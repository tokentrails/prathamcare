package aurora

import (
	"context"
	"time"

	"github.com/prathamcare/backend/internal/models"
)

type Repository interface {
	CreateUser(ctx context.Context, user models.User) (models.User, error)
	GetUserByCognitoSub(ctx context.Context, cognitoSub string) (models.User, error)
	CreateClinic(ctx context.Context, clinic models.Clinic) (models.Clinic, error)
	AssignUserToClinic(ctx context.Context, clinicID, userID string) error

	UpsertPatientIndex(ctx context.Context, patient models.Patient) (models.Patient, error)
	GetPatientByFHIRID(ctx context.Context, fhirPatientID string) (models.Patient, error)
	ListPatientsByClinic(ctx context.Context, clinicID string, limit int) ([]models.Patient, error)

	CreateAppointment(ctx context.Context, a models.Appointment) (models.Appointment, error)
	UpdateAppointmentStatus(ctx context.Context, appointmentID, status string) error
	ListAppointmentsByPhysician(ctx context.Context, physicianID string, start, end time.Time) ([]models.Appointment, error)

	CreatePatientRemark(ctx context.Context, remark models.PatientRemark) (models.PatientRemark, error)
	ListPatientRemarks(ctx context.Context, patientID string, limit int) ([]models.PatientRemark, error)
}
