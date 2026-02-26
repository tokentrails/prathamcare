-- Workflow and feature models for PrathamCare MVP.

CREATE TYPE appointment_status AS ENUM (
  'requested',
  'booked',
  'checked_in',
  'completed',
  'cancelled',
  'no_show'
);

CREATE TYPE booking_channel AS ENUM (
  'call',
  'app',
  'asha',
  'clinic_desk'
);

CREATE TYPE remark_visibility AS ENUM (
  'all_providers',
  'clinic_only',
  'specific_provider'
);

CREATE TABLE appointments (
  appointment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  physician_id UUID NOT NULL REFERENCES users(user_id),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  appointment_type VARCHAR(50) NOT NULL, -- teleconsult, in_person, home_visit
  booking_channel booking_channel NOT NULL,
  status appointment_status NOT NULL DEFAULT 'booked',
  scheduled_start_at TIMESTAMPTZ NOT NULL,
  scheduled_end_at TIMESTAMPTZ NOT NULL,
  preliminary_diagnosis TEXT,
  fhir_appointment_id VARCHAR(255),
  fhir_encounter_id VARCHAR(255),
  created_by UUID REFERENCES users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE appointment_events (
  appointment_event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id UUID NOT NULL REFERENCES appointments(appointment_id),
  event_type VARCHAR(50) NOT NULL, -- booked/rescheduled/cancelled/started/completed
  event_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID REFERENCES users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE patient_remarks (
  remark_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  added_by_user_id UUID REFERENCES users(user_id),
  remark_text_original TEXT NOT NULL,
  original_language VARCHAR(10) NOT NULL DEFAULT 'hi',
  remark_text_english TEXT,
  remark_types TEXT[] NOT NULL DEFAULT '{}', -- symptom, allergy, family_history, lifestyle, travel
  importance VARCHAR(20), -- low, medium, high
  voice_recording_url VARCHAR(500),
  visibility remark_visibility NOT NULL DEFAULT 'all_providers',
  fhir_allergy_resource_id VARCHAR(255),
  fhir_family_history_resource_id VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE triage_assessments (
  triage_assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID REFERENCES patients(patient_id),
  intake_source VARCHAR(20) NOT NULL, -- call, app, asha
  symptoms TEXT[] NOT NULL DEFAULT '{}',
  language_code VARCHAR(10) NOT NULL,
  severity VARCHAR(20) NOT NULL, -- low, medium, high, critical
  preliminary_diagnosis TEXT,
  recommended_specialty VARCHAR(100),
  bedrock_model_id VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE daily_clinical_metrics (
  metric_date DATE NOT NULL,
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  total_appointments INTEGER NOT NULL DEFAULT 0,
  completed_appointments INTEGER NOT NULL DEFAULT 0,
  no_show_appointments INTEGER NOT NULL DEFAULT 0,
  high_risk_triage_count INTEGER NOT NULL DEFAULT 0,
  avg_consultation_minutes NUMERIC(8,2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (metric_date, clinic_id)
);

CREATE INDEX idx_appointments_physician_time ON appointments(physician_id, scheduled_start_at);
CREATE INDEX idx_appointments_patient_time ON appointments(patient_id, scheduled_start_at);
CREATE INDEX idx_appointments_clinic_time ON appointments(clinic_id, scheduled_start_at);
CREATE INDEX idx_patient_remarks_patient_time ON patient_remarks(patient_id, created_at DESC);
CREATE INDEX idx_triage_assessments_patient_time ON triage_assessments(patient_id, created_at DESC);
