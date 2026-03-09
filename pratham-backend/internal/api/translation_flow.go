package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	awstranslate "github.com/aws/aws-sdk-go-v2/service/translate"
)

func (h *Handler) handleVoiceSummaryTranslate(
	ctx context.Context,
	req events.APIGatewayV2HTTPRequest,
) (events.APIGatewayV2HTTPResponse, error) {
	requestID := strings.TrimSpace(req.RequestContext.RequestID)
	log.Printf("voice_summary_translate_hit request_id=%s path=%s", requestID, strings.TrimSpace(req.RawPath))

	if _, err := h.authorize(req, "asha_worker"); err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}

	var in struct {
		Text           string `json:"text"`
		SourceLanguage string `json:"source_language"`
		TargetLanguage string `json:"target_language"`
	}
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}

	text := strings.TrimSpace(in.Text)
	if text == "" {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "text is required")
	}
	if len([]rune(text)) > 4500 {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "text exceeds max length")
	}

	target, ok := normalizeTranslationLanguage(in.TargetLanguage)
	if !ok {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "target_language must be one of: en, hi, kn, ta, te, ml, gu")
	}

	source, sourceProvided := normalizeTranslationLanguage(in.SourceLanguage)
	if !sourceProvided {
		source = "en"
	}

	if source == target {
		return h.json(http.StatusOK, map[string]any{
			"translated_text":  text,
			"source_language":  source,
			"target_language":  target,
			"translated_at":    time.Now().UTC().Format(time.RFC3339),
			"translation_mode": "identity",
		})
	}

	region := defaultString(h.cfg.AWSRegion, "ap-south-1")
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aws config unavailable")
	}
	client := awstranslate.NewFromConfig(awsCfg)

	callCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	out, err := client.TranslateText(callCtx, &awstranslate.TranslateTextInput{
		Text:               &text,
		SourceLanguageCode: &source,
		TargetLanguageCode: &target,
	})
	if err != nil {
		return h.error(http.StatusServiceUnavailable, "TRANSLATION_UNAVAILABLE", "translation failed")
	}

	translatedText := strings.TrimSpace(stringValue(out.TranslatedText))
	if translatedText == "" {
		return h.error(http.StatusServiceUnavailable, "TRANSLATION_UNAVAILABLE", "translation returned empty text")
	}

	return h.json(http.StatusOK, map[string]any{
		"translated_text": translatedText,
		"source_language": defaultString(stringValue(out.SourceLanguageCode), source),
		"target_language": target,
		"translated_at":   time.Now().UTC().Format(time.RFC3339),
	})
}

func normalizeTranslationLanguage(raw string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "en", "en-in":
		return "en", true
	case "hi", "hi-in":
		return "hi", true
	case "kn", "kn-in":
		return "kn", true
	case "ta", "ta-in":
		return "ta", true
	case "te", "te-in":
		return "te", true
	case "ml", "ml-in":
		return "ml", true
	case "gu", "gu-in":
		return "gu", true
	default:
		return "", false
	}
}
