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
	CreateDoctor(ctx context.Context, doctor models.Doctor) (models.Doctor, error)
	ListDoctors(ctx context.Context, filter models.DoctorListFilter) ([]models.Doctor, error)
	GetDoctorByID(ctx context.Context, doctorID string) (models.Doctor, error)
	UpdateDoctor(ctx context.Context, doctor models.Doctor) (models.Doctor, error)
	UpdateDoctorStatus(ctx context.Context, doctorID string, isActive bool, updatedBy string) (models.Doctor, error)

	EnsurePatientByExternalID(ctx context.Context, externalID string) (models.Patient, error)
	CreatePatient(ctx context.Context, patient models.Patient) (models.Patient, error)
	SearchPatients(ctx context.Context, viewerUserRef string, viewerUserUUID *string, filter models.PatientSearchFilter) ([]models.Patient, error)
	GetPatientByIDForUser(ctx context.Context, viewerUserRef string, viewerUserUUID *string, patientID string) (models.Patient, error)
	UpdatePatient(ctx context.Context, viewerUserRef string, viewerUserUUID *string, patient models.Patient) (models.Patient, error)
	ListRecentPatientsByUser(ctx context.Context, viewerUserRef string, viewerUserUUID *string, limit int) ([]models.Patient, error)
	CreateEncounter(ctx context.Context, encounter models.EncounterRecord) (models.EncounterRecord, error)
	GetEncounterByID(ctx context.Context, encounterID string) (models.EncounterRecord, error)
	ListEncountersByASHA(ctx context.Context, ashaUserID string, limit int) ([]models.EncounterRecord, error)
	UpdateEncounterFHIRSync(ctx context.Context, encounterID, fhirEncounterID, syncStatus string) error
	CreateEncounterAlerts(ctx context.Context, encounterID string, alerts []models.EncounterAlert) error
	FindPatientForPublicRequest(ctx context.Context, phoneE164, fullName, pincode, abhaNumber string) (models.Patient, error)
	CountRecentPublicAppointmentRequests(ctx context.Context, phoneE164, requestIP string, within time.Duration) (int, error)
	HasRecentDuplicatePublicAppointment(ctx context.Context, phoneE164, reasonCode, pincode string, within time.Duration) (bool, error)
	MatchASHAByLocation(ctx context.Context, villageOrWard, blockOrTaluk, district, state, pincode string, latitude, longitude *float64) (models.ASHAMatchResult, error)
	CreateASHAAppointment(ctx context.Context, appt models.ASHAAppointment) (models.ASHAAppointment, error)
	ListASHAAppointments(ctx context.Context, filter models.ASHAAppointmentListFilter) ([]models.ASHAAppointment, error)
	ListASHADailyAppointmentSignals(ctx context.Context, ashaUserID, date, timezone string) ([]models.ASHADailyAppointmentSignal, error)
	GetASHAAppointmentByID(ctx context.Context, appointmentID string) (models.ASHAAppointment, error)
	GetASHAAppointmentByIDForASHA(ctx context.Context, appointmentID, ashaUserID string) (models.ASHAAppointment, error)
	UpdateASHAAppointmentStatus(ctx context.Context, appointmentID, status, updatedBy string) error
	CompleteASHAAppointment(ctx context.Context, appointmentID, encounterID, updatedBy string) error
	LogASHAAppointmentEvent(ctx context.Context, evt models.ASHAAppointmentEvent) error
}
