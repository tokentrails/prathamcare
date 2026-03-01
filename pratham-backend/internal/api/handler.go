package api

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
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
	if cfg.CognitoIssuer != "" && cfg.CognitoJWKSURL != "" {
		auth, err := middleware.NewAuthenticator(middleware.AuthConfig{
			Issuer:   cfg.CognitoIssuer,
			JWKSURL:  cfg.CognitoJWKSURL,
			ClientID: cfg.CognitoClientID,
		})
		if err == nil {
			h.auth = auth
		}
	}
	return h
}

func (h *Handler) Handle(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	path := strings.TrimSuffix(req.Path, "/")
	if path == "" {
		path = "/"
	}

	switch {
	case req.HTTPMethod == http.MethodGet && path == "/health":
		return h.json(http.StatusOK, healthResponse{
			Status:    "ok",
			Env:       h.cfg.AppEnv,
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		})
	case req.HTTPMethod == http.MethodGet && path == "/ready":
		if h.auth == nil {
			return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "auth middleware is not initialized")
		}
		return h.json(http.StatusOK, map[string]any{
			"status":    "ready",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		})
	case req.HTTPMethod == http.MethodGet && path == "/api/v1/me":
		if h.auth == nil {
			return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "auth middleware is not initialized")
		}
		claims, err := h.auth.Authorize(req, "doctor", "asha_worker", "clinic_admin", "ops_admin")
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
	case req.HTTPMethod == http.MethodPost && path == "/api/v1/voice/presign":
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
			LanguageCode:     defaultString(in.Language, "hi-IN"),
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
	case req.HTTPMethod == http.MethodPost && path == "/api/v1/voice/transcribe":
		return h.handleVoiceTranscribe(ctx, req)
	case req.HTTPMethod == http.MethodPost && path == "/api/v1/encounters":
		return h.handleEncounterCreate(ctx, req)
	case req.HTTPMethod == http.MethodGet && path == "/api/v1/sync/status":
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
	default:
		return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
	}
}

func (h *Handler) authorize(req events.APIGatewayProxyRequest, allowedRoles ...string) (middleware.Claims, error) {
	tok := strings.TrimSpace(req.Headers["Authorization"])
	if tok == "" {
		tok = strings.TrimSpace(req.Headers["authorization"])
	}
	if strings.EqualFold(tok, "Bearer demo-token") && strings.EqualFold(h.cfg.AppEnv, "dev") {
		return middleware.Claims{
			Role:    "asha_worker",
			Subject: "demo-asha-worker",
		}, nil
	}
	if h.auth == nil {
		return middleware.Claims{}, fmt.Errorf("auth middleware is not initialized")
	}
	return h.auth.Authorize(req, allowedRoles...)
}

func isSupportedAudioType(contentType string) bool {
	ct := strings.ToLower(strings.TrimSpace(contentType))
	return ct == "audio/mpeg" || ct == "audio/mp3" || ct == "audio/wav" || ct == "audio/x-wav"
}

func extFromContentType(contentType string) string {
	switch strings.ToLower(strings.TrimSpace(contentType)) {
	case "audio/mpeg", "audio/mp3":
		return ".mp3"
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

func (h *Handler) json(statusCode int, payload any) (events.APIGatewayProxyResponse, error) {
	b, err := json.Marshal(payload)
	if err != nil {
		return events.APIGatewayProxyResponse{StatusCode: http.StatusInternalServerError}, nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: statusCode,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(b),
	}, nil
}

func (h *Handler) error(statusCode int, code string, message string) (events.APIGatewayProxyResponse, error) {
	return h.json(statusCode, map[string]any{
		"error": map[string]any{
			"code":      code,
			"message":   message,
			"timestamp": time.Now().UTC().Format(time.RFC3339),
		},
	})
}
