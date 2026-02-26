package healthlake

import (
	"context"

	"github.com/prathamcare/backend/internal/models"
)

type Repository interface {
	CreatePatient(ctx context.Context, resource models.FHIRPatientResource) (string, error)
	GetPatient(ctx context.Context, fhirPatientID string) (models.FHIRPatientResource, error)

	CreateEncounter(ctx context.Context, resource models.FHIREncounterResource) (string, error)
	GetEncounter(ctx context.Context, fhirEncounterID string) (models.FHIREncounterResource, error)

	CreateObservation(ctx context.Context, resource models.FHIRObservationResource) (string, error)
	SearchPatientObservations(ctx context.Context, fhirPatientID string, code string, limit int) ([]models.FHIRObservationResource, error)
}
