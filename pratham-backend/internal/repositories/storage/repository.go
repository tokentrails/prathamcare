package storage

import (
	"context"
	"time"

	"github.com/prathamcare/backend/internal/models"
)

type Repository interface {
	GenerateDocumentUploadURL(ctx context.Context, doc models.StoredDocument, expiresIn time.Duration) (string, error)
	GenerateVoiceUploadURL(ctx context.Context, voice models.VoiceRecording, expiresIn time.Duration) (string, error)
	GenerateDownloadURL(ctx context.Context, bucket, key string, expiresIn time.Duration) (string, error)
}
