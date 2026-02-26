package models

import "time"

type StoredDocument struct {
	DocumentID      string    `json:"document_id"`
	PatientID       string    `json:"patient_id"`
	EncounterID     string    `json:"encounter_id,omitempty"`
	DocumentType    string    `json:"document_type"`
	S3Bucket        string    `json:"s3_bucket"`
	S3Key           string    `json:"s3_key"`
	ContentType     string    `json:"content_type"`
	SizeBytes       int64     `json:"size_bytes"`
	UploadedByUserID string   `json:"uploaded_by_user_id"`
	CreatedAt       time.Time `json:"created_at"`
}

type VoiceRecording struct {
	RecordingID      string    `json:"recording_id"`
	PatientID        string    `json:"patient_id,omitempty"`
	EncounterID      string    `json:"encounter_id,omitempty"`
	RecordedByUserID string    `json:"recorded_by_user_id"`
	LanguageCode     string    `json:"language_code"`
	DurationSeconds  int       `json:"duration_seconds"`
	S3Bucket         string    `json:"s3_bucket"`
	S3Key            string    `json:"s3_key"`
	TranscriptionJob string    `json:"transcription_job,omitempty"`
	CreatedAt        time.Time `json:"created_at"`
}
