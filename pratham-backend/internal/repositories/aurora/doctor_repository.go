package aurora

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/prathamcare/backend/internal/models"
)

func (r *PgxRepository) CreateDoctor(ctx context.Context, doctor models.Doctor) (models.Doctor, error) {
	q := `
INSERT INTO doctors (
	cognito_sub, first_name, middle_name, last_name, full_name, email, phone_number, gender, date_of_birth,
	registration_number, specialization, qualifications, years_experience, languages_spoken,
	clinic_name, address_line1, address_line2, city, district, state, pincode, consultation_mode,
	availability_summary, is_active, created_by, updated_by
) VALUES (
	$1,$2,$3,$4,$5,$6,$7,$8,$9,
	$10,$11,$12,$13,$14,
	$15,$16,$17,$18,$19,$20,$21,$22,
	$23,$24,$25,$26
)
RETURNING doctor_id, COALESCE(cognito_sub, ''), first_name, COALESCE(middle_name, ''), COALESCE(last_name, ''), full_name,
	email, phone_number, COALESCE(gender, ''), COALESCE(date_of_birth::text, ''), registration_number, specialization,
	COALESCE(qualifications, ''), COALESCE(years_experience, 0), COALESCE(languages_spoken, '[]'::jsonb),
	COALESCE(clinic_name, ''), COALESCE(address_line1, ''), COALESCE(address_line2, ''), COALESCE(city, ''),
	COALESCE(district, ''), COALESCE(state, ''), COALESCE(pincode, ''), COALESCE(consultation_mode, '{}'::jsonb),
	COALESCE(availability_summary, '{}'::jsonb), is_active, COALESCE(created_by, ''), COALESCE(updated_by, ''),
	created_at, updated_at`

	var out models.Doctor
	var languagesJSON []byte
	var consultationJSON []byte
	var availabilityJSON []byte
	err := r.pool.QueryRow(ctx, q,
		nullIfEmpty(doctor.CognitoSub),
		doctor.FirstName,
		nullIfEmpty(doctor.MiddleName),
		nullIfEmpty(doctor.LastName),
		doctor.FullName,
		doctor.Email,
		doctor.PhoneNumber,
		nullIfEmpty(doctor.Gender),
		nullIfEmpty(doctor.DateOfBirth),
		doctor.RegistrationNumber,
		doctor.Specialization,
		nullIfEmpty(doctor.Qualifications),
		nullIfZeroInt(doctor.YearsExperience),
		toJSONString(doctor.LanguagesSpoken, "[]"),
		nullIfEmpty(doctor.ClinicName),
		nullIfEmpty(doctor.AddressLine1),
		nullIfEmpty(doctor.AddressLine2),
		nullIfEmpty(doctor.City),
		nullIfEmpty(doctor.District),
		nullIfEmpty(doctor.State),
		nullIfEmpty(doctor.Pincode),
		toJSONString(map[string]bool{
			"in_person":    doctor.ConsultationInPerson,
			"telemedicine": doctor.ConsultationTelemedicine,
		}, "{}"),
		defaultJSON(doctor.AvailabilitySummary, "{}"),
		doctor.IsActive,
		nullIfEmpty(doctor.CreatedBy),
		nullIfEmpty(doctor.UpdatedBy),
	).Scan(
		&out.DoctorID,
		&out.CognitoSub,
		&out.FirstName,
		&out.MiddleName,
		&out.LastName,
		&out.FullName,
		&out.Email,
		&out.PhoneNumber,
		&out.Gender,
		&out.DateOfBirth,
		&out.RegistrationNumber,
		&out.Specialization,
		&out.Qualifications,
		&out.YearsExperience,
		&languagesJSON,
		&out.ClinicName,
		&out.AddressLine1,
		&out.AddressLine2,
		&out.City,
		&out.District,
		&out.State,
		&out.Pincode,
		&consultationJSON,
		&availabilityJSON,
		&out.IsActive,
		&out.CreatedBy,
		&out.UpdatedBy,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	if err != nil {
		return models.Doctor{}, err
	}
	applyDoctorJSONFields(&out, languagesJSON, consultationJSON, availabilityJSON)
	return out, nil
}

func (r *PgxRepository) ListDoctors(ctx context.Context, filter models.DoctorListFilter) ([]models.Doctor, error) {
	if filter.Limit <= 0 || filter.Limit > 200 {
		filter.Limit = 25
	}
	if filter.Offset < 0 {
		filter.Offset = 0
	}
	q := `
SELECT doctor_id, COALESCE(cognito_sub, ''), first_name, COALESCE(middle_name, ''), COALESCE(last_name, ''), full_name,
	email, phone_number, COALESCE(gender, ''), COALESCE(date_of_birth::text, ''), registration_number, specialization,
	COALESCE(qualifications, ''), COALESCE(years_experience, 0), COALESCE(languages_spoken, '[]'::jsonb),
	COALESCE(clinic_name, ''), COALESCE(address_line1, ''), COALESCE(address_line2, ''), COALESCE(city, ''),
	COALESCE(district, ''), COALESCE(state, ''), COALESCE(pincode, ''), COALESCE(consultation_mode, '{}'::jsonb),
	COALESCE(availability_summary, '{}'::jsonb), is_active, COALESCE(created_by, ''), COALESCE(updated_by, ''),
	created_at, updated_at
FROM doctors
WHERE ($1 = '' OR (
	full_name ILIKE '%' || $1 || '%'
	OR email ILIKE '%' || $1 || '%'
	OR phone_number ILIKE '%' || $1 || '%'
	OR registration_number ILIKE '%' || $1 || '%'
))
  AND ($2 = '' OR specialization ILIKE '%' || $2 || '%')
  AND ($3::boolean IS NULL OR is_active = $3::boolean)
ORDER BY updated_at DESC
LIMIT $4 OFFSET $5`

	rows, err := r.pool.Query(ctx, q,
		strings.TrimSpace(filter.Query),
		strings.TrimSpace(filter.Specialization),
		filter.Active,
		filter.Limit,
		filter.Offset,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]models.Doctor, 0, filter.Limit)
	for rows.Next() {
		var item models.Doctor
		var languagesJSON []byte
		var consultationJSON []byte
		var availabilityJSON []byte
		if err := rows.Scan(
			&item.DoctorID,
			&item.CognitoSub,
			&item.FirstName,
			&item.MiddleName,
			&item.LastName,
			&item.FullName,
			&item.Email,
			&item.PhoneNumber,
			&item.Gender,
			&item.DateOfBirth,
			&item.RegistrationNumber,
			&item.Specialization,
			&item.Qualifications,
			&item.YearsExperience,
			&languagesJSON,
			&item.ClinicName,
			&item.AddressLine1,
			&item.AddressLine2,
			&item.City,
			&item.District,
			&item.State,
			&item.Pincode,
			&consultationJSON,
			&availabilityJSON,
			&item.IsActive,
			&item.CreatedBy,
			&item.UpdatedBy,
			&item.CreatedAt,
			&item.UpdatedAt,
		); err != nil {
			return nil, err
		}
		applyDoctorJSONFields(&item, languagesJSON, consultationJSON, availabilityJSON)
		out = append(out, item)
	}
	return out, rows.Err()
}

func (r *PgxRepository) GetDoctorByID(ctx context.Context, doctorID string) (models.Doctor, error) {
	q := `
SELECT doctor_id, COALESCE(cognito_sub, ''), first_name, COALESCE(middle_name, ''), COALESCE(last_name, ''), full_name,
	email, phone_number, COALESCE(gender, ''), COALESCE(date_of_birth::text, ''), registration_number, specialization,
	COALESCE(qualifications, ''), COALESCE(years_experience, 0), COALESCE(languages_spoken, '[]'::jsonb),
	COALESCE(clinic_name, ''), COALESCE(address_line1, ''), COALESCE(address_line2, ''), COALESCE(city, ''),
	COALESCE(district, ''), COALESCE(state, ''), COALESCE(pincode, ''), COALESCE(consultation_mode, '{}'::jsonb),
	COALESCE(availability_summary, '{}'::jsonb), is_active, COALESCE(created_by, ''), COALESCE(updated_by, ''),
	created_at, updated_at
FROM doctors
WHERE doctor_id = $1`
	var out models.Doctor
	var languagesJSON []byte
	var consultationJSON []byte
	var availabilityJSON []byte
	err := r.pool.QueryRow(ctx, q, doctorID).Scan(
		&out.DoctorID,
		&out.CognitoSub,
		&out.FirstName,
		&out.MiddleName,
		&out.LastName,
		&out.FullName,
		&out.Email,
		&out.PhoneNumber,
		&out.Gender,
		&out.DateOfBirth,
		&out.RegistrationNumber,
		&out.Specialization,
		&out.Qualifications,
		&out.YearsExperience,
		&languagesJSON,
		&out.ClinicName,
		&out.AddressLine1,
		&out.AddressLine2,
		&out.City,
		&out.District,
		&out.State,
		&out.Pincode,
		&consultationJSON,
		&availabilityJSON,
		&out.IsActive,
		&out.CreatedBy,
		&out.UpdatedBy,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	if err != nil {
		return models.Doctor{}, err
	}
	applyDoctorJSONFields(&out, languagesJSON, consultationJSON, availabilityJSON)
	return out, nil
}

func (r *PgxRepository) UpdateDoctor(ctx context.Context, doctor models.Doctor) (models.Doctor, error) {
	q := `
UPDATE doctors
SET cognito_sub = $2,
	first_name = $3,
	middle_name = $4,
	last_name = $5,
	full_name = $6,
	email = $7,
	phone_number = $8,
	gender = $9,
	date_of_birth = $10,
	registration_number = $11,
	specialization = $12,
	qualifications = $13,
	years_experience = $14,
	languages_spoken = $15,
	clinic_name = $16,
	address_line1 = $17,
	address_line2 = $18,
	city = $19,
	district = $20,
	state = $21,
	pincode = $22,
	consultation_mode = $23,
	availability_summary = $24,
	is_active = $25,
	updated_by = $26,
	updated_at = NOW()
WHERE doctor_id = $1
RETURNING doctor_id, COALESCE(cognito_sub, ''), first_name, COALESCE(middle_name, ''), COALESCE(last_name, ''), full_name,
	email, phone_number, COALESCE(gender, ''), COALESCE(date_of_birth::text, ''), registration_number, specialization,
	COALESCE(qualifications, ''), COALESCE(years_experience, 0), COALESCE(languages_spoken, '[]'::jsonb),
	COALESCE(clinic_name, ''), COALESCE(address_line1, ''), COALESCE(address_line2, ''), COALESCE(city, ''),
	COALESCE(district, ''), COALESCE(state, ''), COALESCE(pincode, ''), COALESCE(consultation_mode, '{}'::jsonb),
	COALESCE(availability_summary, '{}'::jsonb), is_active, COALESCE(created_by, ''), COALESCE(updated_by, ''),
	created_at, updated_at`

	var out models.Doctor
	var languagesJSON []byte
	var consultationJSON []byte
	var availabilityJSON []byte
	err := r.pool.QueryRow(ctx, q,
		doctor.DoctorID,
		nullIfEmpty(doctor.CognitoSub),
		doctor.FirstName,
		nullIfEmpty(doctor.MiddleName),
		nullIfEmpty(doctor.LastName),
		doctor.FullName,
		doctor.Email,
		doctor.PhoneNumber,
		nullIfEmpty(doctor.Gender),
		nullIfEmpty(doctor.DateOfBirth),
		doctor.RegistrationNumber,
		doctor.Specialization,
		nullIfEmpty(doctor.Qualifications),
		nullIfZeroInt(doctor.YearsExperience),
		toJSONString(doctor.LanguagesSpoken, "[]"),
		nullIfEmpty(doctor.ClinicName),
		nullIfEmpty(doctor.AddressLine1),
		nullIfEmpty(doctor.AddressLine2),
		nullIfEmpty(doctor.City),
		nullIfEmpty(doctor.District),
		nullIfEmpty(doctor.State),
		nullIfEmpty(doctor.Pincode),
		toJSONString(map[string]bool{
			"in_person":    doctor.ConsultationInPerson,
			"telemedicine": doctor.ConsultationTelemedicine,
		}, "{}"),
		defaultJSON(doctor.AvailabilitySummary, "{}"),
		doctor.IsActive,
		nullIfEmpty(doctor.UpdatedBy),
	).Scan(
		&out.DoctorID,
		&out.CognitoSub,
		&out.FirstName,
		&out.MiddleName,
		&out.LastName,
		&out.FullName,
		&out.Email,
		&out.PhoneNumber,
		&out.Gender,
		&out.DateOfBirth,
		&out.RegistrationNumber,
		&out.Specialization,
		&out.Qualifications,
		&out.YearsExperience,
		&languagesJSON,
		&out.ClinicName,
		&out.AddressLine1,
		&out.AddressLine2,
		&out.City,
		&out.District,
		&out.State,
		&out.Pincode,
		&consultationJSON,
		&availabilityJSON,
		&out.IsActive,
		&out.CreatedBy,
		&out.UpdatedBy,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	if err != nil {
		return models.Doctor{}, err
	}
	applyDoctorJSONFields(&out, languagesJSON, consultationJSON, availabilityJSON)
	return out, nil
}

func (r *PgxRepository) UpdateDoctorStatus(ctx context.Context, doctorID string, isActive bool, updatedBy string) (models.Doctor, error) {
	q := `
UPDATE doctors
SET is_active = $2,
	updated_by = $3,
	updated_at = NOW()
WHERE doctor_id = $1
RETURNING doctor_id, COALESCE(cognito_sub, ''), first_name, COALESCE(middle_name, ''), COALESCE(last_name, ''), full_name,
	email, phone_number, COALESCE(gender, ''), COALESCE(date_of_birth::text, ''), registration_number, specialization,
	COALESCE(qualifications, ''), COALESCE(years_experience, 0), COALESCE(languages_spoken, '[]'::jsonb),
	COALESCE(clinic_name, ''), COALESCE(address_line1, ''), COALESCE(address_line2, ''), COALESCE(city, ''),
	COALESCE(district, ''), COALESCE(state, ''), COALESCE(pincode, ''), COALESCE(consultation_mode, '{}'::jsonb),
	COALESCE(availability_summary, '{}'::jsonb), is_active, COALESCE(created_by, ''), COALESCE(updated_by, ''),
	created_at, updated_at`
	var out models.Doctor
	var languagesJSON []byte
	var consultationJSON []byte
	var availabilityJSON []byte
	err := r.pool.QueryRow(ctx, q, doctorID, isActive, nullIfEmpty(updatedBy)).Scan(
		&out.DoctorID,
		&out.CognitoSub,
		&out.FirstName,
		&out.MiddleName,
		&out.LastName,
		&out.FullName,
		&out.Email,
		&out.PhoneNumber,
		&out.Gender,
		&out.DateOfBirth,
		&out.RegistrationNumber,
		&out.Specialization,
		&out.Qualifications,
		&out.YearsExperience,
		&languagesJSON,
		&out.ClinicName,
		&out.AddressLine1,
		&out.AddressLine2,
		&out.City,
		&out.District,
		&out.State,
		&out.Pincode,
		&consultationJSON,
		&availabilityJSON,
		&out.IsActive,
		&out.CreatedBy,
		&out.UpdatedBy,
		&out.CreatedAt,
		&out.UpdatedAt,
	)
	if err != nil {
		return models.Doctor{}, err
	}
	applyDoctorJSONFields(&out, languagesJSON, consultationJSON, availabilityJSON)
	return out, nil
}

func applyDoctorJSONFields(doctor *models.Doctor, languagesJSON, consultationJSON, availabilityJSON []byte) {
	if doctor == nil {
		return
	}
	if len(languagesJSON) > 0 {
		_ = json.Unmarshal(languagesJSON, &doctor.LanguagesSpoken)
	}
	mode := map[string]bool{}
	if len(consultationJSON) > 0 {
		_ = json.Unmarshal(consultationJSON, &mode)
	}
	doctor.ConsultationInPerson = mode["in_person"]
	doctor.ConsultationTelemedicine = mode["telemedicine"]
	if len(availabilityJSON) > 0 {
		doctor.AvailabilitySummary = strings.TrimSpace(string(availabilityJSON))
	}
}

func toJSONString(v any, fallback string) string {
	b, err := json.Marshal(v)
	if err != nil {
		return fallback
	}
	return string(b)
}
