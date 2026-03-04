package api

import (
	"testing"

	transcribetypes "github.com/aws/aws-sdk-go-v2/service/transcribe/types"
)

func TestBuildTranscribeStartInput_ExplicitLanguage(t *testing.T) {
	input, cfg := buildTranscribeStartInput(
		"bucket-a",
		"voice-visits/test.wav",
		"job-1",
		"kn-IN",
		[]string{"en-IN", "kn-IN"},
	)

	if cfg.Mode != "explicit" {
		t.Fatalf("expected explicit mode, got %q", cfg.Mode)
	}
	if input.LanguageCode != transcribetypes.LanguageCode("kn-IN") {
		t.Fatalf("expected LanguageCode kn-IN, got %q", input.LanguageCode)
	}
	if input.IdentifyLanguage != nil && *input.IdentifyLanguage {
		t.Fatalf("expected IdentifyLanguage false/nil for explicit mode")
	}
	if len(input.LanguageOptions) != 0 {
		t.Fatalf("expected no LanguageOptions for explicit mode, got %v", input.LanguageOptions)
	}
	if input.MediaFormat != transcribetypes.MediaFormat("wav") {
		t.Fatalf("expected wav media format, got %q", input.MediaFormat)
	}
}

func TestBuildTranscribeStartInput_AutoIdentifyAndOptions(t *testing.T) {
	input, cfg := buildTranscribeStartInput(
		"bucket-a",
		"voice-visits/test.m4a",
		"job-1",
		"",
		[]string{"en-IN", "kn-IN", "hi-IN"},
	)

	if cfg.Mode != "identify" {
		t.Fatalf("expected identify mode, got %q", cfg.Mode)
	}
	if input.LanguageCode != "" {
		t.Fatalf("expected empty LanguageCode for identify mode, got %q", input.LanguageCode)
	}
	if input.IdentifyLanguage == nil || !*input.IdentifyLanguage {
		t.Fatalf("expected IdentifyLanguage true for identify mode")
	}
	if len(input.LanguageOptions) != 2 {
		t.Fatalf("expected 2 LanguageOptions, got %d (%v)", len(input.LanguageOptions), input.LanguageOptions)
	}
	if input.LanguageOptions[0] != transcribetypes.LanguageCode("en-IN") || input.LanguageOptions[1] != transcribetypes.LanguageCode("kn-IN") {
		t.Fatalf("expected LanguageOptions [en-IN kn-IN], got %v", input.LanguageOptions)
	}
	if input.MediaFormat != transcribetypes.MediaFormat("mp4") {
		t.Fatalf("expected mp4 media format for .m4a, got %q", input.MediaFormat)
	}
}

func TestBuildTranscribeStartInput_UnsupportedLanguageFallsBackToAuto(t *testing.T) {
	input, cfg := buildTranscribeStartInput(
		"bucket-a",
		"voice-visits/test.mp3",
		"job-1",
		"hi-IN",
		[]string{"en-IN", "kn-IN"},
	)

	if cfg.Mode != "identify" {
		t.Fatalf("expected identify mode fallback, got %q", cfg.Mode)
	}
	if input.LanguageCode != "" {
		t.Fatalf("expected LanguageCode unset when falling back to identify mode, got %q", input.LanguageCode)
	}
	if len(input.LanguageOptions) != 2 {
		t.Fatalf("expected LanguageOptions [en-IN kn-IN], got %v", input.LanguageOptions)
	}
	for _, opt := range input.LanguageOptions {
		if opt == transcribetypes.LanguageCode("hi-IN") {
			t.Fatalf("did not expect hi-IN in LanguageOptions: %v", input.LanguageOptions)
		}
	}
	if input.MediaFormat != transcribetypes.MediaFormat("mp3") {
		t.Fatalf("expected mp3 media format, got %q", input.MediaFormat)
	}
}

func TestEnsureEnglishTranslation(t *testing.T) {
	got := ensureEnglishTranslation("ರೋಗಿಗೆ ಜ್ವರ ಇದೆ", "ರೋಗಿಗೆ ಜ್ವರ ಇದೆ", "kn-IN")
	if got == "ರೋಗಿಗೆ ಜ್ವರ ಇದೆ" {
		t.Fatalf("expected non-English translation fallback message, got source transcript")
	}
	if got == "" {
		t.Fatalf("expected non-empty fallback message")
	}

	english := ensureEnglishTranslation("Patient has fever", "Patient has fever", "en-IN")
	if english != "Patient has fever" {
		t.Fatalf("expected English transcription passthrough, got %q", english)
	}
}
