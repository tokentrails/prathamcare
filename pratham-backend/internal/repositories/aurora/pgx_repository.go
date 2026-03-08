package aurora

import (
	"context"
	"errors"
	"fmt"
	"strings"
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

func (r *PgxRepository) CreatePatient(ctx context.Context, patient models.Patient) (models.Patient, error) {
	q := `
INSERT INTO patients (
	fhir_patient_id, abha_id, abha_number, abha_address, first_name, middle_name, last_name, full_name, gender,
	date_of_birth, age_years, phone, phone_number, phone_e164, email, address_line1, address_line2, village_or_ward,
	gram_panchayat, block_or_taluk, district, state, pincode, landmark, consent_flags, created_by, updated_by, status,
	preferred_language, source_system, read_only, last_synced_at
) VALUES (
	$1,$2,$3,$4,$5,$6,$7,$8,$9,
	$10,$11,$12,$13,$14,$15,$16,$17,$18,
	$19,$20,$21,$22,$23,$24,COALESCE($25::jsonb, '{}'::jsonb),$26,$27,$28,
	$29,$30,$31,$32
)
RETURNING ` + patientSelectClause("")

	var out models.Patient
	err := r.pool.QueryRow(ctx, q,
		patient.FHIRPatientID,
		nullIfEmpty(patient.ABHAID),
		nullIfEmpty(patient.ABHANumber),
		nullIfEmpty(patient.ABHAAddress),
		nullIfEmpty(patient.FirstName),
		nullIfEmpty(patient.MiddleName),
		nullIfEmpty(patient.LastName),
		nullIfEmpty(patient.FullName),
		nullIfEmpty(patient.Gender),
		nullIfEmpty(patient.DateOfBirth),
		nullIfZeroInt(patient.AgeYears),
		nullIfEmpty(patient.Phone),
		nullIfEmpty(patient.PhoneNumber),
		nullIfEmpty(patient.PhoneE164),
		nullIfEmpty(patient.Email),
		nullIfEmpty(patient.AddressLine1),
		nullIfEmpty(patient.AddressLine2),
		nullIfEmpty(patient.VillageOrWard),
		nullIfEmpty(patient.GramPanchayat),
		nullIfEmpty(patient.BlockOrTaluk),
		nullIfEmpty(patient.District),
		nullIfEmpty(patient.State),
		nullIfEmpty(patient.Pincode),
		nullIfEmpty(patient.Landmark),
		defaultJSON(patient.ConsentFlags, "{}"),
		nullIfEmpty(patient.CreatedBy),
		nullIfEmpty(patient.UpdatedBy),
		nullIfEmpty(patient.Status),
		nullIfEmpty(patient.PreferredLanguage),
		nullIfEmpty(patient.SourceSystem),
		patient.ReadOnly,
		nullIfZeroTime(patient.LastSyncedAt),
	).Scan(patientScanTargets(&out)...)
	return out, err
}

func (r *PgxRepository) SearchPatients(ctx context.Context, viewerUserRef string, viewerUserUUID *string, filter models.PatientSearchFilter) ([]models.Patient, error) {
	limit := filter.Limit
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	q := `
SELECT ` + patientSelectClause("p") + `
FROM patients p
WHERE ` + patientVisibilityWhereClause() + `
AND (
	$3 = '' OR p.patient_id::text = $3 OR p.fhir_patient_id = $3
)
AND (
	$4 = '' OR COALESCE(NULLIF(p.phone_e164, ''), COALESCE(NULLIF(p.phone_number, ''), COALESCE(NULLIF(p.phone, ''), ''))) = $4
)
AND (
	$5 = '' OR COALESCE(NULLIF(p.abha_number, ''), COALESCE(NULLIF(p.abha_id, ''), '')) = $5
)
AND (
	$6 = '' OR p.full_name ILIKE '%' || $6 || '%' OR
		p.first_name ILIKE '%' || $6 || '%' OR
		p.last_name ILIKE '%' || $6 || '%'
)
ORDER BY p.updated_at DESC
LIMIT $7`

	rows, err := r.pool.Query(ctx, q,
		strings.TrimSpace(viewerUserRef),
		nullableUUID(viewerUserUUID),
		strings.TrimSpace(filter.PatientRef),
		strings.TrimSpace(filter.PhoneE164),
		strings.TrimSpace(filter.ABHANumber),
		strings.TrimSpace(filter.Query),
		limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.Patient, 0, limit)
	for rows.Next() {
		var item models.Patient
		if err := rows.Scan(patientScanTargets(&item)...); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) GetPatientByIDForUser(ctx context.Context, viewerUserRef string, viewerUserUUID *string, patientID string) (models.Patient, error) {
	q := `
SELECT ` + patientSelectClause("p") + `
FROM patients p
WHERE p.patient_id::text = $3
  AND ` + patientVisibilityWhereClause()

	var out models.Patient
	err := r.pool.QueryRow(ctx, q,
		strings.TrimSpace(viewerUserRef),
		nullableUUID(viewerUserUUID),
		strings.TrimSpace(patientID),
	).Scan(patientScanTargets(&out)...)
	return out, err
}

func (r *PgxRepository) UpdatePatient(ctx context.Context, viewerUserRef string, viewerUserUUID *string, patient models.Patient) (models.Patient, error) {
	q := `
UPDATE patients p
SET
	abha_id = NULLIF($4, ''),
	abha_number = NULLIF($5, ''),
	abha_address = NULLIF($6, ''),
	first_name = NULLIF($7, ''),
	middle_name = NULLIF($8, ''),
	last_name = NULLIF($9, ''),
	full_name = NULLIF($10, ''),
	gender = NULLIF($11, ''),
	date_of_birth = NULLIF($12, '')::date,
	age_years = $13,
	phone = NULLIF($14, ''),
	phone_number = NULLIF($15, ''),
	phone_e164 = NULLIF($16, ''),
	email = NULLIF($17, ''),
	address_line1 = NULLIF($18, ''),
	address_line2 = NULLIF($19, ''),
	village_or_ward = NULLIF($20, ''),
	gram_panchayat = NULLIF($21, ''),
	block_or_taluk = NULLIF($22, ''),
	district = NULLIF($23, ''),
	state = NULLIF($24, ''),
	pincode = NULLIF($25, ''),
	landmark = NULLIF($26, ''),
	consent_flags = COALESCE($27::jsonb, '{}'::jsonb),
	updated_by = NULLIF($28, ''),
	status = NULLIF($29, ''),
	preferred_language = NULLIF($30, '')
WHERE p.patient_id::text = $3
  AND ` + patientVisibilityWhereClause() + `
RETURNING ` + patientSelectClause("p")

	var out models.Patient
	err := r.pool.QueryRow(ctx, q,
		strings.TrimSpace(viewerUserRef),
		nullableUUID(viewerUserUUID),
		strings.TrimSpace(patient.PatientID),
		strings.TrimSpace(patient.ABHAID),
		strings.TrimSpace(patient.ABHANumber),
		strings.TrimSpace(patient.ABHAAddress),
		strings.TrimSpace(patient.FirstName),
		strings.TrimSpace(patient.MiddleName),
		strings.TrimSpace(patient.LastName),
		strings.TrimSpace(patient.FullName),
		strings.TrimSpace(patient.Gender),
		strings.TrimSpace(patient.DateOfBirth),
		nullIfZeroInt(patient.AgeYears),
		strings.TrimSpace(patient.Phone),
		strings.TrimSpace(patient.PhoneNumber),
		strings.TrimSpace(patient.PhoneE164),
		strings.TrimSpace(patient.Email),
		strings.TrimSpace(patient.AddressLine1),
		strings.TrimSpace(patient.AddressLine2),
		strings.TrimSpace(patient.VillageOrWard),
		strings.TrimSpace(patient.GramPanchayat),
		strings.TrimSpace(patient.BlockOrTaluk),
		strings.TrimSpace(patient.District),
		strings.TrimSpace(patient.State),
		strings.TrimSpace(patient.Pincode),
		strings.TrimSpace(patient.Landmark),
		defaultJSON(patient.ConsentFlags, "{}"),
		strings.TrimSpace(patient.UpdatedBy),
		strings.TrimSpace(patient.Status),
		strings.TrimSpace(patient.PreferredLanguage),
	).Scan(patientScanTargets(&out)...)
	return out, err
}

func (r *PgxRepository) ListRecentPatientsByUser(ctx context.Context, viewerUserRef string, viewerUserUUID *string, limit int) ([]models.Patient, error) {
	if limit <= 0 || limit > 50 {
		limit = 10
	}
	q := `
SELECT ` + patientSelectClause("p") + `
FROM patients p
WHERE ` + patientVisibilityWhereClause() + `
ORDER BY p.updated_at DESC
LIMIT $3`

	rows, err := r.pool.Query(ctx, q, strings.TrimSpace(viewerUserRef), nullableUUID(viewerUserUUID), limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.Patient, 0, limit)
	for rows.Next() {
		var item models.Patient
		if err := rows.Scan(patientScanTargets(&item)...); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) CreateEncounter(ctx context.Context, encounter models.EncounterRecord) (models.EncounterRecord, error) {
	q := `
INSERT INTO encounters (
	patient_id, asha_user_id, appointment_id, clinic_id, visit_type, status, occurred_at,
	source_audio_bucket, source_audio_key, transcription_text, translation_text,
	extracted_entities, clinical_alerts, fhir_encounter_id, sync_status, idempotency_key
) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,$13::jsonb,$14,$15,$16)
ON CONFLICT (idempotency_key) DO UPDATE
SET updated_at = encounters.updated_at
RETURNING encounter_id, patient_id::text, asha_user_id::text, COALESCE(appointment_id::text, ''), COALESCE(clinic_id::text, ''), visit_type, status, occurred_at,
	COALESCE(source_audio_bucket, ''), COALESCE(source_audio_key, ''), COALESCE(transcription_text, ''), COALESCE(translation_text, ''),
	extracted_entities::text, clinical_alerts::text, COALESCE(fhir_encounter_id, ''), sync_status::text, COALESCE(idempotency_key, ''),
	created_at, updated_at`

	var out models.EncounterRecord
	err := r.pool.QueryRow(ctx, q,
		encounter.PatientID,
		encounter.ASHAUserID,
		nullIfEmpty(encounter.AppointmentID),
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
		&out.AppointmentID,
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
SELECT encounter_id, patient_id::text, asha_user_id::text, COALESCE(appointment_id::text, ''), COALESCE(clinic_id::text, ''), visit_type, status, occurred_at,
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
			&item.AppointmentID,
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

func (r *PgxRepository) GetEncounterByID(ctx context.Context, encounterID string) (models.EncounterRecord, error) {
	var out models.EncounterRecord
	err := r.pool.QueryRow(ctx, `
SELECT encounter_id, patient_id::text, asha_user_id::text, COALESCE(appointment_id::text, ''), COALESCE(clinic_id::text, ''), visit_type, status, occurred_at,
	COALESCE(source_audio_bucket, ''), COALESCE(source_audio_key, ''), COALESCE(transcription_text, ''), COALESCE(translation_text, ''),
	extracted_entities::text, clinical_alerts::text, COALESCE(fhir_encounter_id, ''), sync_status::text, COALESCE(idempotency_key, ''),
	created_at, updated_at
FROM encounters
WHERE encounter_id = $1`, encounterID).Scan(
		&out.EncounterID,
		&out.PatientID,
		&out.ASHAUserID,
		&out.AppointmentID,
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

func (r *PgxRepository) FindPatientForPublicRequest(ctx context.Context, phoneE164, fullName, pincode, abhaNumber string) (models.Patient, error) {
	fullName = strings.TrimSpace(fullName)
	pincode = strings.TrimSpace(pincode)
	phoneE164 = strings.TrimSpace(phoneE164)
	abhaNumber = strings.TrimSpace(abhaNumber)

	var out models.Patient
	if abhaNumber != "" {
		err := r.pool.QueryRow(ctx, `
SELECT `+patientSelectClause("p")+`
FROM patients p
WHERE COALESCE(NULLIF(p.abha_number, ''), COALESCE(NULLIF(p.abha_id, ''), '')) = $1
ORDER BY p.updated_at DESC
LIMIT 1`, abhaNumber).Scan(patientScanTargets(&out)...)
		if err == nil {
			return out, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return models.Patient{}, err
		}
	}

	err := r.pool.QueryRow(ctx, `
SELECT `+patientSelectClause("p")+`
FROM patients p
WHERE COALESCE(NULLIF(p.phone_e164, ''), COALESCE(NULLIF(p.phone_number, ''), COALESCE(NULLIF(p.phone, ''), ''))) = $1
  AND (
    ($2 <> '' AND p.full_name ILIKE '%' || $2 || '%')
    OR ($3 <> '' AND COALESCE(p.pincode, '') = $3)
  )
ORDER BY p.updated_at DESC
LIMIT 1`, phoneE164, fullName, pincode).Scan(patientScanTargets(&out)...)
	if err != nil {
		return models.Patient{}, err
	}
	return out, nil
}

func (r *PgxRepository) CountRecentPublicAppointmentRequests(ctx context.Context, phoneE164, requestIP string, within time.Duration) (int, error) {
	seconds := int(within.Seconds())
	if seconds <= 0 {
		seconds = 600
	}
	var count int
	err := r.pool.QueryRow(ctx, `
SELECT COUNT(*)
FROM asha_appointments
WHERE created_at >= NOW() - ($3 || ' seconds')::interval
  AND (
    requestor_phone = $1
    OR COALESCE(notes->>'request_ip', '') = $2
  )`, strings.TrimSpace(phoneE164), strings.TrimSpace(requestIP), seconds).Scan(&count)
	return count, err
}

func (r *PgxRepository) HasRecentDuplicatePublicAppointment(ctx context.Context, phoneE164, reasonCode, pincode string, within time.Duration) (bool, error) {
	seconds := int(within.Seconds())
	if seconds <= 0 {
		seconds = 600
	}
	var exists bool
	err := r.pool.QueryRow(ctx, `
SELECT EXISTS(
  SELECT 1
  FROM asha_appointments
  WHERE requestor_phone = $1
    AND reason_code = $2
    AND pincode = $3
    AND created_at >= NOW() - ($4 || ' seconds')::interval
)`, strings.TrimSpace(phoneE164), strings.TrimSpace(reasonCode), strings.TrimSpace(pincode), seconds).Scan(&exists)
	return exists, err
}

func (r *PgxRepository) MatchASHAByLocation(ctx context.Context, villageOrWard, blockOrTaluk, district, state, pincode string, latitude, longitude *float64) (models.ASHAMatchResult, error) {
	var out models.ASHAMatchResult

	err := r.pool.QueryRow(ctx, `
SELECT ap.user_id::text, 'pincode'::text AS assigned_method, 100.0::numeric AS assignment_score
FROM asha_profiles ap
JOIN users u ON u.user_id = ap.user_id
WHERE u.role = 'asha_worker'
  AND u.is_active = TRUE
  AND COALESCE(ap.service_pincode, '') <> ''
  AND ap.service_pincode = $1
ORDER BY ap.updated_at ASC
LIMIT 1`, strings.TrimSpace(pincode)).Scan(&out.ASHAUserID, &out.AssignedMethod, &out.AssignmentScore)
	if err == nil {
		return out, nil
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return models.ASHAMatchResult{}, err
	}

	err = r.pool.QueryRow(ctx, `
SELECT ap.user_id::text, 'village'::text AS assigned_method, 92.0::numeric AS assignment_score
FROM asha_profiles ap
JOIN users u ON u.user_id = ap.user_id
WHERE u.role = 'asha_worker'
  AND u.is_active = TRUE
  AND LOWER(COALESCE(ap.assigned_village, '')) = LOWER($1)
  AND LOWER(COALESCE(ap.assigned_block, '')) = LOWER($2)
  AND LOWER(COALESCE(ap.assigned_district, '')) = LOWER($3)
  AND LOWER(COALESCE(ap.state, '')) = LOWER($4)
ORDER BY ap.updated_at ASC
LIMIT 1`,
		strings.TrimSpace(villageOrWard),
		strings.TrimSpace(blockOrTaluk),
		strings.TrimSpace(district),
		strings.TrimSpace(state),
	).Scan(&out.ASHAUserID, &out.AssignedMethod, &out.AssignmentScore)
	if err == nil {
		return out, nil
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return models.ASHAMatchResult{}, err
	}

	if latitude != nil && longitude != nil {
		err = r.pool.QueryRow(ctx, `
SELECT ap.user_id::text,
       'geo'::text AS assigned_method,
       GREATEST(60.0::numeric, (95.0 - (dist.km * 2.5))::numeric) AS assignment_score
FROM asha_profiles ap
JOIN users u ON u.user_id = ap.user_id
CROSS JOIN LATERAL (
  SELECT 6371 * ACOS(
    LEAST(
      1.0,
      GREATEST(
        -1.0,
        COS(RADIANS($1)) * COS(RADIANS(ap.service_latitude)) * COS(RADIANS(ap.service_longitude) - RADIANS($2))
        + SIN(RADIANS($1)) * SIN(RADIANS(ap.service_latitude))
      )
    )
  ) AS km
) dist
WHERE u.role = 'asha_worker'
  AND u.is_active = TRUE
  AND ap.service_latitude IS NOT NULL
  AND ap.service_longitude IS NOT NULL
  AND dist.km <= COALESCE(ap.service_radius_km, 10)
ORDER BY dist.km ASC, ap.updated_at ASC
LIMIT 1`, *latitude, *longitude).Scan(&out.ASHAUserID, &out.AssignedMethod, &out.AssignmentScore)
		if err == nil {
			return out, nil
		}
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return models.ASHAMatchResult{}, err
		}
	}

	err = r.pool.QueryRow(ctx, `
WITH candidate AS (
  SELECT ap.user_id,
         COUNT(a.appointment_id) FILTER (
           WHERE a.status IN ('requested', 'assigned', 'accepted', 'in_progress')
         ) AS active_load
  FROM asha_profiles ap
  JOIN users u ON u.user_id = ap.user_id
  LEFT JOIN asha_appointments a ON a.asha_user_id = ap.user_id
  WHERE u.role = 'asha_worker'
    AND u.is_active = TRUE
    AND LOWER(COALESCE(ap.assigned_district, '')) = LOWER($1)
    AND LOWER(COALESCE(ap.state, '')) = LOWER($2)
  GROUP BY ap.user_id
)
SELECT user_id::text, 'district'::text AS assigned_method, 70.0::numeric AS assignment_score
FROM candidate
ORDER BY active_load ASC, user_id ASC
LIMIT 1`, strings.TrimSpace(district), strings.TrimSpace(state)).Scan(&out.ASHAUserID, &out.AssignedMethod, &out.AssignmentScore)
	if err != nil {
		return models.ASHAMatchResult{}, err
	}
	return out, nil
}

func (r *PgxRepository) CreateASHAAppointment(ctx context.Context, appt models.ASHAAppointment) (models.ASHAAppointment, error) {
	var out models.ASHAAppointment
	err := r.pool.QueryRow(ctx, `
INSERT INTO asha_appointments (
  patient_id, asha_user_id, status, reason_code, reason_text, preferred_date, preferred_time_slot,
  visit_type, source_channel, requestor_name, requestor_phone, requestor_email,
  address_line1, address_line2, village_or_ward, gram_panchayat, block_or_taluk, district, state, pincode,
  latitude, longitude, assigned_method, assignment_score, encounter_id, notes
)
VALUES (
  $1, $2, $3::asha_appointment_status, $4, $5, NULLIF($6, '')::date, NULLIF($7, ''),
  $8, $9, $10, $11, $12,
  $13, $14, $15, $16, $17, $18, $19, $20,
  $21, $22, $23, $24, NULLIF($25, '')::uuid, COALESCE($26::jsonb, '{}'::jsonb)
)
RETURNING appointment_id::text, patient_id::text, COALESCE(asha_user_id::text, ''), status::text, reason_code,
  COALESCE(reason_text, ''), COALESCE(to_char(preferred_date, 'YYYY-MM-DD'), ''), COALESCE(preferred_time_slot, ''),
  visit_type, source_channel, requestor_name, requestor_phone, COALESCE(requestor_email, ''),
  address_line1, COALESCE(address_line2, ''), COALESCE(village_or_ward, ''), COALESCE(gram_panchayat, ''),
  COALESCE(block_or_taluk, ''), district, state, pincode, COALESCE(latitude, 0), COALESCE(longitude, 0),
  COALESCE(assigned_method, ''), COALESCE(assignment_score, 0), COALESCE(encounter_id::text, ''), notes::text,
  created_at, updated_at`,
		appt.PatientID,
		nullIfEmpty(appt.ASHAUserID),
		appt.Status,
		strings.TrimSpace(appt.ReasonCode),
		nullIfEmpty(appt.ReasonText),
		nullIfEmpty(appt.PreferredDate),
		nullIfEmpty(appt.PreferredTimeSlot),
		nullIfEmpty(appt.VisitType),
		nullIfEmpty(appt.SourceChannel),
		strings.TrimSpace(appt.RequestorName),
		strings.TrimSpace(appt.RequestorPhone),
		nullIfEmpty(appt.RequestorEmail),
		strings.TrimSpace(appt.AddressLine1),
		nullIfEmpty(appt.AddressLine2),
		nullIfEmpty(appt.VillageOrWard),
		nullIfEmpty(appt.GramPanchayat),
		nullIfEmpty(appt.BlockOrTaluk),
		strings.TrimSpace(appt.District),
		strings.TrimSpace(appt.State),
		strings.TrimSpace(appt.Pincode),
		nullIfZeroFloat(appt.Latitude),
		nullIfZeroFloat(appt.Longitude),
		nullIfEmpty(appt.AssignedMethod),
		nullIfZeroFloat(appt.AssignmentScore),
		nullIfEmpty(appt.EncounterID),
		defaultJSON(appt.Notes, "{}"),
	).Scan(
		&out.AppointmentID,
		&out.PatientID,
		&out.ASHAUserID,
		&out.Status,
		&out.ReasonCode,
		&out.ReasonText,
		&out.PreferredDate,
		&out.PreferredTimeSlot,
		&out.VisitType,
		&out.SourceChannel,
		&out.RequestorName,
		&out.RequestorPhone,
		&out.RequestorEmail,
		&out.AddressLine1,
		&out.AddressLine2,
		&out.VillageOrWard,
		&out.GramPanchayat,
		&out.BlockOrTaluk,
		&out.District,
		&out.State,
		&out.Pincode,
		&out.Latitude,
		&out.Longitude,
		&out.AssignedMethod,
		&out.AssignmentScore,
		&out.EncounterID,
		&out.Notes,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) ListASHAAppointments(ctx context.Context, filter models.ASHAAppointmentListFilter) ([]models.ASHAAppointment, error) {
	limit := filter.Limit
	if limit <= 0 || limit > 100 {
		limit = 25
	}
	rows, err := r.pool.Query(ctx, `
SELECT appointment_id::text, patient_id::text, COALESCE(asha_user_id::text, ''), status::text, reason_code,
  COALESCE(reason_text, ''), COALESCE(to_char(preferred_date, 'YYYY-MM-DD'), ''), COALESCE(preferred_time_slot, ''),
  visit_type, source_channel, requestor_name, requestor_phone, COALESCE(requestor_email, ''),
  address_line1, COALESCE(address_line2, ''), COALESCE(village_or_ward, ''), COALESCE(gram_panchayat, ''),
  COALESCE(block_or_taluk, ''), district, state, pincode, COALESCE(latitude, 0), COALESCE(longitude, 0),
  COALESCE(assigned_method, ''), COALESCE(assignment_score, 0), COALESCE(encounter_id::text, ''), notes::text,
  created_at, updated_at
FROM asha_appointments
WHERE asha_user_id::text = $1
  AND ($2 = '' OR status::text = $2)
  AND ($3 = '' OR COALESCE(preferred_date::text, created_at::date::text) >= $3)
  AND ($4 = '' OR COALESCE(preferred_date::text, created_at::date::text) <= $4)
ORDER BY
  CASE status
    WHEN 'requested' THEN 1
    WHEN 'assigned' THEN 2
    WHEN 'accepted' THEN 3
    WHEN 'in_progress' THEN 4
    WHEN 'completed' THEN 9
    WHEN 'cancelled' THEN 10
    ELSE 8
  END ASC,
  COALESCE(preferred_date, created_at::date) ASC,
  created_at DESC
LIMIT $5`,
		strings.TrimSpace(filter.ASHAUserID),
		strings.TrimSpace(filter.Status),
		strings.TrimSpace(filter.FromDate),
		strings.TrimSpace(filter.ToDate),
		limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.ASHAAppointment, 0, limit)
	for rows.Next() {
		var item models.ASHAAppointment
		if err := rows.Scan(
			&item.AppointmentID,
			&item.PatientID,
			&item.ASHAUserID,
			&item.Status,
			&item.ReasonCode,
			&item.ReasonText,
			&item.PreferredDate,
			&item.PreferredTimeSlot,
			&item.VisitType,
			&item.SourceChannel,
			&item.RequestorName,
			&item.RequestorPhone,
			&item.RequestorEmail,
			&item.AddressLine1,
			&item.AddressLine2,
			&item.VillageOrWard,
			&item.GramPanchayat,
			&item.BlockOrTaluk,
			&item.District,
			&item.State,
			&item.Pincode,
			&item.Latitude,
			&item.Longitude,
			&item.AssignedMethod,
			&item.AssignmentScore,
			&item.EncounterID,
			&item.Notes,
			&item.CreatedAt,
			&item.UpdatedAt,
		); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) ListASHADailyAppointmentSignals(ctx context.Context, ashaUserID, date, timezone string) ([]models.ASHADailyAppointmentSignal, error) {
	rows, err := r.pool.Query(ctx, `
SELECT
  a.appointment_id::text,
  a.patient_id::text,
  COALESCE(NULLIF(p.full_name, ''), a.requestor_name) AS patient_name,
  a.status::text,
  a.reason_code,
  COALESCE(a.reason_text, ''),
  COALESCE(to_char(a.preferred_date, 'YYYY-MM-DD'), ''),
  COALESCE(a.preferred_time_slot, ''),
  a.visit_type,
  a.created_at,
  COALESCE(p.age_years, 0),
  COALESCE(p.gender, ''),
  (
    SELECT MAX(e.occurred_at)
    FROM encounters e
    WHERE e.patient_id = a.patient_id
  ) AS last_encounter_at,
  (
    SELECT COUNT(*)::int
    FROM encounters e
    WHERE e.patient_id = a.patient_id
      AND e.occurred_at >= NOW() - INTERVAL '30 days'
  ) AS recent_encounters_30d,
  (
    SELECT COUNT(*)::int
    FROM encounters e
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(e.clinical_alerts, '[]'::jsonb)) AS alert
    WHERE e.patient_id = a.patient_id
      AND e.occurred_at >= NOW() - INTERVAL '30 days'
      AND LOWER(COALESCE(alert->>'severity', '')) = 'critical'
  ) AS critical_alerts_30d,
  (
    SELECT COUNT(*)::int
    FROM encounters e
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(e.clinical_alerts, '[]'::jsonb)) AS alert
    WHERE e.patient_id = a.patient_id
      AND e.occurred_at >= NOW() - INTERVAL '30 days'
      AND LOWER(COALESCE(alert->>'severity', '')) = 'high'
  ) AS high_alerts_30d
FROM asha_appointments a
LEFT JOIN patients p ON p.patient_id = a.patient_id
WHERE a.asha_user_id::text = $1
  AND COALESCE(a.preferred_date, (a.created_at AT TIME ZONE $2)::date) = $3::date
  AND a.status::text <> 'cancelled'
ORDER BY
  CASE COALESCE(a.preferred_time_slot, '')
    WHEN 'morning' THEN 1
    WHEN 'afternoon' THEN 2
    WHEN 'evening' THEN 3
    ELSE 9
  END ASC,
  a.created_at ASC`,
		strings.TrimSpace(ashaUserID),
		strings.TrimSpace(timezone),
		strings.TrimSpace(date),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.ASHADailyAppointmentSignal, 0, 16)
	for rows.Next() {
		var item models.ASHADailyAppointmentSignal
		if err := rows.Scan(
			&item.AppointmentID,
			&item.PatientID,
			&item.PatientName,
			&item.Status,
			&item.ReasonCode,
			&item.ReasonText,
			&item.PreferredDate,
			&item.PreferredTimeSlot,
			&item.VisitType,
			&item.CreatedAt,
			&item.AgeYears,
			&item.Gender,
			&item.LastEncounterAt,
			&item.RecentEncounterCount,
			&item.RecentCriticalAlerts30,
			&item.RecentHighAlerts30,
		); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) GetASHAAppointmentByID(ctx context.Context, appointmentID string) (models.ASHAAppointment, error) {
	return r.getASHAAppointment(ctx, appointmentID, "")
}

func (r *PgxRepository) GetASHAAppointmentByIDForASHA(ctx context.Context, appointmentID, ashaUserID string) (models.ASHAAppointment, error) {
	return r.getASHAAppointment(ctx, appointmentID, ashaUserID)
}

func (r *PgxRepository) getASHAAppointment(ctx context.Context, appointmentID, ashaUserID string) (models.ASHAAppointment, error) {
	var out models.ASHAAppointment
	err := r.pool.QueryRow(ctx, `
SELECT appointment_id::text, patient_id::text, COALESCE(asha_user_id::text, ''), status::text, reason_code,
  COALESCE(reason_text, ''), COALESCE(to_char(preferred_date, 'YYYY-MM-DD'), ''), COALESCE(preferred_time_slot, ''),
  visit_type, source_channel, requestor_name, requestor_phone, COALESCE(requestor_email, ''),
  address_line1, COALESCE(address_line2, ''), COALESCE(village_or_ward, ''), COALESCE(gram_panchayat, ''),
  COALESCE(block_or_taluk, ''), district, state, pincode, COALESCE(latitude, 0), COALESCE(longitude, 0),
  COALESCE(assigned_method, ''), COALESCE(assignment_score, 0), COALESCE(encounter_id::text, ''), notes::text,
  created_at, updated_at
FROM asha_appointments
WHERE appointment_id::text = $1
  AND ($2 = '' OR asha_user_id::text = $2)
LIMIT 1`, strings.TrimSpace(appointmentID), strings.TrimSpace(ashaUserID)).Scan(
		&out.AppointmentID,
		&out.PatientID,
		&out.ASHAUserID,
		&out.Status,
		&out.ReasonCode,
		&out.ReasonText,
		&out.PreferredDate,
		&out.PreferredTimeSlot,
		&out.VisitType,
		&out.SourceChannel,
		&out.RequestorName,
		&out.RequestorPhone,
		&out.RequestorEmail,
		&out.AddressLine1,
		&out.AddressLine2,
		&out.VillageOrWard,
		&out.GramPanchayat,
		&out.BlockOrTaluk,
		&out.District,
		&out.State,
		&out.Pincode,
		&out.Latitude,
		&out.Longitude,
		&out.AssignedMethod,
		&out.AssignmentScore,
		&out.EncounterID,
		&out.Notes,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	return out, err
}

func (r *PgxRepository) UpdateASHAAppointmentStatus(ctx context.Context, appointmentID, status, updatedBy string) error {
	_, err := r.pool.Exec(ctx, `
UPDATE asha_appointments
SET status = $2::asha_appointment_status,
    updated_at = NOW()
WHERE appointment_id::text = $1`, strings.TrimSpace(appointmentID), strings.TrimSpace(status))
	if err != nil {
		return err
	}
	return r.LogASHAAppointmentEvent(ctx, models.ASHAAppointmentEvent{
		AppointmentID: appointmentID,
		EventType:     strings.TrimSpace(status),
		EventPayload:  `{"source":"status_patch"}`,
		CreatedBy:     strings.TrimSpace(updatedBy),
	})
}

func (r *PgxRepository) CompleteASHAAppointment(ctx context.Context, appointmentID, encounterID, updatedBy string) error {
	_, err := r.pool.Exec(ctx, `
UPDATE asha_appointments
SET status = 'completed'::asha_appointment_status,
    encounter_id = COALESCE(NULLIF($2, '')::uuid, encounter_id),
    updated_at = NOW()
WHERE appointment_id::text = $1`, strings.TrimSpace(appointmentID), strings.TrimSpace(encounterID))
	if err != nil {
		return err
	}
	return r.LogASHAAppointmentEvent(ctx, models.ASHAAppointmentEvent{
		AppointmentID: appointmentID,
		EventType:     "completed",
		EventPayload:  fmt.Sprintf(`{"encounter_id":"%s"}`, strings.TrimSpace(encounterID)),
		CreatedBy:     strings.TrimSpace(updatedBy),
	})
}

func (r *PgxRepository) LogASHAAppointmentEvent(ctx context.Context, evt models.ASHAAppointmentEvent) error {
	_, err := r.pool.Exec(ctx, `
INSERT INTO asha_appointment_events (appointment_id, event_type, event_payload, created_by)
VALUES ($1::uuid, $2, COALESCE($3::jsonb, '{}'::jsonb), NULLIF($4, ''))`,
		strings.TrimSpace(evt.AppointmentID),
		strings.TrimSpace(evt.EventType),
		defaultJSON(evt.EventPayload, "{}"),
		strings.TrimSpace(evt.CreatedBy),
	)
	return err
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

func nullIfZeroInt(v int) any {
	if v <= 0 {
		return nil
	}
	return v
}

func nullIfZeroFloat(v float64) any {
	if v == 0 {
		return nil
	}
	return v
}

func nullableUUID(v *string) any {
	if v == nil {
		return nil
	}
	if strings.TrimSpace(*v) == "" {
		return nil
	}
	return *v
}

func patientVisibilityWhereClause() string {
	return `(
		p.created_by = $1
		OR p.updated_by = $1
		OR (
			COALESCE(p.created_by, '') = ''
			AND COALESCE(p.updated_by, '') = ''
		)
		OR (
			$2::uuid IS NOT NULL
			AND EXISTS (
				SELECT 1
				FROM patient_access pa
				WHERE pa.patient_id = p.patient_id
				  AND pa.user_id = $2::uuid
				  AND pa.revoked_at IS NULL
			)
		)
	)`
}

func patientSelectClause(tableAlias string) string {
	prefix := ""
	if strings.TrimSpace(tableAlias) != "" {
		prefix = strings.TrimSpace(tableAlias) + "."
	}
	return fmt.Sprintf(`%spatient_id::text,
		%sfhir_patient_id,
		COALESCE(%sabha_id, ''),
		COALESCE(%sabha_number, ''),
		COALESCE(%sabha_address, ''),
		COALESCE(%sfirst_name, ''),
		COALESCE(%smiddle_name, ''),
		COALESCE(%slast_name, ''),
		COALESCE(%sfull_name, ''),
		COALESCE(%sgender, ''),
		COALESCE(%sdate_of_birth::text, ''),
		COALESCE(%sage_years, 0),
		COALESCE(%sphone, ''),
		COALESCE(%sphone_number, ''),
		COALESCE(%sphone_e164, ''),
		COALESCE(%semail, ''),
		COALESCE(%saddress_line1, ''),
		COALESCE(%saddress_line2, ''),
		COALESCE(%svillage_or_ward, ''),
		COALESCE(%sgram_panchayat, ''),
		COALESCE(%sblock_or_taluk, ''),
		COALESCE(%sdistrict, ''),
		COALESCE(%sstate, ''),
		COALESCE(%spincode, ''),
		COALESCE(%slandmark, ''),
		COALESCE(%sconsent_flags::text, '{}'),
		COALESCE(%screated_by, ''),
		COALESCE(%supdated_by, ''),
		COALESCE(%sstatus, ''),
		COALESCE(%spreferred_language, ''),
		COALESCE(%sprimary_clinic_id::text, ''),
		COALESCE(%ssource_system, ''),
		%sread_only,
		COALESCE(%slast_synced_at, NOW()),
		%screated_at,
		%supdated_at`,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
		prefix,
	)
}

func patientScanTargets(p *models.Patient) []any {
	return []any{
		&p.PatientID,
		&p.FHIRPatientID,
		&p.ABHAID,
		&p.ABHANumber,
		&p.ABHAAddress,
		&p.FirstName,
		&p.MiddleName,
		&p.LastName,
		&p.FullName,
		&p.Gender,
		&p.DateOfBirth,
		&p.AgeYears,
		&p.Phone,
		&p.PhoneNumber,
		&p.PhoneE164,
		&p.Email,
		&p.AddressLine1,
		&p.AddressLine2,
		&p.VillageOrWard,
		&p.GramPanchayat,
		&p.BlockOrTaluk,
		&p.District,
		&p.State,
		&p.Pincode,
		&p.Landmark,
		&p.ConsentFlags,
		&p.CreatedBy,
		&p.UpdatedBy,
		&p.Status,
		&p.PreferredLanguage,
		&p.PrimaryClinicID,
		&p.SourceSystem,
		&p.ReadOnly,
		&p.LastSyncedAt,
		&p.CreatedAt,
		&p.UpdatedAt,
	}
}

var _ Repository = (*PgxRepository)(nil)
var _ = pgx.ErrNoRows
