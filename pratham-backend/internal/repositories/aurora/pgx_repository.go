package aurora

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/prathamcare/backend/internal/models"
)

type PgxRepository struct {
	pool *pgxpool.Pool
}

func NewPgxRepository(ctx context.Context, dsn string) (*PgxRepository, error) {
	if dsn == "" {
		return nil, errors.New("aurora dsn is empty")
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("pgx pool init: %w", err)
	}
	return &PgxRepository{pool: pool}, nil
}

func (r *PgxRepository) Close() {
	if r.pool != nil {
		r.pool.Close()
	}
}

func (r *PgxRepository) CreateUser(ctx context.Context, user models.User) (models.User, error) {
	q := `
INSERT INTO users (cognito_sub, role, full_name, phone, email, preferred_language, is_active)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING user_id, cognito_sub, role, full_name, phone, COALESCE(email, ''), preferred_language, is_active,
	COALESCE(last_login_at, NOW()), created_at, updated_at`

	var out models.User
	err := r.pool.QueryRow(ctx, q,
		user.CognitoSub,
		user.Role,
		user.FullName,
		user.Phone,
		nullIfEmpty(user.Email),
		nullIfEmpty(user.PreferredLanguage),
		user.IsActive,
	).Scan(
		&out.UserID,
		&out.CognitoSub,
		&out.Role,
		&out.FullName,
		&out.Phone,
		&out.Email,
		&out.PreferredLanguage,
		&out.IsActive,
		&out.LastLoginAt,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) GetUserByCognitoSub(ctx context.Context, cognitoSub string) (models.User, error) {
	var out models.User
	err := r.pool.QueryRow(ctx, `
SELECT user_id, cognito_sub, role, full_name, phone, COALESCE(email, ''), preferred_language, is_active,
	COALESCE(last_login_at, NOW()), created_at, updated_at
FROM users
WHERE cognito_sub = $1`, cognitoSub).Scan(
		&out.UserID,
		&out.CognitoSub,
		&out.Role,
		&out.FullName,
		&out.Phone,
		&out.Email,
		&out.PreferredLanguage,
		&out.IsActive,
		&out.LastLoginAt,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) CreateClinic(ctx context.Context, clinic models.Clinic) (models.Clinic, error) {
	var out models.Clinic
	err := r.pool.QueryRow(ctx, `
INSERT INTO clinics (clinic_code, name, type, abdm_hfr_id, phone, email, city, state, pincode, country_code, is_active)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
RETURNING clinic_id, COALESCE(clinic_code, ''), name, type, COALESCE(abdm_hfr_id, ''), COALESCE(phone, ''), COALESCE(email, ''),
	COALESCE(city, ''), COALESCE(state, ''), COALESCE(pincode, ''), country_code, is_active, created_at, updated_at`,
		nullIfEmpty(clinic.ClinicCode),
		clinic.Name,
		nullIfEmpty(clinic.Type),
		nullIfEmpty(clinic.ABDMHFRID),
		nullIfEmpty(clinic.Phone),
		nullIfEmpty(clinic.Email),
		nullIfEmpty(clinic.City),
		nullIfEmpty(clinic.State),
		nullIfEmpty(clinic.Pincode),
		nullIfEmpty(clinic.CountryCode),
		clinic.IsActive,
	).Scan(
		&out.ClinicID,
		&out.ClinicCode,
		&out.Name,
		&out.Type,
		&out.ABDMHFRID,
		&out.Phone,
		&out.Email,
		&out.City,
		&out.State,
		&out.Pincode,
		&out.CountryCode,
		&out.IsActive,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) AssignUserToClinic(ctx context.Context, clinicID, userID string) error {
	_, err := r.pool.Exec(ctx, `
INSERT INTO clinic_memberships (clinic_id, user_id, status)
VALUES ($1, $2, 'active')
ON CONFLICT (clinic_id, user_id) DO UPDATE SET status = 'active', updated_at = NOW()`, clinicID, userID)
	return err
}

func (r *PgxRepository) UpsertPatientIndex(ctx context.Context, patient models.Patient) (models.Patient, error) {
	q := `
INSERT INTO patients (
	fhir_patient_id, abha_id, full_name, gender, date_of_birth, phone, preferred_language,
	primary_clinic_id, source_system, read_only, last_synced_at
) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
ON CONFLICT (fhir_patient_id) DO UPDATE SET
	abha_id = EXCLUDED.abha_id,
	full_name = EXCLUDED.full_name,
	gender = EXCLUDED.gender,
	date_of_birth = EXCLUDED.date_of_birth,
	phone = EXCLUDED.phone,
	preferred_language = EXCLUDED.preferred_language,
	primary_clinic_id = EXCLUDED.primary_clinic_id,
	source_system = EXCLUDED.source_system,
	read_only = EXCLUDED.read_only,
	last_synced_at = EXCLUDED.last_synced_at,
	updated_at = NOW()
RETURNING patient_id, fhir_patient_id, COALESCE(abha_id, ''), full_name, COALESCE(gender, ''), COALESCE(date_of_birth::text, ''),
	COALESCE(phone, ''), COALESCE(preferred_language, ''), COALESCE(primary_clinic_id::text, ''), source_system, read_only,
	COALESCE(last_synced_at, NOW()), created_at, updated_at`

	var out models.Patient
	err := r.pool.QueryRow(ctx, q,
		patient.FHIRPatientID,
		nullIfEmpty(patient.ABHAID),
		patient.FullName,
		nullIfEmpty(patient.Gender),
		nullIfEmpty(patient.DateOfBirth),
		nullIfEmpty(patient.Phone),
		nullIfEmpty(patient.PreferredLanguage),
		nullIfEmpty(patient.PrimaryClinicID),
		nullIfEmpty(patient.SourceSystem),
		patient.ReadOnly,
		nullIfZeroTime(patient.LastSyncedAt),
	).Scan(
		&out.PatientID,
		&out.FHIRPatientID,
		&out.ABHAID,
		&out.FullName,
		&out.Gender,
		&out.DateOfBirth,
		&out.Phone,
		&out.PreferredLanguage,
		&out.PrimaryClinicID,
		&out.SourceSystem,
		&out.ReadOnly,
		&out.LastSyncedAt,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) GetPatientByFHIRID(ctx context.Context, fhirPatientID string) (models.Patient, error) {
	var out models.Patient
	err := r.pool.QueryRow(ctx, `
SELECT patient_id, fhir_patient_id, COALESCE(abha_id, ''), full_name, COALESCE(gender, ''), COALESCE(date_of_birth::text, ''),
	COALESCE(phone, ''), COALESCE(preferred_language, ''), COALESCE(primary_clinic_id::text, ''), source_system, read_only,
	COALESCE(last_synced_at, NOW()), created_at, updated_at
FROM patients
WHERE fhir_patient_id = $1`, fhirPatientID).Scan(
		&out.PatientID,
		&out.FHIRPatientID,
		&out.ABHAID,
		&out.FullName,
		&out.Gender,
		&out.DateOfBirth,
		&out.Phone,
		&out.PreferredLanguage,
		&out.PrimaryClinicID,
		&out.SourceSystem,
		&out.ReadOnly,
		&out.LastSyncedAt,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) ListPatientsByClinic(ctx context.Context, clinicID string, limit int) ([]models.Patient, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := r.pool.Query(ctx, `
SELECT patient_id, fhir_patient_id, COALESCE(abha_id, ''), full_name, COALESCE(gender, ''), COALESCE(date_of_birth::text, ''),
	COALESCE(phone, ''), COALESCE(preferred_language, ''), COALESCE(primary_clinic_id::text, ''), source_system, read_only,
	COALESCE(last_synced_at, NOW()), created_at, updated_at
FROM patients
WHERE primary_clinic_id = $1
ORDER BY updated_at DESC
LIMIT $2`, clinicID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.Patient, 0, limit)
	for rows.Next() {
		var item models.Patient
		if err := rows.Scan(
			&item.PatientID,
			&item.FHIRPatientID,
			&item.ABHAID,
			&item.FullName,
			&item.Gender,
			&item.DateOfBirth,
			&item.Phone,
			&item.PreferredLanguage,
			&item.PrimaryClinicID,
			&item.SourceSystem,
			&item.ReadOnly,
			&item.LastSyncedAt,
			&item.CreatedAt,
			&item.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) CreateAppointment(ctx context.Context, a models.Appointment) (models.Appointment, error) {
	q := `
INSERT INTO appointments (
	patient_id, physician_id, clinic_id, appointment_type, booking_channel, status,
	scheduled_start_at, scheduled_end_at, preliminary_diagnosis, fhir_appointment_id,
	fhir_encounter_id, created_by
) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
RETURNING appointment_id, patient_id, physician_id, clinic_id, appointment_type, booking_channel,
	status, scheduled_start_at, scheduled_end_at, COALESCE(preliminary_diagnosis, ''), COALESCE(fhir_appointment_id, ''),
	COALESCE(fhir_encounter_id, ''), COALESCE(created_by::text, ''), created_at, updated_at`

	var out models.Appointment
	err := r.pool.QueryRow(ctx, q,
		a.PatientID,
		a.PhysicianID,
		a.ClinicID,
		nullIfEmpty(a.AppointmentType),
		nullIfEmpty(a.BookingChannel),
		nullIfEmpty(a.Status),
		a.ScheduledStartAt,
		a.ScheduledEndAt,
		nullIfEmpty(a.PreliminaryDiagnosis),
		nullIfEmpty(a.FHIRAppointmentID),
		nullIfEmpty(a.FHIREncounterID),
		nullIfEmpty(a.CreatedBy),
	).Scan(
		&out.AppointmentID,
		&out.PatientID,
		&out.PhysicianID,
		&out.ClinicID,
		&out.AppointmentType,
		&out.BookingChannel,
		&out.Status,
		&out.ScheduledStartAt,
		&out.ScheduledEndAt,
		&out.PreliminaryDiagnosis,
		&out.FHIRAppointmentID,
		&out.FHIREncounterID,
		&out.CreatedBy,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) UpdateAppointmentStatus(ctx context.Context, appointmentID, status string) error {
	_, err := r.pool.Exec(ctx, `
UPDATE appointments
SET status = $2, updated_at = NOW()
WHERE appointment_id = $1`, appointmentID, status)
	return err
}

func (r *PgxRepository) ListAppointmentsByPhysician(ctx context.Context, physicianID string, start, end time.Time) ([]models.Appointment, error) {
	q := `
SELECT appointment_id, patient_id, physician_id, clinic_id, appointment_type, booking_channel,
	status, scheduled_start_at, scheduled_end_at, COALESCE(preliminary_diagnosis, ''), COALESCE(fhir_appointment_id, ''),
	COALESCE(fhir_encounter_id, ''), COALESCE(created_by::text, ''), created_at, updated_at
FROM appointments
WHERE physician_id = $1
  AND scheduled_start_at >= $2
  AND scheduled_start_at <= $3
ORDER BY scheduled_start_at ASC`
	rows, err := r.pool.Query(ctx, q, physicianID, start, end)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.Appointment, 0)
	for rows.Next() {
		var item models.Appointment
		if err := rows.Scan(
			&item.AppointmentID,
			&item.PatientID,
			&item.PhysicianID,
			&item.ClinicID,
			&item.AppointmentType,
			&item.BookingChannel,
			&item.Status,
			&item.ScheduledStartAt,
			&item.ScheduledEndAt,
			&item.PreliminaryDiagnosis,
			&item.FHIRAppointmentID,
			&item.FHIREncounterID,
			&item.CreatedBy,
			&item.CreatedAt,
			&item.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) CreatePatientRemark(ctx context.Context, remark models.PatientRemark) (models.PatientRemark, error) {
	q := `
INSERT INTO patient_remarks (
	patient_id, added_by_user_id, remark_text_original, original_language, remark_text_english,
	remark_types, importance, voice_recording_url, visibility
) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
RETURNING remark_id, patient_id, COALESCE(added_by_user_id::text, ''), remark_text_original, original_language,
	COALESCE(remark_text_english, ''), remark_types, COALESCE(importance, ''), COALESCE(voice_recording_url, ''), visibility, created_at`

	var out models.PatientRemark
	err := r.pool.QueryRow(ctx, q,
		remark.PatientID,
		nullIfEmpty(remark.AddedByUserID),
		remark.RemarkTextOriginal,
		nullIfEmpty(remark.OriginalLanguage),
		nullIfEmpty(remark.RemarkTextEnglish),
		remark.RemarkTypes,
		nullIfEmpty(remark.Importance),
		nullIfEmpty(remark.VoiceRecordingURL),
		nullIfEmpty(remark.Visibility),
	).Scan(
		&out.RemarkID,
		&out.PatientID,
		&out.AddedByUserID,
		&out.RemarkTextOriginal,
		&out.OriginalLanguage,
		&out.RemarkTextEnglish,
		&out.RemarkTypes,
		&out.Importance,
		&out.VoiceRecordingURL,
		&out.Visibility,
		&out.CreatedAt,
	)
	return out, err
}

func (r *PgxRepository) ListPatientRemarks(ctx context.Context, patientID string, limit int) ([]models.PatientRemark, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	q := `
SELECT remark_id, patient_id, COALESCE(added_by_user_id::text, ''), remark_text_original, original_language,
	COALESCE(remark_text_english, ''), remark_types, COALESCE(importance, ''), COALESCE(voice_recording_url, ''), visibility, created_at
FROM patient_remarks
WHERE patient_id = $1
ORDER BY created_at DESC
LIMIT $2`

	rows, err := r.pool.Query(ctx, q, patientID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.PatientRemark, 0, limit)
	for rows.Next() {
		var item models.PatientRemark
		if err := rows.Scan(
			&item.RemarkID,
			&item.PatientID,
			&item.AddedByUserID,
			&item.RemarkTextOriginal,
			&item.OriginalLanguage,
			&item.RemarkTextEnglish,
			&item.RemarkTypes,
			&item.Importance,
			&item.VoiceRecordingURL,
			&item.Visibility,
			&item.CreatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) CreateVoiceJob(ctx context.Context, job models.VoiceJob) (models.VoiceJob, error) {
	q := `
INSERT INTO voice_jobs (
	patient_id, asha_user_id, encounter_id, s3_bucket, s3_key, language_code, context,
	transcription_job_id, processing_status, error_code, error_message, processing_started_at, processing_completed_at
) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
RETURNING voice_job_id, COALESCE(patient_id::text, ''), asha_user_id::text, COALESCE(encounter_id::text, ''), s3_bucket, s3_key,
	language_code, context, COALESCE(transcription_job_id, ''), processing_status, COALESCE(error_code, ''), COALESCE(error_message, ''),
	COALESCE(processing_started_at, NOW()), COALESCE(processing_completed_at, NOW()), created_at, updated_at`

	var out models.VoiceJob
	err := r.pool.QueryRow(ctx, q,
		nullIfEmpty(job.PatientID),
		job.ASHAUserID,
		nullIfEmpty(job.EncounterID),
		job.S3Bucket,
		job.S3Key,
		nullIfEmpty(job.LanguageCode),
		nullIfEmpty(job.Context),
		nullIfEmpty(job.TranscriptionJobID),
		nullIfEmpty(job.ProcessingStatus),
		nullIfEmpty(job.ErrorCode),
		nullIfEmpty(job.ErrorMessage),
		nullIfZeroTime(job.ProcessingStartedAt),
		nullIfZeroTime(job.ProcessingCompletedAt),
	).Scan(
		&out.VoiceJobID,
		&out.PatientID,
		&out.ASHAUserID,
		&out.EncounterID,
		&out.S3Bucket,
		&out.S3Key,
		&out.LanguageCode,
		&out.Context,
		&out.TranscriptionJobID,
		&out.ProcessingStatus,
		&out.ErrorCode,
		&out.ErrorMessage,
		&out.ProcessingStartedAt,
		&out.ProcessingCompletedAt,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) GetVoiceJobByID(ctx context.Context, voiceJobID string) (models.VoiceJob, error) {
	var out models.VoiceJob
	err := r.pool.QueryRow(ctx, `
SELECT voice_job_id, COALESCE(patient_id::text, ''), asha_user_id::text, COALESCE(encounter_id::text, ''), s3_bucket, s3_key,
	language_code, context, COALESCE(transcription_job_id, ''), processing_status, COALESCE(error_code, ''), COALESCE(error_message, ''),
	COALESCE(processing_started_at, NOW()), COALESCE(processing_completed_at, NOW()), created_at, updated_at
FROM voice_jobs
WHERE voice_job_id = $1`, voiceJobID).Scan(
		&out.VoiceJobID,
		&out.PatientID,
		&out.ASHAUserID,
		&out.EncounterID,
		&out.S3Bucket,
		&out.S3Key,
		&out.LanguageCode,
		&out.Context,
		&out.TranscriptionJobID,
		&out.ProcessingStatus,
		&out.ErrorCode,
		&out.ErrorMessage,
		&out.ProcessingStartedAt,
		&out.ProcessingCompletedAt,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) ListVoiceJobsByASHA(ctx context.Context, ashaUserID string, limit int) ([]models.VoiceJob, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	rows, err := r.pool.Query(ctx, `
SELECT voice_job_id, COALESCE(patient_id::text, ''), asha_user_id::text, COALESCE(encounter_id::text, ''), s3_bucket, s3_key,
	language_code, context, COALESCE(transcription_job_id, ''), processing_status, COALESCE(error_code, ''), COALESCE(error_message, ''),
	COALESCE(processing_started_at, NOW()), COALESCE(processing_completed_at, NOW()), created_at, updated_at
FROM voice_jobs
WHERE asha_user_id::text = $1
ORDER BY created_at DESC
LIMIT $2`, ashaUserID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.VoiceJob, 0, limit)
	for rows.Next() {
		var item models.VoiceJob
		if err := rows.Scan(
			&item.VoiceJobID,
			&item.PatientID,
			&item.ASHAUserID,
			&item.EncounterID,
			&item.S3Bucket,
			&item.S3Key,
			&item.LanguageCode,
			&item.Context,
			&item.TranscriptionJobID,
			&item.ProcessingStatus,
			&item.ErrorCode,
			&item.ErrorMessage,
			&item.ProcessingStartedAt,
			&item.ProcessingCompletedAt,
			&item.CreatedAt,
			&item.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) UpdateVoiceJobStatus(ctx context.Context, voiceJobID, status, transcriptionJobID, errorCode, errorMessage string, completedAt *time.Time) error {
	_, err := r.pool.Exec(ctx, `
UPDATE voice_jobs
SET processing_status = $2,
	transcription_job_id = COALESCE(NULLIF($3, ''), transcription_job_id),
	error_code = NULLIF($4, ''),
	error_message = NULLIF($5, ''),
	processing_completed_at = COALESCE($6, processing_completed_at),
	updated_at = NOW()
WHERE voice_job_id = $1`,
		voiceJobID, status, transcriptionJobID, errorCode, errorMessage, completedAt)
	return err
}

func (r *PgxRepository) EnsurePatientByExternalID(ctx context.Context, externalID string) (models.Patient, error) {
	if externalID == "" {
		return models.Patient{}, fmt.Errorf("external patient id is required")
	}

	var out models.Patient
	err := r.pool.QueryRow(ctx, `
SELECT patient_id, fhir_patient_id, COALESCE(abha_id, ''), full_name, COALESCE(gender, ''), COALESCE(date_of_birth::text, ''),
	COALESCE(phone, ''), COALESCE(preferred_language, ''), COALESCE(primary_clinic_id::text, ''), source_system, read_only,
	COALESCE(last_synced_at, NOW()), created_at, updated_at
FROM patients
WHERE patient_id::text = $1 OR fhir_patient_id = $1
LIMIT 1`, externalID).Scan(
		&out.PatientID,
		&out.FHIRPatientID,
		&out.ABHAID,
		&out.FullName,
		&out.Gender,
		&out.DateOfBirth,
		&out.Phone,
		&out.PreferredLanguage,
		&out.PrimaryClinicID,
		&out.SourceSystem,
		&out.ReadOnly,
		&out.LastSyncedAt,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	if err == nil {
		return out, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return models.Patient{}, err
	}

	return r.UpsertPatientIndex(ctx, models.Patient{
		FHIRPatientID:     externalID,
		FullName:          "Unknown Patient",
		SourceSystem:      "app",
		ReadOnly:          false,
		PreferredLanguage: "hi",
		LastSyncedAt:      time.Now().UTC(),
	})
}

func (r *PgxRepository) CreateEncounter(ctx context.Context, encounter models.EncounterRecord) (models.EncounterRecord, error) {
	q := `
INSERT INTO encounters (
	patient_id, asha_user_id, clinic_id, visit_type, status, occurred_at,
	source_audio_bucket, source_audio_key, transcription_text, translation_text,
	extracted_entities, clinical_alerts, fhir_encounter_id, sync_status, idempotency_key
) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb,$12::jsonb,$13,$14,$15)
RETURNING encounter_id, patient_id::text, asha_user_id::text, COALESCE(clinic_id::text, ''), visit_type, status, occurred_at,
	COALESCE(source_audio_bucket, ''), COALESCE(source_audio_key, ''), COALESCE(transcription_text, ''), COALESCE(translation_text, ''),
	extracted_entities::text, clinical_alerts::text, COALESCE(fhir_encounter_id, ''), sync_status::text, COALESCE(idempotency_key, ''),
	created_at, updated_at`

	var out models.EncounterRecord
	err := r.pool.QueryRow(ctx, q,
		encounter.PatientID,
		encounter.ASHAUserID,
		nullIfEmpty(encounter.ClinicID),
		nullIfEmpty(encounter.VisitType),
		nullIfEmpty(encounter.Status),
		encounter.OccurredAt,
		nullIfEmpty(encounter.SourceAudioBucket),
		nullIfEmpty(encounter.SourceAudioKey),
		nullIfEmpty(encounter.TranscriptionText),
		nullIfEmpty(encounter.TranslationText),
		defaultJSON(encounter.ExtractedEntities, "{}"),
		defaultJSON(encounter.ClinicalAlerts, "[]"),
		nullIfEmpty(encounter.FHIREncounterID),
		nullIfEmpty(encounter.SyncStatus),
		nullIfEmpty(encounter.IdempotencyKey),
	).Scan(
		&out.EncounterID,
		&out.PatientID,
		&out.ASHAUserID,
		&out.ClinicID,
		&out.VisitType,
		&out.Status,
		&out.OccurredAt,
		&out.SourceAudioBucket,
		&out.SourceAudioKey,
		&out.TranscriptionText,
		&out.TranslationText,
		&out.ExtractedEntities,
		&out.ClinicalAlerts,
		&out.FHIREncounterID,
		&out.SyncStatus,
		&out.IdempotencyKey,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) ListEncountersByASHA(ctx context.Context, ashaUserID string, limit int) ([]models.EncounterRecord, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	rows, err := r.pool.Query(ctx, `
SELECT encounter_id, patient_id::text, asha_user_id::text, COALESCE(clinic_id::text, ''), visit_type, status, occurred_at,
	COALESCE(source_audio_bucket, ''), COALESCE(source_audio_key, ''), COALESCE(transcription_text, ''), COALESCE(translation_text, ''),
	extracted_entities::text, clinical_alerts::text, COALESCE(fhir_encounter_id, ''), sync_status::text, COALESCE(idempotency_key, ''),
	created_at, updated_at
FROM encounters
WHERE asha_user_id::text = $1
ORDER BY created_at DESC
LIMIT $2`, ashaUserID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.EncounterRecord, 0, limit)
	for rows.Next() {
		var item models.EncounterRecord
		if err := rows.Scan(
			&item.EncounterID,
			&item.PatientID,
			&item.ASHAUserID,
			&item.ClinicID,
			&item.VisitType,
			&item.Status,
			&item.OccurredAt,
			&item.SourceAudioBucket,
			&item.SourceAudioKey,
			&item.TranscriptionText,
			&item.TranslationText,
			&item.ExtractedEntities,
			&item.ClinicalAlerts,
			&item.FHIREncounterID,
			&item.SyncStatus,
			&item.IdempotencyKey,
			&item.CreatedAt,
			&item.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) UpdateEncounterFHIRSync(ctx context.Context, encounterID, fhirEncounterID, syncStatus string) error {
	_, err := r.pool.Exec(ctx, `
UPDATE encounters
SET fhir_encounter_id = NULLIF($2, ''),
	sync_status = $3::encounter_sync_status,
	updated_at = NOW()
WHERE encounter_id = $1`, encounterID, fhirEncounterID, syncStatus)
	return err
}

func (r *PgxRepository) CreateEncounterAlerts(ctx context.Context, encounterID string, alerts []models.EncounterAlert) error {
	if len(alerts) == 0 {
		return nil
	}
	for _, alert := range alerts {
		_, err := r.pool.Exec(ctx, `
INSERT INTO encounter_alerts (encounter_id, severity, alert_code, message, metadata)
VALUES ($1,$2,$3,$4,$5::jsonb)`,
			encounterID,
			nullIfEmpty(alert.Severity),
			nullIfEmpty(alert.AlertCode),
			alert.Message,
			defaultJSON(alert.Metadata, "{}"),
		)
		if err != nil {
			return err
		}
	}
	return nil
}

func nullIfEmpty(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func nullIfZeroTime(t time.Time) any {
	if t.IsZero() {
		return nil
	}
	return t
}

func defaultJSON(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}

var _ Repository = (*PgxRepository)(nil)
var _ = pgx.ErrNoRows
