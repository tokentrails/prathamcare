package models

import "time"

type UserRole string

const (
	UserRoleDoctor     UserRole = "doctor"
	UserRoleASHAWorker UserRole = "asha_worker"
	UserRoleClinicAdmin UserRole = "clinic_admin"
	UserRoleOpsAdmin    UserRole = "ops_admin"
)

type User struct {
	UserID             string    `json:"user_id"`
	CognitoSub         string    `json:"cognito_sub"`
	Role               UserRole  `json:"role"`
	FullName           string    `json:"full_name"`
	Phone              string    `json:"phone"`
	Email              string    `json:"email,omitempty"`
	PreferredLanguage  string    `json:"preferred_language"`
	IsActive           bool      `json:"is_active"`
	LastLoginAt        time.Time `json:"last_login_at,omitempty"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

type Clinic struct {
	ClinicID    string    `json:"clinic_id"`
	ClinicCode  string    `json:"clinic_code"`
	Name        string    `json:"name"`
	Type        string    `json:"type"`
	ABDMHFRID   string    `json:"abdm_hfr_id,omitempty"`
	Phone       string    `json:"phone,omitempty"`
	Email       string    `json:"email,omitempty"`
	City        string    `json:"city,omitempty"`
	State       string    `json:"state,omitempty"`
	Pincode     string    `json:"pincode,omitempty"`
	CountryCode string    `json:"country_code"`
	IsActive    bool      `json:"is_active"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type DoctorProfile struct {
	UserID                 string    `json:"user_id"`
	RegistrationNumber     string    `json:"registration_number"`
	SpecialtyCode          string    `json:"specialty_code"`
	SpecialtyName          string    `json:"specialty_name"`
	YearsExperience        int16     `json:"years_experience,omitempty"`
	ConsultationLanguages  []string  `json:"consultation_languages,omitempty"`
	TelemedicineEnabled    bool      `json:"telemedicine_enabled"`
	CreatedAt              time.Time `json:"created_at"`
	UpdatedAt              time.Time `json:"updated_at"`
}

type Doctor struct {
	DoctorID            string    `json:"doctor_id"`
	CognitoSub          string    `json:"cognito_sub,omitempty"`
	FirstName           string    `json:"first_name"`
	MiddleName          string    `json:"middle_name,omitempty"`
	LastName            string    `json:"last_name,omitempty"`
	FullName            string    `json:"full_name"`
	Email               string    `json:"email"`
	PhoneNumber         string    `json:"phone_number"`
	Gender              string    `json:"gender,omitempty"`
	DateOfBirth         string    `json:"date_of_birth,omitempty"`
	RegistrationNumber  string    `json:"registration_number"`
	Specialization      string    `json:"specialization"`
	Qualifications      string    `json:"qualifications,omitempty"`
	YearsExperience     int       `json:"years_experience,omitempty"`
	LanguagesSpoken     []string  `json:"languages_spoken,omitempty"`
	ClinicName          string    `json:"clinic_name,omitempty"`
	AddressLine1        string    `json:"address_line1,omitempty"`
	AddressLine2        string    `json:"address_line2,omitempty"`
	City                string    `json:"city,omitempty"`
	District            string    `json:"district,omitempty"`
	State               string    `json:"state,omitempty"`
	Pincode             string    `json:"pincode,omitempty"`
	ConsultationInPerson bool     `json:"consultation_in_person"`
	ConsultationTelemedicine bool `json:"consultation_telemedicine"`
	AvailabilitySummary string    `json:"availability_summary,omitempty"`
	IsActive            bool      `json:"is_active"`
	CreatedBy           string    `json:"created_by,omitempty"`
	UpdatedBy           string    `json:"updated_by,omitempty"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
}

type DoctorListFilter struct {
	Query          string `json:"query,omitempty"`
	Specialization string `json:"specialization,omitempty"`
	Active         *bool  `json:"active,omitempty"`
	Limit          int    `json:"limit,omitempty"`
	Offset         int    `json:"offset,omitempty"`
}

type ASHAProfile struct {
	UserID            string    `json:"user_id"`
	ASHACode          string    `json:"asha_code,omitempty"`
	SupervisorName    string    `json:"supervisor_name,omitempty"`
	AssignedVillage   string    `json:"assigned_village,omitempty"`
	AssignedBlock     string    `json:"assigned_block,omitempty"`
	AssignedDistrict  string    `json:"assigned_district,omitempty"`
	State             string    `json:"state,omitempty"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
}

type Patient struct {
	PatientID          string    `json:"patient_id"`
	FHIRPatientID      string    `json:"fhir_patient_id"`
	ABHAID             string    `json:"abha_id,omitempty"`
	ABHANumber         string    `json:"abha_number,omitempty"`
	ABHAAddress        string    `json:"abha_address,omitempty"`
	FirstName          string    `json:"first_name,omitempty"`
	MiddleName         string    `json:"middle_name,omitempty"`
	LastName           string    `json:"last_name,omitempty"`
	FullName           string    `json:"full_name"`
	Gender             string    `json:"gender,omitempty"`
	DateOfBirth        string    `json:"date_of_birth,omitempty"`
	AgeYears           int       `json:"age_years,omitempty"`
	Phone              string    `json:"phone,omitempty"`
	PhoneNumber        string    `json:"phone_number,omitempty"`
	PhoneE164          string    `json:"phone_e164,omitempty"`
	Email              string    `json:"email,omitempty"`
	AddressLine1       string    `json:"address_line1,omitempty"`
	AddressLine2       string    `json:"address_line2,omitempty"`
	VillageOrWard      string    `json:"village_or_ward,omitempty"`
	GramPanchayat      string    `json:"gram_panchayat,omitempty"`
	BlockOrTaluk       string    `json:"block_or_taluk,omitempty"`
	District           string    `json:"district,omitempty"`
	State              string    `json:"state,omitempty"`
	Pincode            string    `json:"pincode,omitempty"`
	Landmark           string    `json:"landmark,omitempty"`
	ConsentFlags       string    `json:"consent_flags,omitempty"`
	CreatedBy          string    `json:"created_by,omitempty"`
	UpdatedBy          string    `json:"updated_by,omitempty"`
	Status             string    `json:"status,omitempty"`
	PreferredLanguage  string    `json:"preferred_language,omitempty"`
	PrimaryClinicID    string    `json:"primary_clinic_id,omitempty"`
	SourceSystem       string    `json:"source_system"`
	ReadOnly           bool      `json:"read_only"`
	LastSyncedAt       time.Time `json:"last_synced_at,omitempty"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

type PatientSearchFilter struct {
	Query      string `json:"query,omitempty"`
	PhoneE164  string `json:"phone_e164,omitempty"`
	ABHANumber string `json:"abha_number,omitempty"`
	PatientRef string `json:"patient_ref,omitempty"`
	Limit      int    `json:"limit,omitempty"`
}

type Appointment struct {
	AppointmentID         string    `json:"appointment_id"`
	PatientID             string    `json:"patient_id"`
	PhysicianID           string    `json:"physician_id"`
	ClinicID              string    `json:"clinic_id"`
	AppointmentType       string    `json:"appointment_type"`
	BookingChannel        string    `json:"booking_channel"`
	Status                string    `json:"status"`
	ScheduledStartAt      time.Time `json:"scheduled_start_at"`
	ScheduledEndAt        time.Time `json:"scheduled_end_at"`
	PreliminaryDiagnosis  string    `json:"preliminary_diagnosis,omitempty"`
	FHIRAppointmentID     string    `json:"fhir_appointment_id,omitempty"`
	FHIREncounterID       string    `json:"fhir_encounter_id,omitempty"`
	CreatedBy             string    `json:"created_by"`
	CreatedAt             time.Time `json:"created_at"`
	UpdatedAt             time.Time `json:"updated_at"`
}

type PatientRemark struct {
	RemarkID           string    `json:"remark_id"`
	PatientID          string    `json:"patient_id"`
	AddedByUserID      string    `json:"added_by_user_id"`
	RemarkTextOriginal string    `json:"remark_text_original"`
	OriginalLanguage   string    `json:"original_language"`
	RemarkTextEnglish  string    `json:"remark_text_english,omitempty"`
	RemarkTypes        []string  `json:"remark_types,omitempty"`
	Importance         string    `json:"importance,omitempty"`
	VoiceRecordingURL  string    `json:"voice_recording_url,omitempty"`
	Visibility         string    `json:"visibility"`
	CreatedAt          time.Time `json:"created_at"`
}
