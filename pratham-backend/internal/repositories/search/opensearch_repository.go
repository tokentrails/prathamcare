package search

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/prathamcare/backend/internal/awshttp"
	"github.com/prathamcare/backend/internal/models"
)

type OpenSearchRepository struct {
	client    *awshttp.SignedClient
	baseURL   string
	indexName string
	service   string
}

func NewOpenSearchRepository(ctx context.Context, region, baseURL, indexName string) (*OpenSearchRepository, error) {
	client, err := awshttp.NewSignedClient(ctx, region)
	if err != nil {
		return nil, err
	}
	if indexName == "" {
		indexName = "prathamcare-vectors"
	}
	return &OpenSearchRepository{
		client:    client,
		baseURL:   strings.TrimSuffix(baseURL, "/"),
		indexName: indexName,
		service:   "aoss",
	}, nil
}

func (r *OpenSearchRepository) IndexVectorDocument(ctx context.Context, doc models.VectorDocument, embedding []float32) error {
	payload := map[string]any{
		"document_id":       doc.DocumentID,
		"source_type":       doc.SourceType,
		"source_id":         doc.SourceID,
		"patient_id":        doc.PatientID,
		"chunk_text":        doc.ChunkText,
		"embedding_model":   doc.EmbeddingModel,
		"embedding_version": doc.EmbeddingVersion,
		"created_at":        doc.CreatedAt,
		"embedding":         embedding,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	url := fmt.Sprintf("%s/%s/_doc/%s", r.baseURL, r.indexName, doc.DocumentID)
	resp, err := r.client.Do(ctx, r.service, http.MethodPut, url, body, "application/json")
	if err != nil {
		return err
	}
	_, err = awshttp.ReadJSONBody(resp)
	return err
}

func (r *OpenSearchRepository) SemanticSearch(ctx context.Context, queryEmbedding []float32, topK int, patientID string) ([]models.SearchHit, error) {
	if topK <= 0 || topK > 50 {
		topK = 10
	}

	filters := make([]map[string]any, 0)
	if patientID != "" {
		filters = append(filters, map[string]any{
			"term": map[string]any{"patient_id.keyword": patientID},
		})
	}

	query := map[string]any{
		"size": topK,
		"query": map[string]any{
			"bool": map[string]any{
				"must": []any{
					map[string]any{
						"knn": map[string]any{
							"embedding": map[string]any{
								"vector": queryEmbedding,
								"k":      topK,
							},
						},
					},
				},
				"filter": filters,
			},
		},
	}
	body, err := json.Marshal(query)
	if err != nil {
		return nil, err
	}

	url := fmt.Sprintf("%s/%s/_search", r.baseURL, r.indexName)
	resp, err := r.client.Do(ctx, r.service, http.MethodPost, url, body, "application/json")
	if err != nil {
		return nil, err
	}
	resBody, err := awshttp.ReadJSONBody(resp)
	if err != nil {
		return nil, err
	}

	var parsed struct {
		Hits struct {
			Hits []struct {
				Score  float64 `json:"_score"`
				Source struct {
					DocumentID string `json:"document_id"`
					ChunkText  string `json:"chunk_text"`
					SourceID   string `json:"source_id"`
					SourceType string `json:"source_type"`
				} `json:"_source"`
			} `json:"hits"`
		} `json:"hits"`
	}
	if err := json.Unmarshal(resBody, &parsed); err != nil {
		return nil, err
	}

	out := make([]models.SearchHit, 0, len(parsed.Hits.Hits))
	for _, h := range parsed.Hits.Hits {
		out = append(out, models.SearchHit{
			DocumentID: h.Source.DocumentID,
			Score:      h.Score,
			ChunkText:  h.Source.ChunkText,
			SourceID:   h.Source.SourceID,
			SourceType: h.Source.SourceType,
		})
	}
	return out, nil
}

var _ Repository = (*OpenSearchRepository)(nil)
