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

	CreateVoiceJob(ctx context.Context, job models.VoiceJob) (models.VoiceJob, error)
	GetVoiceJobByID(ctx context.Context, voiceJobID string) (models.VoiceJob, error)
	ListVoiceJobsByASHA(ctx context.Context, ashaUserID string, limit int) ([]models.VoiceJob, error)
	UpdateVoiceJobStatus(ctx context.Context, voiceJobID, status, transcriptionJobID, errorCode, errorMessage string, completedAt *time.Time) error

	EnsurePatientByExternalID(ctx context.Context, externalID string) (models.Patient, error)
	CreateEncounter(ctx context.Context, encounter models.EncounterRecord) (models.EncounterRecord, error)
	GetEncounterByID(ctx context.Context, encounterID string) (models.EncounterRecord, error)
	ListEncountersByASHA(ctx context.Context, ashaUserID string, limit int) ([]models.EncounterRecord, error)
	UpdateEncounterFHIRSync(ctx context.Context, encounterID, fhirEncounterID, syncStatus string) error
	CreateEncounterAlerts(ctx context.Context, encounterID string, alerts []models.EncounterAlert) error
}
