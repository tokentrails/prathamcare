package storage

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
	"github.com/prathamcare/backend/internal/models"
)

type S3Repository struct {
	presignClient *s3.PresignClient
}

func NewS3Repository(ctx context.Context, region string) (*S3Repository, error) {
	awsCfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}
	client := s3.NewFromConfig(awsCfg)
	return &S3Repository{presignClient: s3.NewPresignClient(client)}, nil
}

func (r *S3Repository) GenerateDocumentUploadURL(ctx context.Context, doc models.StoredDocument, expiresIn time.Duration) (string, error) {
	out, err := r.presignClient.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:      &doc.S3Bucket,
		Key:         &doc.S3Key,
		ContentType: &doc.ContentType,
		Metadata: map[string]string{
			"patient_id": doc.PatientID,
			"document_id": doc.DocumentID,
			"document_type": doc.DocumentType,
		},
		ServerSideEncryption: types.ServerSideEncryptionAwsKms,
	}, s3.WithPresignExpires(expiresIn))
	if err != nil {
		return "", err
	}
	return out.URL, nil
}

func (r *S3Repository) GenerateVoiceUploadURL(ctx context.Context, voice models.VoiceRecording, expiresIn time.Duration) (string, error) {
	contentType := "audio/mpeg"
	out, err := r.presignClient.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:      &voice.S3Bucket,
		Key:         &voice.S3Key,
		ContentType: &contentType,
		Metadata: map[string]string{
			"recording_id": voice.RecordingID,
			"recorded_by": voice.RecordedByUserID,
			"language": voice.LanguageCode,
		},
		ServerSideEncryption: types.ServerSideEncryptionAwsKms,
	}, s3.WithPresignExpires(expiresIn))
	if err != nil {
		return "", err
	}
	return out.URL, nil
}

func (r *S3Repository) GenerateDownloadURL(ctx context.Context, bucket, key string, expiresIn time.Duration) (string, error) {
	out, err := r.presignClient.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: &bucket,
		Key:    &key,
	}, s3.WithPresignExpires(expiresIn))
	if err != nil {
		return "", err
	}
	return out.URL, nil
}

var _ Repository = (*S3Repository)(nil)
