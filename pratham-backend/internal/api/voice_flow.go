package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/bedrockruntime"
	bedrocktypes "github.com/aws/aws-sdk-go-v2/service/bedrockruntime/types"
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

func (h *Handler) handleVoiceTranscribe(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}

	var in struct {
		ObjectKey string `json:"object_key"`
		Language  string `json:"language"`
		Context   string `json:"context"`
		PatientID string `json:"patient_id"`
	}
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	if strings.TrimSpace(in.PatientID) == "" {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "patient_id is required")
	}
	if strings.TrimSpace(in.ObjectKey) == "" {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "object_key is required")
	}

	requestID := strings.TrimSpace(req.RequestContext.RequestID)
	startedAt := time.Now().UTC()
	log.Printf("voice_transcribe_start request_id=%s sub=%s patient_id=%s object_key=%s", requestID, claims.Subject, in.PatientID, in.ObjectKey)

	startCtx, cancelStart := context.WithTimeout(ctx, 8*time.Second)
	defer cancelStart()
	transcriptionJobID, err := h.startTranscribeJob(startCtx, in.ObjectKey, in.Language)
	if err != nil {
		log.Printf("voice_transcribe_start_failed request_id=%s error=%v", requestID, err)
		return h.error(http.StatusBadGateway, "SERVICE_UNAVAILABLE", "failed to start transcription: "+err.Error())
	}
	log.Printf("voice_transcribe_started request_id=%s transcription_job_id=%s", requestID, transcriptionJobID)

	if h.deps == nil || h.deps.Aurora == nil {
		queueID, _ := h.enqueueVoiceJobFallback(ctx, claims.Subject, in.PatientID, transcriptionJobID, in.ObjectKey, in.Language, in.Context)
		return h.json(http.StatusAccepted, map[string]any{
			"voice_job_id":      "",
			"transcription_job": transcriptionJobID,
			"processing_status": "transcribing",
			"poll_by":           "transcription_job",
			"queue_id":          queueID,
			"message":           "voice job accepted without Aurora persistence",
		})
	}

	warnings := make([]string, 0, 2)
	ashaUserID := claims.Subject
	resolveCtx, cancelResolve := context.WithTimeout(ctx, 3*time.Second)
	resolvedASHAUserID, ashaResolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject)
	cancelResolve()
	if ashaResolveErr == nil {
		ashaUserID = resolvedASHAUserID
	} else {
		warnings = append(warnings, "ASHA user mapping unavailable; using Cognito sub as fallback")
		log.Printf("voice_transcribe_asha_map_warn request_id=%s cognito_sub=%s error=%v", requestID, claims.Subject, ashaResolveErr)
	}

	patientIDForWrites := in.PatientID
	mapCtx, cancelMap := context.WithTimeout(ctx, 3*time.Second)
	patient, pErr := h.deps.Aurora.EnsurePatientByExternalID(mapCtx, in.PatientID)
	cancelMap()
	if pErr == nil {
		patientIDForWrites = patient.PatientID
	} else if strings.Contains(strings.ToLower(pErr.Error()), "invalid input syntax") {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "patient_id must be a known external id or UUID")
	} else {
		warnings = append(warnings, "patient mapping unavailable; voice job not persisted")
		log.Printf("voice_transcribe_patient_map_warn request_id=%s patient_id=%s error=%v", requestID, in.PatientID, pErr)
	}

	if !looksLikeUUID(patientIDForWrites) {
		queueID, _ := h.enqueueVoiceJobFallback(ctx, claims.Subject, in.PatientID, transcriptionJobID, in.ObjectKey, in.Language, in.Context)
		resp := map[string]any{
			"voice_job_id":      "",
			"transcription_job": transcriptionJobID,
			"processing_status": "transcribing",
			"poll_by":           "transcription_job",
			"queue_id":          queueID,
		}
		if len(warnings) > 0 {
			resp["warnings"] = warnings
		}
		return h.json(http.StatusAccepted, resp)
	}

	createCtx, cancelCreate := context.WithTimeout(ctx, 3*time.Second)
	created, cErr := h.deps.Aurora.CreateVoiceJob(createCtx, models.VoiceJob{
		PatientID:           patientIDForWrites,
		ASHAUserID:          ashaUserID,
		S3Bucket:            h.cfg.S3VoiceBucket,
		S3Key:               in.ObjectKey,
		LanguageCode:        defaultString(in.Language, "en-IN"),
		Context:             defaultString(in.Context, "asha_home_visit"),
		TranscriptionJobID:  transcriptionJobID,
		ProcessingStatus:    "transcribing",
		ProcessingStartedAt: startedAt,
	})
	cancelCreate()
	if cErr != nil {
		log.Printf("voice_transcribe_create_job_warn request_id=%s transcription_job_id=%s error=%v", requestID, transcriptionJobID, cErr)
		queueID, _ := h.enqueueVoiceJobFallback(ctx, claims.Subject, in.PatientID, transcriptionJobID, in.ObjectKey, in.Language, in.Context)
		resp := map[string]any{
			"voice_job_id":      "",
			"transcription_job": transcriptionJobID,
			"processing_status": "transcribing",
			"poll_by":           "transcription_job",
			"queue_id":          queueID,
			"message":           "transcription started; voice job persistence unavailable",
		}
		if len(warnings) > 0 {
			resp["warnings"] = warnings
		}
		return h.json(http.StatusAccepted, resp)
	}

	resp := map[string]any{
		"voice_job_id":      created.VoiceJobID,
		"transcription_job": transcriptionJobID,
		"processing_status": "transcribing",
		"poll_by":           "voice_job_id",
	}
	if len(warnings) > 0 {
		resp["warnings"] = warnings
	}
	return h.json(http.StatusAccepted, resp)
}

func (h *Handler) handleVoiceTranscribeStatus(ctx context.Context, req events.APIGatewayV2HTTPRequest, voiceJobID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}

	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	voiceJob, err := h.deps.Aurora.GetVoiceJobByID(ctx, voiceJobID)
	if err != nil {
		return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "voice job not found")
	}

	if ashaUserID, resolveErr := h.resolveASHAUserID(ctx, claims.Subject); resolveErr == nil {
		if voiceJob.ASHAUserID != "" && ashaUserID != "" && voiceJob.ASHAUserID != ashaUserID {
			return h.error(http.StatusForbidden, "AUTHORIZATION_DENIED", "voice job does not belong to caller")
		}
	}

	status, transcriptURL, failureReason, err := h.checkTranscribeJob(ctx, voiceJob.TranscriptionJobID)
	if err != nil {
		return h.error(http.StatusBadGateway, "SERVICE_UNAVAILABLE", "failed to check transcription: "+err.Error())
	}

	switch status {
	case "in_progress":
		return h.json(http.StatusOK, map[string]any{
			"voice_job_id":      voiceJobID,
			"transcription_job": voiceJob.TranscriptionJobID,
			"processing_status": "transcribing",
		})
	case "failed":
		now := time.Now().UTC()
		_ = h.deps.Aurora.UpdateVoiceJobStatus(ctx, voiceJobID, "failed", voiceJob.TranscriptionJobID, "TRANSCRIBE_FAILED", failureReason, &now)
		return h.json(http.StatusOK, map[string]any{
			"voice_job_id":      voiceJobID,
			"transcription_job": voiceJob.TranscriptionJobID,
			"processing_status": "failed",
			"error":             failureReason,
		})
	}

	transcriptionText, err := fetchTranscriptText(ctx, transcriptURL)
	if err != nil {
		return h.error(http.StatusBadGateway, "SERVICE_UNAVAILABLE", "failed to read transcript: "+err.Error())
	}
	h.logAIDebug("transcribe_raw_text", transcriptionText)
	if strings.TrimSpace(transcriptionText) == "" {
		now := time.Now().UTC()
		_ = h.deps.Aurora.UpdateVoiceJobStatus(ctx, voiceJobID, "failed", voiceJob.TranscriptionJobID, "EMPTY_TRANSCRIPT", "empty transcript returned", &now)
		return h.json(http.StatusOK, map[string]any{
			"voice_job_id":      voiceJobID,
			"transcription_job": voiceJob.TranscriptionJobID,
			"processing_status": "failed",
			"error":             "empty transcript returned",
		})
	}

	warnings := make([]string, 0, 1)
	translation := transcriptionText
	extracted, alerts, bedrockErr := h.runBedrockExtraction(ctx, transcriptionText)
	if bedrockErr != nil {
		log.Printf("voice_transcribe_bedrock_fallback voice_job_id=%s transcription_job_id=%s error=%v", voiceJobID, voiceJob.TranscriptionJobID, bedrockErr)
		extractedFallback, alertsFallback := extractClinicalSignals(transcriptionText)
		extracted = map[string]any{
			"patient_name": extractedFallback.PatientName,
			"visit_type":   extractedFallback.VisitType,
			"symptoms":     extractedFallback.Symptoms,
			"vitals":       extractedFallback.Vitals,
		}
		alerts = alertsFallback
		warnings = append(warnings, "Bedrock extraction unavailable; fallback extraction used: "+bedrockErr.Error())
	}
	if v, ok := extracted["translation"].(string); ok && strings.TrimSpace(v) != "" {
		translation = v
	}
	extracted = enrichExtractedEntities(transcriptionText, translation, extracted, alerts)
	alerts = enrichClinicalAlerts(extracted, alerts)
	medicalEntities := h.detectMedicalEntities(ctx, translation)
	now := time.Now().UTC()
	_ = h.deps.Aurora.UpdateVoiceJobStatus(ctx, voiceJobID, "completed", voiceJob.TranscriptionJobID, "", "", &now)

	resp := map[string]any{
		"voice_job_id":      voiceJobID,
		"transcription_job": voiceJob.TranscriptionJobID,
		"processing_status": "completed",
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

func (h *Handler) handleVoiceTranscribeJobStatus(ctx context.Context, req events.APIGatewayV2HTTPRequest, transcriptionJobID string) (events.APIGatewayV2HTTPResponse, error) {
	if _, err := h.authorize(req, "asha_worker"); err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}

	checkCtx, cancelCheck := context.WithTimeout(ctx, 8*time.Second)
	defer cancelCheck()
	status, transcriptURL, failureReason, err := h.checkTranscribeJob(checkCtx, transcriptionJobID)
	if err != nil {
		return h.error(http.StatusBadGateway, "SERVICE_UNAVAILABLE", "failed to check transcription: "+err.Error())
	}

	switch status {
	case "in_progress":
		return h.json(http.StatusOK, map[string]any{
			"voice_job_id":      "",
			"transcription_job": transcriptionJobID,
			"processing_status": "transcribing",
		})
	case "failed":
		return h.json(http.StatusOK, map[string]any{
			"voice_job_id":      "",
			"transcription_job": transcriptionJobID,
			"processing_status": "failed",
			"error":             failureReason,
		})
	}

	transcriptionText, err := fetchTranscriptText(ctx, transcriptURL)
	if err != nil {
		return h.error(http.StatusBadGateway, "SERVICE_UNAVAILABLE", "failed to read transcript: "+err.Error())
	}
	h.logAIDebug("transcribe_raw_text", transcriptionText)
	if strings.TrimSpace(transcriptionText) == "" {
		return h.json(http.StatusOK, map[string]any{
			"voice_job_id":      "",
			"transcription_job": transcriptionJobID,
			"processing_status": "failed",
			"error":             "empty transcript returned",
		})
	}

	warnings := make([]string, 0, 1)
	translation := transcriptionText
	extracted, alerts, bedrockErr := h.runBedrockExtraction(ctx, transcriptionText)
	if bedrockErr != nil {
		log.Printf("voice_transcribe_bedrock_fallback transcription_job_id=%s error=%v", transcriptionJobID, bedrockErr)
		extractedFallback, alertsFallback := extractClinicalSignals(transcriptionText)
		extracted = map[string]any{
			"patient_name": extractedFallback.PatientName,
			"visit_type":   extractedFallback.VisitType,
			"symptoms":     extractedFallback.Symptoms,
			"vitals":       extractedFallback.Vitals,
		}
		alerts = alertsFallback
		warnings = append(warnings, "Bedrock extraction unavailable; fallback extraction used: "+bedrockErr.Error())
	}
	if v, ok := extracted["translation"].(string); ok && strings.TrimSpace(v) != "" {
		translation = v
	}
	extracted = enrichExtractedEntities(transcriptionText, translation, extracted, alerts)
	alerts = enrichClinicalAlerts(extracted, alerts)
	medicalEntities := h.detectMedicalEntities(ctx, translation)

	resp := map[string]any{
		"voice_job_id":       "",
		"transcription_job":  transcriptionJobID,
		"processing_status":  "completed",
		"transcription":      transcriptionText,
		"translation":        translation,
		"extracted_entities": extracted,
		"clinical_alerts":    alerts,
		"medical_entities":   medicalEntities,
	}
	if len(warnings) > 0 {
		resp["warnings"] = warnings
	}
	return h.json(http.StatusOK, resp)
}

func (h *Handler) handleEncounterCreate(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	requestID := strings.TrimSpace(req.RequestContext.RequestID)

	var in struct {
		PatientID         string         `json:"patient_id"`
		VisitType         string         `json:"visit_type"`
		OccurredAt        string         `json:"occurred_at"`
		Transcription     string         `json:"transcription"`
		ExtractedEntities map[string]any `json:"extracted_entities"`
		MedicalEntities   any            `json:"medical_entities"`
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
	log.Printf("encounter_create_start request_id=%s sub=%s patient_id=%s visit_type=%s", requestID, claims.Subject, in.PatientID, in.VisitType)

	occurredAt := time.Now().UTC()
	if strings.TrimSpace(in.OccurredAt) != "" {
		if parsed, pErr := time.Parse(time.RFC3339, in.OccurredAt); pErr == nil {
			occurredAt = parsed.UTC()
		}
	}

	if h.deps == nil || h.deps.Aurora == nil {
		queueID, queueErr := h.enqueueEncounterFallback(ctx, claims.Subject, in.PatientID, in)
		if queueErr != nil {
			log.Printf("encounter_create_queue_failed request_id=%s error=%v", requestID, queueErr)
		}
		return h.json(http.StatusAccepted, map[string]any{
			"encounter_id":      "enc_" + newID(),
			"sync_status":       "queued",
			"fhir_encounter_id": "",
			"queue_id":          queueID,
			"message":           "Aurora repository is not configured; encounter queued",
		})
	}

	warnings := make([]string, 0, 3)

	ashaUserID := claims.Subject
	resolveCtx, cancelResolve := context.WithTimeout(ctx, 3*time.Second)
	resolvedASHAUserID, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject)
	cancelResolve()
	if resolveErr == nil {
		ashaUserID = resolvedASHAUserID
	} else {
		warnings = append(warnings, "ASHA mapping unavailable; using Cognito subject")
		log.Printf("encounter_create_asha_map_warn request_id=%s sub=%s error=%v", requestID, claims.Subject, resolveErr)
	}

	patientMapCtx, cancelPatientMap := context.WithTimeout(ctx, 3*time.Second)
	patient, pErr := h.deps.Aurora.EnsurePatientByExternalID(patientMapCtx, in.PatientID)
	cancelPatientMap()
	if pErr != nil {
		if strings.Contains(strings.ToLower(pErr.Error()), "invalid input syntax") {
			return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "unable to map patient_id: "+pErr.Error())
		}
		queueID, queueErr := h.enqueueEncounterFallback(ctx, claims.Subject, in.PatientID, in)
		if queueErr != nil {
			log.Printf("encounter_create_queue_failed request_id=%s error=%v", requestID, queueErr)
			return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "encounter persistence unavailable")
		}
		log.Printf("encounter_create_patient_map_warn request_id=%s patient_id=%s error=%v queue_id=%s", requestID, in.PatientID, pErr, queueID)
		return h.json(http.StatusAccepted, map[string]any{
			"encounter_id":      "enc_" + newID(),
			"sync_status":       "queued",
			"fhir_encounter_id": "",
			"queue_id":          queueID,
			"warning":           "patient mapping unavailable; encounter queued",
		})
	}

	if !looksLikeUUID(patient.PatientID) {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "unable to map patient_id to internal UUID")
	}

	if in.ExtractedEntities == nil {
		in.ExtractedEntities = map[string]any{}
	}
	if in.MedicalEntities != nil {
		in.ExtractedEntities["medical_entities"] = in.MedicalEntities
	}
	extractedJSON, _ := json.Marshal(in.ExtractedEntities)
	alertsJSON, _ := json.Marshal(in.ClinicalAlerts)
	if strings.TrimSpace(in.Translation) == "" {
		in.Translation = in.Transcription
	}

	fhirCtx, cancelFHIR := context.WithTimeout(ctx, 5*time.Second)
	fhirEncounterID, fhirSyncStatus, fhirErr := h.createFHIREncounter(fhirCtx, patient.FHIRPatientID, in.VisitType, occurredAt, ashaUserID)
	cancelFHIR()
	if fhirSyncStatus == "" {
		fhirSyncStatus = "queued"
	}
	if fhirErr != nil {
		fhirSyncStatus = "queued"
		warnings = append(warnings, "FHIR sync queued for retry")
		log.Printf("encounter_create_fhir_warn request_id=%s patient_id=%s error=%v", requestID, patient.PatientID, fhirErr)
	} else if !strings.EqualFold(fhirSyncStatus, "synced") {
		warnings = append(warnings, "FHIR sync queued for retry")
	}

	idempotencyKey := strings.TrimSpace(headerValue(req.Headers, "Idempotency-Key"))
	if idempotencyKey == "" {
		idempotencyKey = "enc-" + newID()
	}

	createCtx, cancelCreate := context.WithTimeout(ctx, 4*time.Second)
	enc, cErr := h.deps.Aurora.CreateEncounter(createCtx, models.EncounterRecord{
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
	cancelCreate()
	if cErr != nil {
		if strings.Contains(strings.ToLower(cErr.Error()), "duplicate key") && strings.Contains(strings.ToLower(cErr.Error()), "idempotency_key") {
			return h.error(http.StatusConflict, "VALIDATION_ERROR", "duplicate encounter submission")
		}
		queueID, queueErr := h.enqueueEncounterFallback(ctx, claims.Subject, in.PatientID, in)
		if queueErr != nil {
			log.Printf("encounter_create_failed request_id=%s error=%v queue_error=%v", requestID, cErr, queueErr)
			return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to persist encounter")
		}
		log.Printf("encounter_create_persist_warn request_id=%s error=%v queue_id=%s", requestID, cErr, queueID)
		resp := map[string]any{
			"encounter_id":      "enc_" + newID(),
			"sync_status":       "queued",
			"fhir_encounter_id": "",
			"queue_id":          queueID,
			"warning":           "encounter queued because persistence is unavailable",
		}
		if len(warnings) > 0 {
			resp["warnings"] = warnings
		}
		return h.json(http.StatusAccepted, resp)
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
	alertCtx, cancelAlerts := context.WithTimeout(ctx, 3*time.Second)
	if err := h.deps.Aurora.CreateEncounterAlerts(alertCtx, enc.EncounterID, alertRows); err != nil {
		warnings = append(warnings, "encounter alerts persistence failed")
		log.Printf("encounter_create_alerts_warn request_id=%s encounter_id=%s error=%v", requestID, enc.EncounterID, err)
	}
	cancelAlerts()

	out := map[string]any{
		"encounter_id":      enc.EncounterID,
		"sync_status":       enc.SyncStatus,
		"fhir_encounter_id": enc.FHIREncounterID,
	}
	if fhirErr != nil || !strings.EqualFold(fhirSyncStatus, "synced") {
		out["warning"] = "Encounter stored in Aurora; FHIR sync queued for retry"
		if fhirErr != nil {
			out["fhir_error"] = fhirErr.Error()
		}
		if queueID, qErr := h.enqueueFHIRSyncFallback(ctx, claims.Subject, patient.PatientID, map[string]any{
			"encounter_id":    enc.EncounterID,
			"fhir_patient_id": patient.FHIRPatientID,
			"visit_type":      enc.VisitType,
			"occurred_at":     enc.OccurredAt.Format(time.RFC3339),
			"asha_user_id":    enc.ASHAUserID,
		}); qErr == nil {
			out["fhir_retry_queue_id"] = queueID
		}
	}
	if len(warnings) > 0 {
		out["warnings"] = warnings
	}
	log.Printf("encounter_create_done request_id=%s encounter_id=%s sync_status=%s", requestID, enc.EncounterID, enc.SyncStatus)
	return h.json(http.StatusCreated, out)
}

func (h *Handler) enqueueEncounterFallback(ctx context.Context, userID, patientID string, payload any) (string, error) {
	if h.deps == nil || h.deps.Dynamo == nil {
		return "", fmt.Errorf("dynamo repository is not configured")
	}
	queueID := "oq_" + newID()
	now := time.Now().UTC()
	payloadJSON, _ := json.Marshal(payload)
	writeCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	err := h.deps.Dynamo.EnqueueOfflineAction(writeCtx, models.OfflineQueueItem{
		PatientID:    patientID,
		Timestamp:    now.Format(time.RFC3339Nano),
		QueueID:      queueID,
		UserID:       userID,
		ActionType:   "create",
		ResourceType: "encounter",
		ResourceID:   "",
		Payload:      string(payloadJSON),
		Status:       "queued",
		RetryCount:   0,
		CreatedAt:    now,
	})
	if err != nil {
		return "", err
	}
	return queueID, nil
}

func (h *Handler) enqueueVoiceJobFallback(ctx context.Context, userID, patientID, transcriptionJobID, objectKey, language, visitContext string) (string, error) {
	if h.deps == nil || h.deps.Dynamo == nil {
		return "", fmt.Errorf("dynamo repository is not configured")
	}
	queueID := "oq_" + newID()
	now := time.Now().UTC()
	payload := map[string]any{
		"transcription_job": transcriptionJobID,
		"object_key":        objectKey,
		"language":          defaultString(language, "en-IN"),
		"context":           defaultString(visitContext, "asha_home_visit"),
	}
	payloadJSON, _ := json.Marshal(payload)
	writeCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	err := h.deps.Dynamo.EnqueueOfflineAction(writeCtx, models.OfflineQueueItem{
		PatientID:    patientID,
		Timestamp:    now.Format(time.RFC3339Nano),
		QueueID:      queueID,
		UserID:       userID,
		ActionType:   "create",
		ResourceType: "voice_job",
		ResourceID:   transcriptionJobID,
		Payload:      string(payloadJSON),
		Status:       "queued",
		RetryCount:   0,
		CreatedAt:    now,
	})
	if err != nil {
		return "", err
	}
	return queueID, nil
}

func (h *Handler) enqueueFHIRSyncFallback(ctx context.Context, userID, patientID string, payload any) (string, error) {
	if h.deps == nil || h.deps.Dynamo == nil {
		return "", fmt.Errorf("dynamo repository is not configured")
	}
	queueID := "oq_" + newID()
	now := time.Now().UTC()
	payloadJSON, _ := json.Marshal(payload)
	writeCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()
	err := h.deps.Dynamo.EnqueueOfflineAction(writeCtx, models.OfflineQueueItem{
		PatientID:    patientID,
		Timestamp:    now.Format(time.RFC3339Nano),
		QueueID:      queueID,
		UserID:       userID,
		ActionType:   "create",
		ResourceType: "fhir_sync",
		ResourceID:   "",
		Payload:      string(payloadJSON),
		Status:       "queued",
		RetryCount:   0,
		CreatedAt:    now,
	})
	if err != nil {
		return "", err
	}
	return queueID, nil
}

func (h *Handler) handleVoiceHistory(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}

	limit := parseLimit(req.QueryStringParameters, 25, 100)
	items := make([]map[string]any, 0, limit)
	warnings := make([]string, 0, 1)

	if h.deps == nil || h.deps.Aurora == nil {
		warnings = append(warnings, "Aurora repository is not configured")
	} else {
		ashaUserID := claims.Subject
		resolveCtx, cancelResolve := context.WithTimeout(ctx, 3*time.Second)
		if resolved, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject); resolveErr == nil {
			ashaUserID = resolved
		} else {
			warnings = append(warnings, "ASHA user mapping unavailable; using Cognito sub")
		}
		cancelResolve()

		listCtx, cancelList := context.WithTimeout(ctx, 4*time.Second)
		jobs, listErr := h.deps.Aurora.ListVoiceJobsByASHA(listCtx, ashaUserID, limit)
		cancelList()
		if listErr != nil {
			warnings = append(warnings, "Unable to fetch voice history from Aurora")
		} else {
			for _, j := range jobs {
				items = append(items, map[string]any{
					"voice_job_id":       j.VoiceJobID,
					"patient_id":         j.PatientID,
					"processing_status":  j.ProcessingStatus,
					"transcription_job":  j.TranscriptionJobID,
					"source_audio_key":   j.S3Key,
					"language":           j.LanguageCode,
					"context":            j.Context,
					"error_code":         j.ErrorCode,
					"error_message":      j.ErrorMessage,
					"processing_started": j.ProcessingStartedAt.UTC().Format(time.RFC3339),
					"created_at":         j.CreatedAt.UTC().Format(time.RFC3339),
				})
			}
		}
	}

	if h.deps != nil && h.deps.Dynamo != nil {
		queueCtx, cancelQueue := context.WithTimeout(ctx, 3*time.Second)
		qItems, qErr := h.deps.Dynamo.ListOfflineQueueByUser(queueCtx, claims.Subject, limit)
		cancelQueue()
		if qErr != nil {
			warnings = append(warnings, "Unable to fetch queued voice jobs")
		} else {
			for _, q := range qItems {
				if !strings.EqualFold(q.ResourceType, "voice_job") {
					continue
				}
				items = append(items, map[string]any{
					"voice_job_id":       "",
					"patient_id":         q.PatientID,
					"processing_status":  q.Status,
					"transcription_job":  q.ResourceID,
					"source_audio_key":   "",
					"language":           "",
					"context":            "queued",
					"error_code":         "",
					"error_message":      "",
					"processing_started": q.CreatedAt.UTC().Format(time.RFC3339),
					"created_at":         q.CreatedAt.UTC().Format(time.RFC3339),
					"queue_id":           q.QueueID,
				})
			}
		}
	}

	resp := map[string]any{
		"items": items,
		"count": len(items),
	}
	if len(warnings) > 0 {
		resp["warnings"] = warnings
	}
	return h.json(http.StatusOK, resp)
}

func (h *Handler) handleEncounterHistory(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}

	limit := parseLimit(req.QueryStringParameters, 25, 100)
	encounters := make([]map[string]any, 0, limit)
	queued := make([]map[string]any, 0, 10)
	warnings := make([]string, 0, 2)

	if h.deps != nil && h.deps.Aurora != nil {
		ashaUserID := claims.Subject
		resolveCtx, cancelResolve := context.WithTimeout(ctx, 3*time.Second)
		if resolved, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject); resolveErr == nil {
			ashaUserID = resolved
		} else {
			warnings = append(warnings, "ASHA mapping unavailable; using Cognito sub")
		}
		cancelResolve()

		listCtx, cancelList := context.WithTimeout(ctx, 4*time.Second)
		rows, listErr := h.deps.Aurora.ListEncountersByASHA(listCtx, ashaUserID, limit)
		cancelList()
		if listErr != nil {
			warnings = append(warnings, "Unable to fetch encounter history from Aurora")
		} else {
			for _, e := range rows {
				encounters = append(encounters, map[string]any{
					"encounter_id":      e.EncounterID,
					"patient_id":        e.PatientID,
					"visit_type":        e.VisitType,
					"status":            e.Status,
					"sync_status":       e.SyncStatus,
					"fhir_encounter_id": e.FHIREncounterID,
					"occurred_at":       e.OccurredAt.UTC().Format(time.RFC3339),
					"created_at":        e.CreatedAt.UTC().Format(time.RFC3339),
				})
			}
		}
	} else {
		warnings = append(warnings, "Aurora repository is not configured")
	}

	if h.deps != nil && h.deps.Dynamo != nil {
		queueCtx, cancelQueue := context.WithTimeout(ctx, 3*time.Second)
		qItems, qErr := h.deps.Dynamo.ListOfflineQueueByUser(queueCtx, claims.Subject, limit)
		cancelQueue()
		if qErr != nil {
			warnings = append(warnings, "Unable to fetch offline queue")
		} else {
			for _, q := range qItems {
				if !(strings.EqualFold(q.ResourceType, "encounter") || strings.EqualFold(q.ActionType, "create")) {
					continue
				}
				queued = append(queued, map[string]any{
					"queue_id":     q.QueueID,
					"patient_id":   q.PatientID,
					"status":       q.Status,
					"resource_type": q.ResourceType,
					"action_type":  q.ActionType,
					"created_at":   q.CreatedAt.UTC().Format(time.RFC3339),
				})
			}
		}
	}

	resp := map[string]any{
		"encounters": encounters,
		"queued":     queued,
		"count":      len(encounters),
	}
	if len(warnings) > 0 {
		resp["warnings"] = warnings
	}
	return h.json(http.StatusOK, resp)
}

func (h *Handler) handleEncounterDetail(ctx context.Context, req events.APIGatewayV2HTTPRequest, encounterID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	ownerID := claims.Subject
	resolveCtx, cancelResolve := context.WithTimeout(ctx, 3*time.Second)
	if resolved, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject); resolveErr == nil {
		ownerID = resolved
	}
	cancelResolve()

	readCtx, cancelRead := context.WithTimeout(ctx, 4*time.Second)
	encounter, readErr := h.deps.Aurora.GetEncounterByID(readCtx, encounterID)
	cancelRead()
	if readErr != nil {
		if errors.Is(readErr, pgx.ErrNoRows) {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "encounter not found")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "unable to fetch encounter details")
	}
	if ownerID != "" && encounter.ASHAUserID != "" && encounter.ASHAUserID != ownerID {
		return h.error(http.StatusForbidden, "AUTHORIZATION_DENIED", "encounter does not belong to caller")
	}

	extractedEntities := map[string]any{}
	if strings.TrimSpace(encounter.ExtractedEntities) != "" {
		_ = json.Unmarshal([]byte(encounter.ExtractedEntities), &extractedEntities)
	}
	clinicalAlerts := make([]map[string]any, 0)
	if strings.TrimSpace(encounter.ClinicalAlerts) != "" {
		_ = json.Unmarshal([]byte(encounter.ClinicalAlerts), &clinicalAlerts)
	}

	resp := map[string]any{
		"encounter_id":      encounter.EncounterID,
		"patient_id":        encounter.PatientID,
		"visit_type":        encounter.VisitType,
		"status":            encounter.Status,
		"sync_status":       encounter.SyncStatus,
		"fhir_encounter_id": encounter.FHIREncounterID,
		"occurred_at":       encounter.OccurredAt.UTC().Format(time.RFC3339),
		"created_at":        encounter.CreatedAt.UTC().Format(time.RFC3339),
		"updated_at":        encounter.UpdatedAt.UTC().Format(time.RFC3339),
		"transcription":     encounter.TranscriptionText,
		"translation":       encounter.TranslationText,
		"extracted_entities": extractedEntities,
		"clinical_alerts":   clinicalAlerts,
	}
	if strings.TrimSpace(encounter.SourceAudioBucket) != "" {
		resp["source_audio_bucket"] = encounter.SourceAudioBucket
	}
	if strings.TrimSpace(encounter.SourceAudioKey) != "" {
		resp["source_audio_key"] = encounter.SourceAudioKey
	}

	return h.json(http.StatusOK, resp)
}

func parseLimit(params map[string]string, fallback, max int) int {
	limit := fallback
	if params == nil {
		return limit
	}
	if raw, ok := params["limit"]; ok {
		if n, err := strconv.Atoi(strings.TrimSpace(raw)); err == nil && n > 0 {
			limit = n
		}
	}
	if limit > max {
		limit = max
	}
	return limit
}

func (h *Handler) handleSyncReplay(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Dynamo == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "dynamo repository is not configured")
	}
	if h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	var in struct {
		MaxItems int `json:"max_items"`
	}
	if strings.TrimSpace(req.Body) != "" {
		_ = json.Unmarshal([]byte(req.Body), &in)
	}
	limit := in.MaxItems
	if limit <= 0 || limit > 50 {
		limit = 10
	}

	listCtx, cancelList := context.WithTimeout(ctx, 4*time.Second)
	items, listErr := h.deps.Dynamo.ListOfflineQueueByUser(listCtx, claims.Subject, 100)
	cancelList()
	if listErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to read sync queue")
	}

	type fhirReplayPayload struct {
		EncounterID   string `json:"encounter_id"`
		FHIRPatientID string `json:"fhir_patient_id"`
		VisitType     string `json:"visit_type"`
		OccurredAt    string `json:"occurred_at"`
		ASHAUserID    string `json:"asha_user_id"`
	}

	processed := 0
	failed := 0
	results := make([]map[string]any, 0, limit)

	for _, item := range items {
		if processed >= limit {
			break
		}
		if !strings.EqualFold(item.ResourceType, "fhir_sync") || !strings.EqualFold(item.Status, "queued") {
			continue
		}

		var payload fhirReplayPayload
		if err := json.Unmarshal([]byte(item.Payload), &payload); err != nil {
			failed++
			results = append(results, map[string]any{
				"queue_id": item.QueueID,
				"status":   "failed",
				"error":    "invalid payload",
			})
			continue
		}
		occurredAt := time.Now().UTC()
		if parsed, pErr := time.Parse(time.RFC3339, strings.TrimSpace(payload.OccurredAt)); pErr == nil {
			occurredAt = parsed.UTC()
		}
		if strings.TrimSpace(payload.VisitType) == "" {
			payload.VisitType = "home_visit"
		}
		if strings.TrimSpace(payload.ASHAUserID) == "" {
			payload.ASHAUserID = claims.Subject
		}

		fhirCtx, cancelFHIR := context.WithTimeout(ctx, 12*time.Second)
		fhirEncounterID, syncStatus, fhirErr := h.createFHIREncounter(fhirCtx, payload.FHIRPatientID, payload.VisitType, occurredAt, payload.ASHAUserID)
		cancelFHIR()
		if fhirErr != nil || !strings.EqualFold(syncStatus, "synced") {
			errMsg := "fhir sync failed"
			if fhirErr != nil {
				errMsg = fhirErr.Error()
			}
			failed++
			results = append(results, map[string]any{
				"queue_id": item.QueueID,
				"status":   "failed",
				"error":    errMsg,
			})
			continue
		}

		if strings.TrimSpace(payload.EncounterID) != "" {
			updateCtx, cancelUpdate := context.WithTimeout(ctx, 3*time.Second)
			_ = h.deps.Aurora.UpdateEncounterFHIRSync(updateCtx, payload.EncounterID, fhirEncounterID, "synced")
			cancelUpdate()
		}
		markCtx, cancelMark := context.WithTimeout(ctx, 3*time.Second)
		markErr := h.deps.Dynamo.MarkOfflineActionProcessed(markCtx, item.QueueID)
		cancelMark()
		if markErr != nil {
			failed++
			results = append(results, map[string]any{
				"queue_id": item.QueueID,
				"status":   "failed",
				"error":    "synced but failed to mark processed",
			})
			continue
		}

		processed++
		results = append(results, map[string]any{
			"queue_id":          item.QueueID,
			"status":            "processed",
			"fhir_encounter_id": fhirEncounterID,
			"encounter_id":      payload.EncounterID,
		})
	}

	return h.json(http.StatusOK, map[string]any{
		"processed": processed,
		"failed":    failed,
		"results":   results,
	})
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

func (h *Handler) startTranscribeJob(ctx context.Context, objectKey, requestedLanguage string) (string, error) {
	if h.cfg.S3VoiceBucket == "" {
		return "", fmt.Errorf("voice bucket is not configured")
	}
	region := defaultString(h.cfg.AWSRegion, "ap-south-1")
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return "", err
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
		return "", err
	}
	return jobName, nil
}

func (h *Handler) checkTranscribeJob(ctx context.Context, transcriptionJobID string) (status string, transcriptURL string, failureReason string, err error) {
	region := defaultString(h.cfg.AWSRegion, "ap-south-1")
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return "", "", "", err
	}
	client := transcribe.NewFromConfig(awsCfg)
	out, err := client.GetTranscriptionJob(ctx, &transcribe.GetTranscriptionJobInput{
		TranscriptionJobName: stringPtr(transcriptionJobID),
	})
	if err != nil {
		return "", "", "", err
	}
	if out.TranscriptionJob == nil {
		return "in_progress", "", "", nil
	}
	switch out.TranscriptionJob.TranscriptionJobStatus {
	case transcribetypes.TranscriptionJobStatusCompleted:
		if out.TranscriptionJob.Transcript == nil || out.TranscriptionJob.Transcript.TranscriptFileUri == nil {
			return "failed", "", "transcript file uri missing", nil
		}
		return "completed", *out.TranscriptionJob.Transcript.TranscriptFileUri, "", nil
	case transcribetypes.TranscriptionJobStatusFailed:
		if out.TranscriptionJob.FailureReason != nil {
			return "failed", "", *out.TranscriptionJob.FailureReason, nil
		}
		return "failed", "", "transcribe failed", nil
	default:
		return "in_progress", "", "", nil
	}
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
		"`translation` must be English. `extracted_entities` must include patient_name, visit_type, symptoms (array), symptom_details (array of objects), vitals (object), medications_mentioned (array), " +
		"clinical_summary (string), referral_urgency (immediate|within_24h|routine), asha_next_steps (array), red_flags (array), and should also include if present: " +
		"age_years, chief_complaint, duration_days, symptom_duration_text, body_site, suspected_conditions (array), risk_factors (array), follow_up_recommendations (array), " +
		"pregnancy_context (object with is_pregnant, gravida, parity, gestational_age_weeks, anc_visits_completed, high_risk_pregnancy, expected_delivery_date), " +
		"immunization_context (object with due_vaccines array, missed_vaccines array, last_vaccine_date, child_age_months). " +
		"`translation` must ALWAYS be in English regardless of source language and code-mixing. " +
		"All string values inside `extracted_entities` must be in English. " +
		"Do not rewrite, normalize, or translate the original transcript text itself; only produce the structured JSON output. " +
		"`clinical_alerts` must be array of objects with severity, code, message, recommended_action. " +
		"Do not add markdown.\nTranscript:\n" + transcript
	h.logAIDebug("bedrock_prompt", prompt)

	maxTokens := int32(4000)
	temperature := float32(0.0)
	out, err := client.Converse(ctx, &bedrockruntime.ConverseInput{
		ModelId: &h.cfg.BedrockModelID,
		Messages: []bedrocktypes.Message{
			{
				Role: bedrocktypes.ConversationRoleUser,
				Content: []bedrocktypes.ContentBlock{
					&bedrocktypes.ContentBlockMemberText{Value: prompt},
				},
			},
		},
		InferenceConfig: &bedrocktypes.InferenceConfiguration{
			MaxTokens:  &maxTokens,
			Temperature: &temperature,
		},
	})
	if err != nil {
		return nil, nil, err
	}
	if raw, marshalErr := json.Marshal(out); marshalErr == nil {
		h.logAIDebug("bedrock_raw_response", string(raw))
	} else {
		h.logAIDebug("bedrock_raw_response", fmt.Sprintf("%+v", out))
	}

	responseText, err := extractTextFromConverseOutput(out)
	if err != nil {
		return nil, nil, err
	}

	raw := strings.TrimSpace(responseText)
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
		jsonOnly := extractJSONObject(raw)
		if jsonOnly == "" {
			return nil, nil, err
		}
		if err2 := json.Unmarshal([]byte(jsonOnly), &payload); err2 != nil {
			return nil, nil, err2
		}
	}
	if payload.ExtractedEntities == nil {
		payload.ExtractedEntities = map[string]any{}
	}
	payload.ExtractedEntities["translation"] = payload.Translation
	return payload.ExtractedEntities, payload.ClinicalAlerts, nil
}

func extractTextFromConverseOutput(out *bedrockruntime.ConverseOutput) (string, error) {
	if out == nil || out.Output == nil {
		return "", fmt.Errorf("bedrock returned empty output")
	}
	msgOut, ok := out.Output.(*bedrocktypes.ConverseOutputMemberMessage)
	if !ok {
		return "", fmt.Errorf("bedrock returned unsupported output type")
	}
	if len(msgOut.Value.Content) == 0 {
		return "", fmt.Errorf("bedrock returned empty content")
	}

	var sb strings.Builder
	for _, block := range msgOut.Value.Content {
		if textBlock, ok := block.(*bedrocktypes.ContentBlockMemberText); ok {
			sb.WriteString(textBlock.Value)
		}
	}
	result := strings.TrimSpace(sb.String())
	if result == "" {
		return "", fmt.Errorf("bedrock returned empty text content")
	}
	return result, nil
}

func extractJSONObject(s string) string {
	start := strings.Index(s, "{")
	end := strings.LastIndex(s, "}")
	if start < 0 || end < 0 || end <= start {
		return ""
	}
	return strings.TrimSpace(s[start : end+1])
}

func (h *Handler) logAIDebug(label, content string) {
	if !h.cfg.EnableAIDebugLogs {
		return
	}
	maxChars := h.cfg.AIDebugLogMaxChars
	if maxChars <= 0 {
		maxChars = 4000
	}
	trimmed := strings.TrimSpace(content)
	if len(trimmed) > maxChars {
		log.Printf("ai_debug_%s=%s...<truncated %d chars>", label, trimmed[:maxChars], len(trimmed)-maxChars)
		return
	}
	log.Printf("ai_debug_%s=%s", label, trimmed)
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
			Items []struct {
				Type         string `json:"type"`
				Alternatives []struct {
					Content string `json:"content"`
				} `json:"alternatives"`
			} `json:"items"`
		} `json:"results"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return "", err
	}
	itemsTranscript := rebuildTranscriptFromItems(parsed.Results.Items)

	// Priority:
	// 1) token-level rebuild from items
	// 2) fallback to longest transcripts[] string
	if itemsTranscript != "" {
		return itemsTranscript, nil
	}
	return longestTranscript(parsed.Results.Transcripts), nil
}

func longestTranscript(transcripts []struct {
	Transcript string `json:"transcript"`
}) string {
	if len(transcripts) == 0 {
		return ""
	}
	best := ""
	for _, t := range transcripts {
		current := strings.TrimSpace(t.Transcript)
		if len(current) > len(best) {
			best = current
		}
	}
	return best
}

func rebuildTranscriptFromItems(items []struct {
	Type         string `json:"type"`
	Alternatives []struct {
		Content string `json:"content"`
	} `json:"alternatives"`
}) string {
	if len(items) == 0 {
		return ""
	}
	var b strings.Builder
	for _, item := range items {
		if len(item.Alternatives) == 0 {
			continue
		}
		token := strings.TrimSpace(item.Alternatives[0].Content)
		if token == "" {
			continue
		}
		if item.Type == "punctuation" {
			// Punctuation attaches to previous token without a leading space.
			b.WriteString(token)
			continue
		}
		if item.Type != "pronunciation" {
			continue
		}
		if b.Len() > 0 {
			b.WriteString(" ")
		}
		b.WriteString(token)
	}
	return strings.TrimSpace(b.String())
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

func enrichExtractedEntities(transcription, translation string, extracted map[string]any, alerts []map[string]any) map[string]any {
	if extracted == nil {
		extracted = map[string]any{}
	}
	if _, ok := extracted["symptoms"]; !ok {
		extracted["symptoms"] = []string{}
	}
	if _, ok := extracted["vitals"]; !ok {
		extracted["vitals"] = map[string]any{}
	}
	if _, ok := extracted["symptom_details"]; !ok {
		extracted["symptom_details"] = []map[string]any{}
	}
	if _, ok := extracted["medications_mentioned"]; !ok {
		extracted["medications_mentioned"] = []string{}
	}
	if _, ok := extracted["red_flags"]; !ok {
		extracted["red_flags"] = []string{}
	}
	if _, ok := extracted["asha_next_steps"]; !ok {
		extracted["asha_next_steps"] = []string{}
	}
	if _, ok := extracted["pregnancy_context"]; !ok {
		extracted["pregnancy_context"] = map[string]any{}
	}
	if _, ok := extracted["immunization_context"]; !ok {
		extracted["immunization_context"] = map[string]any{}
	}
	if _, ok := extracted["clinical_summary"]; !ok {
		extracted["clinical_summary"] = ""
	}
	if _, ok := extracted["referral_urgency"]; !ok {
		extracted["referral_urgency"] = "routine"
	}

	source := strings.TrimSpace(translation)
	if source == "" {
		source = strings.TrimSpace(transcription)
	}
	lower := strings.ToLower(source)

	if strings.TrimSpace(fmt.Sprintf("%v", extracted["visit_type"])) == "" {
		extracted["visit_type"] = "home visit"
	}
	if strings.TrimSpace(fmt.Sprintf("%v", extracted["chief_complaint"])) == "" {
		symptoms := normalizeStringSlice(extracted["symptoms"])
		if len(symptoms) > 0 {
			extracted["chief_complaint"] = symptoms[0]
		}
	}
	if age := extractAgeYears(source); age > 0 {
		if _, exists := extracted["age_years"]; !exists {
			extracted["age_years"] = age
		}
	}
	if duration := extractDurationDays(source); duration > 0 {
		if _, exists := extracted["duration_days"]; !exists {
			extracted["duration_days"] = duration
		}
	}
	if _, exists := extracted["symptom_duration_text"]; !exists {
		if durationText := extractDurationText(source); durationText != "" {
			extracted["symptom_duration_text"] = durationText
		}
	}
	if _, exists := extracted["body_site"]; !exists {
		if site := detectBodySite(lower); site != "" {
			extracted["body_site"] = site
		}
	}
	if _, exists := extracted["suspected_conditions"]; !exists {
		conditions := make([]string, 0, 3)
		for _, s := range normalizeStringSlice(extracted["symptoms"]) {
			switch strings.ToLower(s) {
			case "fever":
				conditions = append(conditions, "acute febrile illness")
			case "right knee pain", "knee pain":
				conditions = append(conditions, "chronic joint pain")
			}
		}
		if len(conditions) > 0 {
			extracted["suspected_conditions"] = uniqueStrings(conditions)
		}
	}
	if _, exists := extracted["risk_factors"]; !exists {
		riskFactors := make([]string, 0, 2)
		if age, _ := toInt(extracted["age_years"]); age >= 60 {
			riskFactors = append(riskFactors, "older_age")
		}
		if duration, _ := toInt(extracted["duration_days"]); duration >= 14 {
			riskFactors = append(riskFactors, "prolonged_symptoms")
		}
		if len(riskFactors) > 0 {
			extracted["risk_factors"] = uniqueStrings(riskFactors)
		}
	}
	if _, exists := extracted["follow_up_recommendations"]; !exists {
		reco := make([]string, 0, 3)
		if duration, _ := toInt(extracted["duration_days"]); duration >= 5 {
			reco = append(reco, "clinician_review")
		}
		if len(alerts) > 0 {
			reco = append(reco, "urgent_follow_up")
		}
		if len(reco) > 0 {
			extracted["follow_up_recommendations"] = uniqueStrings(reco)
		}
	}

	insights := map[string]any{
		"symptom_count": len(normalizeStringSlice(extracted["symptoms"])),
		"alert_count":   len(alerts),
	}
	if age, ok := toInt(extracted["age_years"]); ok {
		insights["age_years"] = age
	}
	if duration, ok := toInt(extracted["duration_days"]); ok {
		insights["duration_days"] = duration
	}
	extracted["insights"] = insights

	return extracted
}

func enrichClinicalAlerts(extracted map[string]any, alerts []map[string]any) []map[string]any {
	out := make([]map[string]any, 0, len(alerts)+2)
	out = append(out, alerts...)

	duration, hasDuration := toInt(extracted["duration_days"])
	if hasDuration && duration >= 5 && !alertExists(out, "FEVER_DURATION") {
		out = append(out, map[string]any{
			"severity": "moderate",
			"code":     "FEVER_DURATION",
			"message":  "Symptoms persisting for multiple days require clinician review",
		})
	}

	age, hasAge := toInt(extracted["age_years"])
	if hasAge && age >= 60 && !alertExists(out, "ELDERLY_PATIENT") {
		out = append(out, map[string]any{
			"severity": "low",
			"code":     "ELDERLY_PATIENT",
			"message":  "Older patient; monitor closely for worsening symptoms",
		})
	}

	return out
}

func alertExists(alerts []map[string]any, code string) bool {
	for _, a := range alerts {
		if strings.EqualFold(strings.TrimSpace(fmt.Sprintf("%v", a["code"])), code) {
			return true
		}
	}
	return false
}

func normalizeStringSlice(v any) []string {
	switch t := v.(type) {
	case []string:
		return t
	case []any:
		out := make([]string, 0, len(t))
		for _, item := range t {
			s := strings.TrimSpace(fmt.Sprintf("%v", item))
			if s != "" {
				out = append(out, s)
			}
		}
		return uniqueStrings(out)
	default:
		return nil
	}
}

func uniqueStrings(in []string) []string {
	seen := make(map[string]struct{}, len(in))
	out := make([]string, 0, len(in))
	for _, s := range in {
		key := strings.ToLower(strings.TrimSpace(s))
		if key == "" {
			continue
		}
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, s)
	}
	return out
}

func toInt(v any) (int, bool) {
	switch n := v.(type) {
	case int:
		return n, true
	case int32:
		return int(n), true
	case int64:
		return int(n), true
	case float64:
		return int(n), true
	case string:
		i, err := strconv.Atoi(strings.TrimSpace(n))
		if err != nil {
			return 0, false
		}
		return i, true
	default:
		return 0, false
	}
}

func extractAgeYears(text string) int {
	re := regexp.MustCompile(`(?i)\b(\d{1,3})\s*(years?|yrs?)\s*old\b`)
	m := re.FindStringSubmatch(text)
	if len(m) < 2 {
		return 0
	}
	age, err := strconv.Atoi(m[1])
	if err != nil || age <= 0 || age > 120 {
		return 0
	}
	return age
}

func extractDurationDays(text string) int {
	lower := strings.ToLower(text)
	if m := regexp.MustCompile(`(?i)\b(\d{1,3})\s*(day|days)\b`).FindStringSubmatch(lower); len(m) >= 2 {
		if v, err := strconv.Atoi(m[1]); err == nil {
			return v
		}
	}
	if m := regexp.MustCompile(`(?i)\b(\d{1,2})\s*(week|weeks)\b`).FindStringSubmatch(lower); len(m) >= 2 {
		if v, err := strconv.Atoi(m[1]); err == nil {
			return v * 7
		}
	}
	if m := regexp.MustCompile(`(?i)\b(\d{1,2})\s*(month|months)\b`).FindStringSubmatch(lower); len(m) >= 2 {
		if v, err := strconv.Atoi(m[1]); err == nil {
			return v * 30
		}
	}
	return 0
}

func extractDurationText(text string) string {
	re := regexp.MustCompile(`(?i)\bfor\s+the\s+past\s+([a-z0-9\s-]{1,30}(days?|weeks?|months?))`)
	m := re.FindStringSubmatch(text)
	if len(m) >= 2 {
		return strings.TrimSpace(m[1])
	}
	return ""
}

func detectBodySite(lowerText string) string {
	candidates := []string{"right knee", "left knee", "knee", "throat", "chest", "abdomen", "back", "head"}
	for _, c := range candidates {
		if strings.Contains(lowerText, c) {
			return c
		}
	}
	return ""
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

func looksLikeUUID(v string) bool {
	s := strings.TrimSpace(v)
	if len(s) != 36 {
		return false
	}
	for i, c := range s {
		switch i {
		case 8, 13, 18, 23:
			if c != '-' {
				return false
			}
		default:
			if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')) {
				return false
			}
		}
	}
	return true
}
