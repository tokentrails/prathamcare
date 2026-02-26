package middleware

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v2"
	"github.com/aws/aws-lambda-go/events"
	"github.com/golang-jwt/jwt/v5"
)

type AuthConfig struct {
	Issuer   string
	JWKSURL  string
	ClientID string
}

type Claims struct {
	Role         string
	Subject      string
	CognitoGroups []string
}

type Authenticator struct {
	cfg  AuthConfig
	jwks *keyfunc.JWKS
}

func NewAuthenticator(cfg AuthConfig) (*Authenticator, error) {
	if cfg.Issuer == "" || cfg.JWKSURL == "" {
		return nil, errors.New("missing Cognito issuer/JWKS config")
	}

	jwks, err := keyfunc.Get(cfg.JWKSURL, keyfunc.Options{
		RefreshInterval: time.Hour,
	})
	if err != nil {
		return nil, fmt.Errorf("load jwks: %w", err)
	}

	return &Authenticator{cfg: cfg, jwks: jwks}, nil
}

func (a *Authenticator) Close() {
	if a.jwks != nil {
		a.jwks.EndBackground()
	}
}

func (a *Authenticator) Authorize(req events.APIGatewayProxyRequest, allowedRoles ...string) (Claims, error) {
	tok := strings.TrimSpace(req.Headers["Authorization"])
	if tok == "" {
		tok = strings.TrimSpace(req.Headers["authorization"])
	}
	if tok == "" {
		return Claims{}, errors.New("missing authorization header")
	}
	parts := strings.SplitN(tok, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return Claims{}, errors.New("invalid authorization header format")
	}

	claims := jwt.MapClaims{}
	parsed, err := jwt.ParseWithClaims(parts[1], claims, a.jwks.Keyfunc, jwt.WithValidMethods([]string{"RS256"}))
	if err != nil || !parsed.Valid {
		return Claims{}, errors.New("invalid token")
	}

	if !verifyIssuer(claims, a.cfg.Issuer) {
		return Claims{}, errors.New("invalid issuer")
	}
	if a.cfg.ClientID != "" {
		if !verifyAudience(claims, a.cfg.ClientID) {
			return Claims{}, errors.New("invalid audience")
		}
	}

	role := extractRole(claims)
	if role == "" {
		return Claims{}, errors.New("role claim not found")
	}
	if len(allowedRoles) > 0 && !contains(allowedRoles, role) {
		return Claims{}, errors.New("authorization denied for role")
	}

	sub, _ := claims["sub"].(string)
	return Claims{
		Role:         role,
		Subject:      sub,
		CognitoGroups: extractGroups(claims),
	}, nil
}

func WithClaims(ctx context.Context, c Claims) context.Context {
	return context.WithValue(ctx, claimsKey{}, c)
}

func ClaimsFromContext(ctx context.Context) (Claims, bool) {
	c, ok := ctx.Value(claimsKey{}).(Claims)
	return c, ok
}

type claimsKey struct{}

func extractRole(claims jwt.MapClaims) string {
	if v, ok := claims["custom:role"].(string); ok && v != "" {
		return v
	}
	if v, ok := claims["role"].(string); ok && v != "" {
		return v
	}
	if groups := extractGroups(claims); len(groups) > 0 {
		// Use first group as role for Cognito group-based RBAC.
		return groups[0]
	}
	return ""
}

func extractGroups(claims jwt.MapClaims) []string {
	raw, ok := claims["cognito:groups"]
	if !ok {
		return nil
	}
	if direct, ok := raw.([]string); ok {
		return direct
	}

	arr, ok := raw.([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(arr))
	for _, item := range arr {
		if s, ok := item.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func verifyAudience(claims jwt.MapClaims, expected string) bool {
	if aud, ok := claims["aud"].(string); ok {
		return aud == expected
	}
	if clientID, ok := claims["client_id"].(string); ok {
		return clientID == expected
	}
	return false
}

func verifyIssuer(claims jwt.MapClaims, expected string) bool {
	if iss, ok := claims["iss"].(string); ok {
		return iss == expected
	}
	return false
}

func contains(values []string, target string) bool {
	for _, v := range values {
		if v == target {
			return true
		}
	}
	return false
}
