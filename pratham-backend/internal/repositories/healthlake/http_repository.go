package healthlake

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/prathamcare/backend/internal/awshttp"
	"github.com/prathamcare/backend/internal/models"
)

type HTTPRepository struct {
	client   *awshttp.SignedClient
	baseURL  string
	service  string
}

func NewHTTPRepository(ctx context.Context, region, baseURL string) (*HTTPRepository, error) {
	client, err := awshttp.NewSignedClient(ctx, region)
	if err != nil {
		return nil, err
	}
	return &HTTPRepository{client: client, baseURL: strings.TrimSuffix(baseURL, "/"), service: "healthlake"}, nil
}

func (r *HTTPRepository) CreatePatient(ctx context.Context, resource models.FHIRPatientResource) (string, error) {
	return r.createResource(ctx, "Patient", resource)
}

func (r *HTTPRepository) GetPatient(ctx context.Context, fhirPatientID string) (models.FHIRPatientResource, error) {
	var out models.FHIRPatientResource
	err := r.getResource(ctx, "Patient", fhirPatientID, &out)
	return out, err
}

func (r *HTTPRepository) CreateEncounter(ctx context.Context, resource models.FHIREncounterResource) (string, error) {
	return r.createResource(ctx, "Encounter", resource)
}

func (r *HTTPRepository) GetEncounter(ctx context.Context, fhirEncounterID string) (models.FHIREncounterResource, error) {
	var out models.FHIREncounterResource
	err := r.getResource(ctx, "Encounter", fhirEncounterID, &out)
	return out, err
}

func (r *HTTPRepository) CreateObservation(ctx context.Context, resource models.FHIRObservationResource) (string, error) {
	return r.createResource(ctx, "Observation", resource)
}

func (r *HTTPRepository) SearchPatientObservations(ctx context.Context, fhirPatientID string, code string, limit int) ([]models.FHIRObservationResource, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	params := url.Values{}
	params.Set("subject", "Patient/"+fhirPatientID)
	if code != "" {
		params.Set("code", code)
	}
	params.Set("_count", fmt.Sprintf("%d", limit))

	resp, err := r.client.Do(ctx, r.service, http.MethodGet, r.baseURL+"/Observation?"+params.Encode(), nil, "")
	if err != nil {
		return nil, err
	}
	body, err := awshttp.ReadJSONBody(resp)
	if err != nil {
		return nil, err
	}
	var bundle struct {
		Entry []struct {
			Resource models.FHIRObservationResource `json:"resource"`
		} `json:"entry"`
	}
	if err := json.Unmarshal(body, &bundle); err != nil {
		return nil, err
	}
	out := make([]models.FHIRObservationResource, 0, len(bundle.Entry))
	for _, e := range bundle.Entry {
		out = append(out, e.Resource)
	}
	return out, nil
}

func (r *HTTPRepository) createResource(ctx context.Context, resourceType string, payload any) (string, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	resp, err := r.client.Do(ctx, r.service, http.MethodPost, r.baseURL+"/"+resourceType, body, "application/fhir+json")
	if err != nil {
		return "", err
	}
	resBody, err := awshttp.ReadJSONBody(resp)
	if err != nil {
		return "", err
	}
	var parsed struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(resBody, &parsed); err != nil {
		return "", err
	}
	if parsed.ID == "" {
		return "", fmt.Errorf("healthlake response missing id")
	}
	return parsed.ID, nil
}

func (r *HTTPRepository) getResource(ctx context.Context, resourceType, id string, out any) error {
	resp, err := r.client.Do(ctx, r.service, http.MethodGet, r.baseURL+"/"+resourceType+"/"+id, nil, "")
	if err != nil {
		return err
	}
	body, err := awshttp.ReadJSONBody(resp)
	if err != nil {
		return err
	}
	return json.Unmarshal(body, out)
}

var _ Repository = (*HTTPRepository)(nil)
