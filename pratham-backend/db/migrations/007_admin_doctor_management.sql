-- Admin doctor management model.
-- Supports create/edit/list/view/status operations for clinic and ops admins.

CREATE TABLE IF NOT EXISTS doctors (
  doctor_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cognito_sub VARCHAR(255),
  first_name VARCHAR(100) NOT NULL,
  middle_name VARCHAR(100),
  last_name VARCHAR(100),
  full_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  phone_number VARCHAR(20) NOT NULL,
  gender VARCHAR(20),
  date_of_birth DATE,
  registration_number VARCHAR(64) NOT NULL,
  specialization VARCHAR(120) NOT NULL,
  qualifications TEXT,
  years_experience SMALLINT,
  languages_spoken JSONB NOT NULL DEFAULT '[]'::jsonb,
  clinic_name VARCHAR(255),
  address_line1 VARCHAR(255),
  address_line2 VARCHAR(255),
  city VARCHAR(120),
  district VARCHAR(120),
  state VARCHAR(120),
  pincode VARCHAR(6),
  consultation_mode JSONB NOT NULL DEFAULT '{"in_person": true, "telemedicine": true}'::jsonb,
  availability_summary JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by VARCHAR(255),
  updated_by VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_doctors_gender
    CHECK (gender IS NULL OR lower(gender) IN ('male', 'female', 'other', 'unknown')),
  CONSTRAINT chk_doctors_pincode
    CHECK (pincode IS NULL OR pincode ~ '^[0-9]{6}$'),
  CONSTRAINT chk_doctors_years_experience
    CHECK (years_experience IS NULL OR (years_experience >= 0 AND years_experience <= 80))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_doctors_email
  ON doctors (LOWER(email));

CREATE UNIQUE INDEX IF NOT EXISTS uq_doctors_phone_number
  ON doctors (phone_number);

CREATE UNIQUE INDEX IF NOT EXISTS uq_doctors_registration_number
  ON doctors (LOWER(registration_number));

CREATE UNIQUE INDEX IF NOT EXISTS uq_doctors_cognito_sub
  ON doctors (cognito_sub)
  WHERE cognito_sub IS NOT NULL AND cognito_sub <> '';

CREATE INDEX IF NOT EXISTS idx_doctors_name
  ON doctors (LOWER(full_name));

CREATE INDEX IF NOT EXISTS idx_doctors_specialization
  ON doctors (LOWER(specialization));

CREATE INDEX IF NOT EXISTS idx_doctors_is_active
  ON doctors (is_active);
