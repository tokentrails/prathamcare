package search

import (
	"context"

	"github.com/prathamcare/backend/internal/models"
)

type Repository interface {
	IndexVectorDocument(ctx context.Context, doc models.VectorDocument, embedding []float32) error
	SemanticSearch(ctx context.Context, queryEmbedding []float32, topK int, patientID string) ([]models.SearchHit, error)
}
