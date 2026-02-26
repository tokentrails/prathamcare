package models

import "time"

type VectorDocument struct {
	DocumentID       string    `json:"document_id"`
	SourceType       string    `json:"source_type"` // guideline, patient_summary, note
	SourceID         string    `json:"source_id"`
	PatientID        string    `json:"patient_id,omitempty"`
	ChunkText        string    `json:"chunk_text"`
	EmbeddingModel   string    `json:"embedding_model"`
	EmbeddingVersion string    `json:"embedding_version"`
	CreatedAt        time.Time `json:"created_at"`
}

type SearchHit struct {
	DocumentID string  `json:"document_id"`
	Score      float64 `json:"score"`
	ChunkText  string  `json:"chunk_text"`
	SourceID   string  `json:"source_id"`
	SourceType string  `json:"source_type"`
}
