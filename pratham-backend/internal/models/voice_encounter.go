package models

import "time"

type VoiceJob struct {
	VoiceJobID           string
	PatientID            string
	ASHAUserID           string
	EncounterID          string
	S3Bucket             string
	S3Key                string
	LanguageCode         string
	Context              string
	TranscriptionJobID   string
	ProcessingStatus     string
	ErrorCode            string
	ErrorMessage         string
	ProcessingStartedAt  time.Time
	ProcessingCompletedAt time.Time
	CreatedAt            time.Time
	UpdatedAt            time.Time
}

type EncounterRecord struct {
	EncounterID       string
	PatientID         string
	ASHAUserID        string
	ClinicID          string
	VisitType         string
	Status            string
	OccurredAt        time.Time
	SourceAudioBucket string
	SourceAudioKey    string
	TranscriptionText string
	TranslationText   string
	ExtractedEntities string
	ClinicalAlerts    string
	FHIREncounterID   string
	SyncStatus        string
	IdempotencyKey    string
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

type EncounterAlert struct {
	EncounterAlertID string
	EncounterID      string
	Severity         string
	AlertCode        string
	Message          string
	Metadata         string
	CreatedAt        time.Time
}
