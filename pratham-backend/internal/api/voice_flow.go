package api

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/bedrockruntime"
	cm "github.com/aws/aws-sdk-go-v2/service/comprehendmedical"
	transcribe "github.com/aws/aws-sdk-go-v2/service/transcribe"
	transcribetypes "github.com/aws/aws-sdk-go-v2/service/transcribe/types"
	"github.com/aws/aws-lambda-go/events"
	"github.com/jackc/pgx/v5"
	"github.com/prathamcare/backend/internal/models"
)

type extractedEntities struct {
	PatientName string         `json:"patient_name,omitempty"`
	VisitType   string         `json:"visit_type,omitempty"`
	Symptoms    []string       `json:"symptoms,omitempty"`
	Vitals      map[string]any `json:"vitals,omitempty"`
}

func (h *Handler) handleVoiceTranscribe(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}

	var in struct {
		ObjectKey         string `json:"object_key"`
		Language          string `json:"language"`
		Context           string `json:"context"`
		PatientID         string `json:"patient_id"`
		MockTranscription string `json:"mock_transcription"`
	}
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	if strings.TrimSpace(in.PatientID) == "" {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "patient_id is required")
	}
	if strings.TrimSpace(in.ObjectKey) == "" && strings.TrimSpace(in.MockTranscription) == "" {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "object_key is required when mock_transcription is empty")
	}

	ashaUserID, ashaResolveErr := h.resolveASHAUserID(ctx, claims.Subject)
	warnings := make([]string, 0, 2)
	if ashaResolveErr != nil {
		warnings = append(warnings, "ASHA user is not mapped in Aurora users table; encounter write may fail")
	}

	patientIDForWrites := in.PatientID
	if h.deps != nil && h.deps.Aurora != nil {
		patient, pErr := h.deps.Aurora.EnsurePatientByExternalID(ctx, in.PatientID)
		if pErr == nil {
			patientIDForWrites = patient.PatientID
		} else {
			warnings = append(warnings, "patient mapping failed in Aurora; using request patient_id directly")
		}
	}

	var voiceJobID string
	if h.deps != nil && h.deps.Aurora != nil && ashaUserID != "" {
		created, cErr := h.deps.Aurora.CreateVoiceJob(ctx, models.VoiceJob{
			PatientID:           patientIDForWrites,
			ASHAUserID:          ashaUserID,
			S3Bucket:            h.cfg.S3VoiceBucket,
			S3Key:               in.ObjectKey,
			LanguageCode:        defaultString(in.Language, "hi-IN"),
			Context:             defaultString(in.Context, "asha_home_visit"),
			ProcessingStatus:    "transcribing",
			ProcessingStartedAt: time.Now().UTC(),
		})
		if cErr == nil {
			voiceJobID = created.VoiceJobID
		} else {
			warnings = append(warnings, "voice job could not be recorded in Aurora")
		}
	}

	transcriptionText := strings.TrimSpace(in.MockTranscription)
	var transcriptionJobID string
	if transcriptionText == "" {
		transcriptionText, transcriptionJobID, err = h.runTranscribeJob(ctx, in.ObjectKey, in.Language)
		if err != nil {
			if voiceJobID != "" && h.deps != nil && h.deps.Aurora != nil {
				now := time.Now().UTC()
				_ = h.deps.Aurora.UpdateVoiceJobStatus(ctx, voiceJobID, "failed", transcriptionJobID, "TRANSCRIBE_FAILED", err.Error(), &now)
			}
			return h.error(http.StatusBadGateway, "SERVICE_UNAVAILABLE", "transcription failed: "+err.Error())
		}
	}
	if strings.TrimSpace(transcriptionText) == "" {
		if voiceJobID != "" && h.deps != nil && h.deps.Aurora != nil {
			now := time.Now().UTC()
			_ = h.deps.Aurora.UpdateVoiceJobStatus(ctx, voiceJobID, "failed", transcriptionJobID, "EMPTY_TRANSCRIPT", "empty transcript returned", &now)
		}
		return h.error(http.StatusBadGateway, "SERVICE_UNAVAILABLE", "empty transcription")
	}

	translation := transcriptionText
	extracted, alerts, bedrockErr := h.runBedrockExtraction(ctx, transcriptionText)
	if bedrockErr != nil {
		extractedFallback, alertsFallback := extractClinicalSignals(transcriptionText)
		extracted = map[string]any{
			"patient_name": extractedFallback.PatientName,
			"visit_type":   extractedFallback.VisitType,
			"symptoms":     extractedFallback.Symptoms,
			"vitals":       extractedFallback.Vitals,
		}
		alerts = alertsFallback
		warnings = append(warnings, "Bedrock extraction unavailable; fallback extraction used")
	}
	if v, ok := extracted["translation"].(string); ok && strings.TrimSpace(v) != "" {
		translation = v
	}

	medicalEntities := h.detectMedicalEntities(ctx, translation)

	if voiceJobID != "" && h.deps != nil && h.deps.Aurora != nil {
		now := time.Now().UTC()
		_ = h.deps.Aurora.UpdateVoiceJobStatus(ctx, voiceJobID, "completed", transcriptionJobID, "", "", &now)
	}

	resp := map[string]any{
		"voice_job_id":      voiceJobID,
		"transcription_job": transcriptionJobID,
		"transcription":     transcriptionText,
		"translation":       translation,
		"extracted_entities": extracted,
		"clinical_alerts":   alerts,
		"medical_entities":  medicalEntities,
	}
	if len(warnings) > 0 {
		resp["warnings"] = warnings
	}
	return h.json(http.StatusOK, resp)
}

func (h *Handler) handleEncounterCreate(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}

	var in struct {
		PatientID         string         `json:"patient_id"`
		VisitType         string         `json:"visit_type"`
		OccurredAt        string         `json:"occurred_at"`
		Transcription     string         `json:"transcription"`
		ExtractedEntities map[string]any `json:"extracted_entities"`
		ClinicalAlerts    []map[string]any `json:"clinical_alerts"`
		Translation       string         `json:"translation"`
		SourceAudioKey    string         `json:"source_audio_key"`
	}
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	if strings.TrimSpace(in.PatientID) == "" {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "patient_id is required")
	}
	if strings.TrimSpace(in.Transcription) == "" {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "transcription is required")
	}
	if strings.TrimSpace(in.VisitType) == "" {
		in.VisitType = "home_visit"
	}

	occurredAt := time.Now().UTC()
	if strings.TrimSpace(in.OccurredAt) != "" {
		if parsed, pErr := time.Parse(time.RFC3339, in.OccurredAt); pErr == nil {
			occurredAt = parsed.UTC()
		}
	}

	if h.deps == nil || h.deps.Aurora == nil {
		return h.json(http.StatusAccepted, map[string]any{
			"encounter_id":      "enc_" + newID(),
			"sync_status":       "queued",
			"fhir_encounter_id": "",
			"message":           "Aurora repository is not configured; encounter accepted without persistence",
		})
	}

	ashaUserID, resolveErr := h.resolveASHAUserID(ctx, claims.Subject)
	if resolveErr != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "ASHA user mapping missing in Aurora users table")
	}

	patient, pErr := h.deps.Aurora.EnsurePatientByExternalID(ctx, in.PatientID)
	if pErr != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "unable to map patient_id: "+pErr.Error())
	}

	extractedJSON, _ := json.Marshal(in.ExtractedEntities)
	alertsJSON, _ := json.Marshal(in.ClinicalAlerts)
	if strings.TrimSpace(in.Translation) == "" {
		in.Translation = in.Transcription
	}

	fhirEncounterID, fhirSyncStatus, fhirErr := h.createFHIREncounter(ctx, patient.FHIRPatientID, in.VisitType, occurredAt, ashaUserID)
	if fhirSyncStatus == "" {
		fhirSyncStatus = "queued"
	}

	idempotencyKey := strings.TrimSpace(req.Headers["Idempotency-Key"])
	if idempotencyKey == "" {
		idempotencyKey = strings.TrimSpace(req.Headers["idempotency-key"])
	}
	if idempotencyKey == "" {
		idempotencyKey = "enc-" + newID()
	}

	enc, cErr := h.deps.Aurora.CreateEncounter(ctx, models.EncounterRecord{
		PatientID:         patient.PatientID,
		ASHAUserID:        ashaUserID,
		VisitType:         in.VisitType,
		Status:            "completed",
		OccurredAt:        occurredAt,
		SourceAudioBucket: h.cfg.S3VoiceBucket,
		SourceAudioKey:    in.SourceAudioKey,
		TranscriptionText: in.Transcription,
		TranslationText:   in.Translation,
		ExtractedEntities: string(extractedJSON),
		ClinicalAlerts:    string(alertsJSON),
		FHIREncounterID:   fhirEncounterID,
		SyncStatus:        fhirSyncStatus,
		IdempotencyKey:    idempotencyKey,
	})
	if cErr != nil {
		if strings.Contains(strings.ToLower(cErr.Error()), "duplicate key") && strings.Contains(strings.ToLower(cErr.Error()), "idempotency_key") {
			return h.error(http.StatusConflict, "VALIDATION_ERROR", "duplicate encounter submission")
		}
		return h.error(http.StatusInternalServerError, "INTERNAL_SERVER_ERROR", "failed to create encounter")
	}

	alertRows := make([]models.EncounterAlert, 0, len(in.ClinicalAlerts))
	for _, alert := range in.ClinicalAlerts {
		alertRows = append(alertRows, models.EncounterAlert{
			Severity:  fmt.Sprintf("%v", alert["severity"]),
			AlertCode: fmt.Sprintf("%v", alert["code"]),
			Message:   fmt.Sprintf("%v", alert["message"]),
			Metadata:  asJSONString(alert),
		})
	}
	if err := h.deps.Aurora.CreateEncounterAlerts(ctx, enc.EncounterID, alertRows); err != nil {
		return h.error(http.StatusInternalServerError, "INTERNAL_SERVER_ERROR", "failed to create encounter alerts")
	}

	out := map[string]any{
		"encounter_id":      enc.EncounterID,
		"sync_status":       enc.SyncStatus,
		"fhir_encounter_id": enc.FHIREncounterID,
	}
	if fhirErr != nil {
		out["warning"] = "Encounter stored in Aurora but FHIR sync failed"
		out["fhir_error"] = fhirErr.Error()
	}
	return h.json(http.StatusCreated, out)
}

func (h *Handler) resolveASHAUserID(ctx context.Context, cognitoSub string) (string, error) {
	if h.deps == nil || h.deps.Aurora == nil {
		return cognitoSub, nil
	}
	user, err := h.deps.Aurora.GetUserByCognitoSub(ctx, cognitoSub)
	if err == nil {
		return user.UserID, nil
	}
	if strings.Contains(strings.ToLower(err.Error()), "no rows") || strings.Contains(strings.ToLower(err.Error()), "not found") || err == pgx.ErrNoRows {
		return "", err
	}
	return "", err
}

func (h *Handler) runTranscribeJob(ctx context.Context, objectKey, requestedLanguage string) (string, string, error) {
	if h.cfg.S3VoiceBucket == "" {
		return "", "", fmt.Errorf("voice bucket is not configured")
	}
	region := defaultString(h.cfg.AWSRegion, "ap-south-1")
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return "", "", err
	}
	client := transcribe.NewFromConfig(awsCfg)

	jobName := "pc-" + strings.ReplaceAll(newID(), "-", "")
	input := &transcribe.StartTranscriptionJobInput{
		TranscriptionJobName: &jobName,
		Media: &transcribetypes.Media{
			MediaFileUri: stringPtr(fmt.Sprintf("s3://%s/%s", h.cfg.S3VoiceBucket, objectKey)),
		},
	}

	lang := strings.TrimSpace(requestedLanguage)
	if lang != "" {
		input.LanguageCode = transcribetypes.LanguageCode(lang)
	} else {
		input.IdentifyLanguage = boolPtr(true)
		if len(h.cfg.TranscribeLanguages) > 0 {
			opts := make([]transcribetypes.LanguageCode, 0, len(h.cfg.TranscribeLanguages))
			for _, code := range h.cfg.TranscribeLanguages {
				opts = append(opts, transcribetypes.LanguageCode(strings.TrimSpace(code)))
			}
			input.LanguageOptions = opts
		}
	}

	if _, err := client.StartTranscriptionJob(ctx, input); err != nil {
		return "", jobName, err
	}

	waitCtx, cancel := context.WithTimeout(ctx, 65*time.Second)
	defer cancel()

	for {
		select {
		case <-waitCtx.Done():
			return "", jobName, fmt.Errorf("transcription timeout")
		default:
		}

		out, err := client.GetTranscriptionJob(waitCtx, &transcribe.GetTranscriptionJobInput{
			TranscriptionJobName: &jobName,
		})
		if err != nil {
			return "", jobName, err
		}
		if out.TranscriptionJob == nil {
			time.Sleep(2 * time.Second)
			continue
		}

		status := out.TranscriptionJob.TranscriptionJobStatus
		switch status {
		case transcribetypes.TranscriptionJobStatusCompleted:
			uri := ""
			if out.TranscriptionJob.Transcript != nil && out.TranscriptionJob.Transcript.TranscriptFileUri != nil {
				uri = *out.TranscriptionJob.Transcript.TranscriptFileUri
			}
			if uri == "" {
				return "", jobName, fmt.Errorf("transcript file uri missing")
			}
			text, err := fetchTranscriptText(waitCtx, uri)
			return text, jobName, err
		case transcribetypes.TranscriptionJobStatusFailed:
			reason := "transcribe failed"
			if out.TranscriptionJob.FailureReason != nil {
				reason = *out.TranscriptionJob.FailureReason
			}
			return "", jobName, fmt.Errorf(reason)
		default:
			time.Sleep(2 * time.Second)
		}
	}
}

func (h *Handler) runBedrockExtraction(ctx context.Context, transcript string) (map[string]any, []map[string]any, error) {
	if strings.TrimSpace(h.cfg.BedrockModelID) == "" {
		return nil, nil, fmt.Errorf("bedrock model id not configured")
	}
	region := defaultString(strings.TrimSpace(h.cfg.BedrockRegion), defaultString(h.cfg.AWSRegion, "ap-south-1"))
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return nil, nil, err
	}
	client := bedrockruntime.NewFromConfig(awsCfg)

	prompt := "You are a clinical AI for ASHA home visits. " +
		"From transcript, return strict JSON object with keys: translation, extracted_entities, clinical_alerts. " +
		"`translation` must be English. `extracted_entities` must include patient_name, visit_type, symptoms (array), vitals (object). " +
		"`clinical_alerts` must be array of objects with severity, code, message. " +
		"Do not add markdown.\nTranscript:\n" + transcript

	bodyObj := map[string]any{
		"anthropic_version": "bedrock-2023-05-31",
		"max_tokens":        800,
		"temperature":       0.0,
		"messages": []map[string]any{
			{
				"role": "user",
				"content": []map[string]any{
					{"type": "text", "text": prompt},
				},
			},
		},
	}
	body, _ := json.Marshal(bodyObj)

	out, err := client.InvokeModel(ctx, &bedrockruntime.InvokeModelInput{
		ModelId:     &h.cfg.BedrockModelID,
		ContentType: stringPtr("application/json"),
		Accept:      stringPtr("application/json"),
		Body:        body,
	})
	if err != nil {
		return nil, nil, err
	}

	var parsed struct {
		Content []struct {
			Type string `json:"type"`
			Text string `json:"text"`
		} `json:"content"`
	}
	if err := json.Unmarshal(out.Body, &parsed); err != nil {
		return nil, nil, err
	}
	if len(parsed.Content) == 0 {
		return nil, nil, fmt.Errorf("bedrock returned empty content")
	}

	raw := strings.TrimSpace(parsed.Content[0].Text)
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var payload struct {
		Translation       string           `json:"translation"`
		ExtractedEntities map[string]any   `json:"extracted_entities"`
		ClinicalAlerts    []map[string]any `json:"clinical_alerts"`
	}
	if err := json.Unmarshal([]byte(raw), &payload); err != nil {
		return nil, nil, err
	}
	if payload.ExtractedEntities == nil {
		payload.ExtractedEntities = map[string]any{}
	}
	payload.ExtractedEntities["translation"] = payload.Translation
	return payload.ExtractedEntities, payload.ClinicalAlerts, nil
}

func (h *Handler) detectMedicalEntities(ctx context.Context, text string) []map[string]any {
	if strings.TrimSpace(text) == "" {
		return nil
	}
	region := defaultString(h.cfg.AWSRegion, "ap-south-1")
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return nil
	}
	client := cm.NewFromConfig(awsCfg)
	out, err := client.DetectEntitiesV2(ctx, &cm.DetectEntitiesV2Input{
		Text: &text,
	})
	if err != nil {
		return nil
	}

	entities := make([]map[string]any, 0, len(out.Entities))
	for _, entity := range out.Entities {
		item := map[string]any{
			"text":       stringValue(entity.Text),
			"category":   string(entity.Category),
			"type":       string(entity.Type),
			"score":      entity.Score,
			"traits":     entity.Traits,
			"attributes": entity.Attributes,
		}
		entities = append(entities, item)
		if len(entities) >= 20 {
			break
		}
	}
	return entities
}

func (h *Handler) createFHIREncounter(ctx context.Context, fhirPatientID, visitType string, occurredAt time.Time, ashaUserID string) (string, string, error) {
	if h.deps == nil || h.deps.HealthLake == nil {
		return "", "queued", nil
	}
	if strings.TrimSpace(fhirPatientID) == "" {
		return "", "failed", fmt.Errorf("empty fhir patient id")
	}

	resource := models.FHIREncounterResource{
		ResourceType: "Encounter",
		Status:       "finished",
		Class: map[string]any{
			"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode",
			"code":   "AMB",
			"display": "ambulatory",
		},
		Subject: &models.FHIRReference{
			Reference: "Patient/" + fhirPatientID,
		},
		Participant: []map[string]any{
			{
				"individual": map[string]any{
					"reference": "Practitioner/" + ashaUserID,
				},
			},
		},
		Period: map[string]string{
			"start": occurredAt.Format(time.RFC3339),
			"end":   occurredAt.Format(time.RFC3339),
		},
		ReasonCode: []models.FHIRCodeableConcept{
			{Text: visitType},
		},
	}
	id, err := h.deps.HealthLake.CreateEncounter(ctx, resource)
	if err != nil {
		return "", "failed", err
	}
	return id, "synced", nil
}

func fetchTranscriptText(ctx context.Context, transcriptURL string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, transcriptURL, nil)
	if err != nil {
		return "", err
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	if res.StatusCode >= 300 {
		return "", fmt.Errorf("transcript fetch failed with status %d", res.StatusCode)
	}
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return "", err
	}
	var parsed struct {
		Results struct {
			Transcripts []struct {
				Transcript string `json:"transcript"`
			} `json:"transcripts"`
		} `json:"results"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", err
	}
	if len(parsed.Results.Transcripts) == 0 {
		return "", nil
	}
	return strings.TrimSpace(parsed.Results.Transcripts[0].Transcript), nil
}

func extractClinicalSignals(text string) (extractedEntities, []map[string]any) {
	lower := strings.ToLower(text)
	out := extractedEntities{
		PatientName: "Unknown",
		VisitType:   "home_visit",
		Symptoms:    []string{},
		Vitals:      map[string]any{},
	}
	if strings.Contains(lower, "anc") {
		out.VisitType = "anc"
	}
	if strings.Contains(lower, "pnc") {
		out.VisitType = "pnc"
	}
	if strings.Contains(lower, "follow up") || strings.Contains(lower, "follow-up") {
		out.VisitType = "follow_up"
	}
	if strings.Contains(lower, "headache") {
		out.Symptoms = append(out.Symptoms, "headache")
	}
	if strings.Contains(lower, "fever") {
		out.Symptoms = append(out.Symptoms, "fever")
	}

	if m := regexp.MustCompile(`(?i)bp[^0-9]*(\d{2,3})\s*/\s*(\d{2,3})`).FindStringSubmatch(text); len(m) == 3 {
		if s, err := strconv.Atoi(m[1]); err == nil {
			out.Vitals["bp_systolic"] = s
		}
		if d, err := strconv.Atoi(m[2]); err == nil {
			out.Vitals["bp_diastolic"] = d
		}
	}
	if m := regexp.MustCompile(`(?i)weight[^0-9]*(\d{2,3})`).FindStringSubmatch(text); len(m) == 2 {
		if w, err := strconv.Atoi(m[1]); err == nil {
			out.Vitals["weight_kg"] = w
		}
	}

	alerts := make([]map[string]any, 0, 1)
	if s, okS := out.Vitals["bp_systolic"].(int); okS {
		if d, okD := out.Vitals["bp_diastolic"].(int); okD && (s >= 140 || d >= 90) {
			alerts = append(alerts, map[string]any{
				"severity": "high",
				"code":     "HIGH_BP",
				"message":  "Elevated blood pressure detected",
			})
		}
	}
	return out, alerts
}

func asJSONString(v any) string {
	if v == nil {
		return "{}"
	}
	b, err := json.Marshal(v)
	if err != nil {
		return "{}"
	}
	return string(b)
}

func boolPtr(v bool) *bool {
	return &v
}

func stringPtr(v string) *string {
	return &v
}

func stringValue(v *string) string {
	if v == nil {
		return ""
	}
	return *v
}
