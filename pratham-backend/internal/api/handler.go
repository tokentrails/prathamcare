package api

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/prathamcare/backend/internal/app"
	"github.com/prathamcare/backend/internal/config"
	"github.com/prathamcare/backend/internal/middleware"
	"github.com/prathamcare/backend/internal/models"
)

type Handler struct {
	cfg  config.Config
	deps *app.Dependencies
	auth *middleware.Authenticator
}

type healthResponse struct {
	Status    string `json:"status"`
	Env       string `json:"env"`
	Timestamp string `json:"timestamp"`
}

func NewHandler(cfg config.Config, deps *app.Dependencies) *Handler {
	h := &Handler{cfg: cfg, deps: deps}
	if strings.EqualFold(os.Getenv("DISABLE_AUTH_INIT"), "true") {
		log.Printf("auth init disabled via DISABLE_AUTH_INIT=true")
		return h
	}
	authInitTimeout := authInitTimeoutFromEnv()
	if cfg.CognitoIssuer != "" && cfg.CognitoJWKSURL != "" {
		authCh := make(chan *middleware.Authenticator, 1)
		errCh := make(chan error, 1)
		go func() {
			auth, err := middleware.NewAuthenticator(middleware.AuthConfig{
				Issuer:   cfg.CognitoIssuer,
				JWKSURL:  cfg.CognitoJWKSURL,
				ClientID: cfg.CognitoClientID,
			})
			if err != nil {
				errCh <- err
				return
			}
			authCh <- auth
		}()

		select {
		case auth := <-authCh:
			h.auth = auth
			log.Printf("auth init success")
		case err := <-errCh:
			log.Printf("warning: auth init failed, continuing without auth: %v", err)
		case <-time.After(authInitTimeout):
			log.Printf("warning: auth init timeout after %s, continuing without auth", authInitTimeout)
		}
	}
	return h
}

func authInitTimeoutFromEnv() time.Duration {
	const fallback = 5000
	raw := strings.TrimSpace(os.Getenv("AUTH_INIT_TIMEOUT_MS"))
	if raw == "" {
		return time.Duration(fallback) * time.Millisecond
	}
	ms, err := strconv.Atoi(raw)
	if err != nil || ms <= 0 {
		log.Printf("warning: invalid AUTH_INIT_TIMEOUT_MS=%q; using default %dms", raw, fallback)
		return time.Duration(fallback) * time.Millisecond
	}
	return time.Duration(ms) * time.Millisecond
}

func (h *Handler) Handle(ctx context.Context, req events.APIGatewayV2HTTPRequest) (resp events.APIGatewayV2HTTPResponse, err error) {
	defer func() {
		if rec := recover(); rec != nil {
			log.Printf("panic recovered in handler path=%s method=%s panic=%v stack=%s", req.RawPath, req.RequestContext.HTTP.Method, rec, string(debug.Stack()))
			body, _ := json.Marshal(map[string]any{
				"error": map[string]any{
					"code":      "INTERNAL_SERVER_ERROR",
					"message":   "unexpected server error",
					"timestamp": time.Now().UTC().Format(time.RFC3339),
				},
			})
			resp = events.APIGatewayV2HTTPResponse{
				StatusCode: http.StatusInternalServerError,
				Headers:    corsHeaders(map[string]string{"Content-Type": "application/json"}),
				Body: string(body),
			}
			err = nil
		}
	}()

	method := strings.ToUpper(strings.TrimSpace(req.RequestContext.HTTP.Method))
	path := strings.TrimSpace(req.RawPath)
	if path == "" {
		path = strings.TrimSpace(req.RequestContext.HTTP.Path)
	}
	path = strings.TrimSuffix(path, "/")
	// API Gateway stage paths can arrive as /{stage}/route (for example /dev/health).
	// Normalize to route-only path so handler routing remains stable across stage mappings.
	if stage := strings.TrimSpace(req.RequestContext.Stage); stage != "" {
		stagePrefix := "/" + stage
		switch {
		case path == stagePrefix:
			path = "/"
		case strings.HasPrefix(path, stagePrefix+"/"):
			path = strings.TrimPrefix(path, stagePrefix)
		}
	}
	if path == "" {
		path = "/"
	}
	if method == http.MethodOptions {
		return events.APIGatewayV2HTTPResponse{
			StatusCode: http.StatusNoContent,
			Headers:    corsHeaders(nil),
		}, nil
	}

	switch {
	case method == http.MethodGet && path == "/health":
		return h.json(http.StatusOK, healthResponse{
			Status:    "ok",
			Env:       h.cfg.AppEnv,
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		})
	case method == http.MethodGet && path == "/ready":
		if h.auth == nil {
			return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "auth middleware is not initialized")
		}
		return h.json(http.StatusOK, map[string]any{
			"status":    "ready",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		})
	case method == http.MethodGet && path == "/api/v1/me":
		if h.auth == nil {
			return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "auth middleware is not initialized")
		}
		claims, err := h.auth.Authorize(req.Headers, "doctor", "asha_worker", "clinic_admin", "ops_admin")
		if err != nil {
			return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
		}
		ctx = middleware.WithClaims(ctx, claims)
		authClaims, _ := middleware.ClaimsFromContext(ctx)
		return h.json(http.StatusOK, map[string]any{
			"user": map[string]any{
				"sub":    authClaims.Subject,
				"role":   authClaims.Role,
				"groups": authClaims.CognitoGroups,
			},
		})
	case method == http.MethodPost && path == "/api/v1/voice/presign":
		claims, err := h.authorize(req, "asha_worker")
		if err != nil {
			return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
		}
		var in struct {
			ContentType   string `json:"content_type"`
			FileSizeBytes int64  `json:"file_size_bytes"`
			Context       string `json:"context"`
			PatientID     string `json:"patient_id,omitempty"`
			Language      string `json:"language,omitempty"`
		}
		if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
			return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
		}
		if in.ContentType == "" {
			in.ContentType = "audio/wav"
		}
		if in.FileSizeBytes <= 0 || in.FileSizeBytes > 10*1024*1024 {
			return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "file_size_bytes must be between 1 and 10485760")
		}
		if !isSupportedAudioType(in.ContentType) {
			return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "unsupported content_type")
		}
		if h.deps == nil || h.deps.Storage == nil {
			return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "storage is not configured")
		}

		recordingID := "rec_" + newID()
		date := time.Now().UTC().Format("2006-01-02")
		ext := extFromContentType(in.ContentType)
		objectKey := fmt.Sprintf("voice-visits/%s/%s/%s%s", claims.Subject, date, recordingID, ext)

		url, err := h.deps.Storage.GenerateVoiceUploadURL(ctx, models.VoiceRecording{
			RecordingID:      recordingID,
			PatientID:        in.PatientID,
			RecordedByUserID: claims.Subject,
			LanguageCode:     normalizeVoiceJobLanguage(in.Language),
			S3Bucket:         h.cfg.S3VoiceBucket,
			S3Key:            objectKey,
			CreatedAt:        time.Now().UTC(),
		}, 15*time.Minute)
		if err != nil {
			return h.error(http.StatusInternalServerError, "INTERNAL_SERVER_ERROR", "failed to generate upload url")
		}
		return h.json(http.StatusOK, map[string]any{
			"upload_url":  url,
			"object_key":  objectKey,
			"expires_in":  900,
			"recording_id": recordingID,
		})
	case method == http.MethodPost && path == "/api/v1/voice/transcribe":
		return h.handleVoiceTranscribe(ctx, req)
	case method == http.MethodPost && path == "/api/v1/voice/translate-summary":
		return h.handleVoiceSummaryTranslate(ctx, req)
	case method == http.MethodGet && strings.HasPrefix(path, "/api/v1/voice/transcribe/"):
		jobPrefix := "/api/v1/voice/transcribe/job/"
		if strings.HasPrefix(path, jobPrefix) {
			transcriptionJobID := strings.TrimPrefix(path, jobPrefix)
			if strings.TrimSpace(transcriptionJobID) == "" {
				return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "transcription_job_id is required")
			}
			return h.handleVoiceTranscribeJobStatus(ctx, req, transcriptionJobID)
		}
		voiceJobID := strings.TrimPrefix(path, "/api/v1/voice/transcribe/")
		if strings.TrimSpace(voiceJobID) == "" {
			return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "voice_job_id is required")
		}
		return h.handleVoiceTranscribeStatus(ctx, req, voiceJobID)
	case method == http.MethodPost && path == "/api/v1/encounters":
		return h.handleEncounterCreate(ctx, req)
	case method == http.MethodPost && path == "/api/v1/public/appointments/request":
		return h.handlePublicASHAAppointmentRequest(ctx, req)
	case method == http.MethodGet && path == "/api/v1/appointments/asha":
		return h.handleASHAAppointmentsList(ctx, req)
	case method == http.MethodGet && path == "/api/v1/appointments/asha/day-summary":
		return h.handleASHADaySummary(ctx, req)
	case method == http.MethodPatch && strings.HasPrefix(path, "/api/v1/appointments/") && strings.HasSuffix(path, "/status"):
		appointmentID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/appointments/"), "/status")
		if strings.TrimSpace(appointmentID) == "" {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handleASHAAppointmentStatusPatch(ctx, req, appointmentID)
	case method == http.MethodPost && strings.HasPrefix(path, "/api/v1/appointments/") && strings.HasSuffix(path, "/start-encounter"):
		appointmentID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/appointments/"), "/start-encounter")
		if strings.TrimSpace(appointmentID) == "" {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handleASHAAppointmentStartEncounter(ctx, req, appointmentID)
	case method == http.MethodPost && strings.HasPrefix(path, "/api/v1/appointments/") && strings.HasSuffix(path, "/complete"):
		appointmentID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/appointments/"), "/complete")
		if strings.TrimSpace(appointmentID) == "" {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handleASHAAppointmentComplete(ctx, req, appointmentID)
	case method == http.MethodGet && strings.HasPrefix(path, "/api/v1/appointments/"):
		appointmentID := strings.TrimPrefix(path, "/api/v1/appointments/")
		if strings.TrimSpace(appointmentID) == "" || strings.EqualFold(appointmentID, "asha") {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handleASHAAppointmentGet(ctx, req, appointmentID)
	case method == http.MethodPost && path == "/api/v1/admin/doctors":
		return h.handleAdminDoctorCreate(ctx, req)
	case method == http.MethodGet && path == "/api/v1/admin/doctors":
		return h.handleAdminDoctorList(ctx, req)
	case method == http.MethodPatch && strings.HasPrefix(path, "/api/v1/admin/doctors/") && strings.HasSuffix(path, "/status"):
		doctorID := strings.TrimSuffix(strings.TrimPrefix(path, "/api/v1/admin/doctors/"), "/status")
		if strings.TrimSpace(doctorID) == "" {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handleAdminDoctorStatusUpdate(ctx, req, doctorID)
	case method == http.MethodGet && strings.HasPrefix(path, "/api/v1/admin/doctors/"):
		doctorID := strings.TrimPrefix(path, "/api/v1/admin/doctors/")
		if strings.TrimSpace(doctorID) == "" {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handleAdminDoctorGet(ctx, req, doctorID)
	case method == http.MethodPut && strings.HasPrefix(path, "/api/v1/admin/doctors/"):
		doctorID := strings.TrimPrefix(path, "/api/v1/admin/doctors/")
		if strings.TrimSpace(doctorID) == "" {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handleAdminDoctorUpdate(ctx, req, doctorID)
	case method == http.MethodPost && path == "/api/v1/patients":
		return h.handlePatientCreate(ctx, req)
	case method == http.MethodGet && path == "/api/v1/patients/search":
		return h.handlePatientSearch(ctx, req)
	case method == http.MethodGet && path == "/api/v1/patients/recent":
		return h.handlePatientRecent(ctx, req)
	case method == http.MethodGet && strings.HasPrefix(path, "/api/v1/patients/"):
		patientID := strings.TrimPrefix(path, "/api/v1/patients/")
		if strings.TrimSpace(patientID) == "" || strings.EqualFold(patientID, "search") || strings.EqualFold(patientID, "recent") {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handlePatientGet(ctx, req, patientID)
	case method == http.MethodPut && strings.HasPrefix(path, "/api/v1/patients/"):
		patientID := strings.TrimPrefix(path, "/api/v1/patients/")
		if strings.TrimSpace(patientID) == "" || strings.EqualFold(patientID, "search") || strings.EqualFold(patientID, "recent") {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handlePatientUpdate(ctx, req, patientID)
	case method == http.MethodGet && path == "/api/v1/voice/history":
		return h.handleVoiceHistory(ctx, req)
	case method == http.MethodGet && path == "/api/v1/encounters/history":
		return h.handleEncounterHistory(ctx, req)
	case method == http.MethodGet && strings.HasPrefix(path, "/api/v1/encounters/"):
		encounterID := strings.TrimPrefix(path, "/api/v1/encounters/")
		if strings.TrimSpace(encounterID) == "" || strings.EqualFold(encounterID, "history") {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
		}
		return h.handleEncounterDetail(ctx, req, encounterID)
	case method == http.MethodGet && path == "/api/v1/sync/status":
		claims, err := h.authorize(req, "asha_worker")
		if err != nil {
			return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
		}
		pending := 0
		if h.deps != nil && h.deps.Dynamo != nil {
			items, listErr := h.deps.Dynamo.ListOfflineQueueByUser(ctx, claims.Subject, 100)
			if listErr == nil {
				for _, it := range items {
					if strings.EqualFold(it.Status, "queued") || strings.EqualFold(it.Status, "pending") {
						pending++
					}
				}
			}
		}
		return h.json(http.StatusOK, map[string]any{
			"user_id":         claims.Subject,
			"pending_actions": pending,
			"last_checked_at": time.Now().UTC().Format(time.RFC3339),
		})
	case method == http.MethodPost && path == "/api/v1/sync/replay":
		return h.handleSyncReplay(ctx, req)
	default:
		return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
	}
}

func (h *Handler) authorize(req events.APIGatewayV2HTTPRequest, allowedRoles ...string) (middleware.Claims, error) {
	tok := strings.TrimSpace(headerValue(req.Headers, "Authorization"))
	if strings.EqualFold(tok, "Bearer demo-token") && strings.EqualFold(h.cfg.AppEnv, "dev") {
		return middleware.Claims{
			Role:    "asha_worker",
			Subject: "demo-asha-worker",
		}, nil
	}
	if h.auth == nil {
		return middleware.Claims{}, fmt.Errorf("auth middleware is not initialized")
	}
	return h.auth.Authorize(req.Headers, allowedRoles...)
}

func isSupportedAudioType(contentType string) bool {
	ct := strings.ToLower(strings.TrimSpace(contentType))
	return ct == "audio/mpeg" ||
		ct == "audio/mp3" ||
		ct == "audio/wav" ||
		ct == "audio/x-wav" ||
		ct == "audio/mp4" ||
		ct == "audio/m4a" ||
		ct == "audio/aac"
}

func extFromContentType(contentType string) string {
	switch strings.ToLower(strings.TrimSpace(contentType)) {
	case "audio/mpeg", "audio/mp3":
		return ".mp3"
	case "audio/mp4", "audio/m4a", "audio/aac":
		return ".m4a"
	default:
		return ".wav"
	}
}

func defaultString(v, fallback string) string {
	if strings.TrimSpace(v) == "" {
		return fallback
	}
	return v
}

func newID() string {
	buf := make([]byte, 8)
	if _, err := rand.Read(buf); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(buf)
}

func (h *Handler) json(statusCode int, payload any) (events.APIGatewayV2HTTPResponse, error) {
	b, err := json.Marshal(payload)
	if err != nil {
		return events.APIGatewayV2HTTPResponse{
			StatusCode: http.StatusInternalServerError,
			Headers:    corsHeaders(map[string]string{"Content-Type": "application/json"}),
		}, nil
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: statusCode,
		Headers:    corsHeaders(map[string]string{"Content-Type": "application/json"}),
		Body:       string(b),
	}, nil
}

func (h *Handler) error(statusCode int, code string, message string) (events.APIGatewayV2HTTPResponse, error) {
	return h.json(statusCode, map[string]any{
		"error": map[string]any{
			"code":      code,
			"message":   message,
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		},
	})
}

func headerValue(headers map[string]string, name string) string {
	if headers == nil {
		return ""
	}
	if v, ok := headers[name]; ok && strings.TrimSpace(v) != "" {
		return v
	}
	lower := strings.ToLower(name)
	for k, v := range headers {
		if strings.ToLower(k) == lower && strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func corsHeaders(base map[string]string) map[string]string {
	headers := map[string]string{
		"Access-Control-Allow-Origin":  "*",
		"Access-Control-Allow-Methods": "GET,POST,PUT,PATCH,DELETE,OPTIONS",
		"Access-Control-Allow-Headers": "Authorization,Content-Type,X-Requested-With",
	}
	for k, v := range base {
		headers[k] = v
	}
	return headers
}

