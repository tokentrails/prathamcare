package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/prathamcare/backend/internal/config"
	"github.com/prathamcare/backend/internal/middleware"
)

type Handler struct {
	cfg  config.Config
	auth *middleware.Authenticator
}

type healthResponse struct {
	Status    string `json:"status"`
	Env       string `json:"env"`
	Timestamp string `json:"timestamp"`
}

func NewHandler(cfg config.Config) *Handler {
	h := &Handler{cfg: cfg}
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
				"sub":   authClaims.Subject,
				"role":  authClaims.Role,
				"groups": authClaims.CognitoGroups,
			},
		})
	default:
		return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "route not found")
	}
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
