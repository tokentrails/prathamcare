-- PrathamCare initial core models
-- Target: Amazon Aurora PostgreSQL

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TYPE user_role AS ENUM (
  'doctor',
  'asha_worker',
  'clinic_admin',
  'ops_admin'
);

CREATE TYPE membership_status AS ENUM (
  'active',
  'inactive',
  'invited'
);

CREATE TYPE patient_access_role AS ENUM (
  'primary_doctor',
  'treating_doctor',
  'asha_worker',
  'clinic_staff'
);

CREATE TABLE clinics (
  clinic_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_code VARCHAR(64) UNIQUE,
  name VARCHAR(255) NOT NULL,
  type VARCHAR(50) NOT NULL DEFAULT 'phc', -- phc/chc/hospital/private_clinic
  abdm_hfr_id VARCHAR(128),
  phone VARCHAR(20),
  email VARCHAR(255),
  address_line1 VARCHAR(255),
  address_line2 VARCHAR(255),
  city VARCHAR(100),
  state VARCHAR(100),
  pincode VARCHAR(12),
  country_code CHAR(2) NOT NULL DEFAULT 'IN',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Workforce users only (doctor/ASHA/clinic admins)
CREATE TABLE users (
  user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cognito_sub VARCHAR(255) UNIQUE NOT NULL,
  role user_role NOT NULL,
  full_name VARCHAR(255) NOT NULL,
  phone VARCHAR(20) UNIQUE NOT NULL,
  email VARCHAR(255),
  preferred_language VARCHAR(10) NOT NULL DEFAULT 'hi',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Users can belong to one or more clinics
CREATE TABLE clinic_memberships (
  clinic_membership_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  clinic_id UUID NOT NULL REFERENCES clinics(clinic_id),
  user_id UUID NOT NULL REFERENCES users(user_id),
  status membership_status NOT NULL DEFAULT 'active',
  started_at DATE NOT NULL DEFAULT CURRENT_DATE,
  ended_at DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (clinic_id, user_id)
);

CREATE TABLE doctor_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(user_id),
  registration_number VARCHAR(64) UNIQUE NOT NULL,
  specialty_code VARCHAR(64) NOT NULL,
  specialty_name VARCHAR(255) NOT NULL,
  years_experience SMALLINT,
  consultation_languages TEXT[] DEFAULT '{}',
  telemedicine_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE asha_profiles (
  user_id UUID PRIMARY KEY REFERENCES users(user_id),
  asha_code VARCHAR(64) UNIQUE,
  supervisor_name VARCHAR(255),
  assigned_village VARCHAR(255),
  assigned_block VARCHAR(255),
  assigned_district VARCHAR(255),
  state VARCHAR(100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Patient records are read-only in app; source of truth is HealthLake/FHIR.
CREATE TABLE patients (
  patient_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fhir_patient_id VARCHAR(255) UNIQUE NOT NULL,
  abha_id VARCHAR(32),
  full_name VARCHAR(255) NOT NULL,
  gender VARCHAR(20),
  date_of_birth DATE,
  phone VARCHAR(20),
  preferred_language VARCHAR(10) DEFAULT 'hi',
  primary_clinic_id UUID REFERENCES clinics(clinic_id),
  source_system VARCHAR(50) NOT NULL DEFAULT 'healthlake',
  read_only BOOLEAN NOT NULL DEFAULT TRUE,
  last_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Which workforce users can access which patients.
CREATE TABLE patient_access (
  patient_access_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  user_id UUID NOT NULL REFERENCES users(user_id),
  access_role patient_access_role NOT NULL,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (patient_id, user_id, access_role)
);

CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_clinic_memberships_user ON clinic_memberships(user_id);
CREATE INDEX idx_clinic_memberships_clinic ON clinic_memberships(clinic_id);
CREATE INDEX idx_patients_fhir_patient_id ON patients(fhir_patient_id);
CREATE INDEX idx_patients_primary_clinic ON patients(primary_clinic_id);
CREATE INDEX idx_patient_access_patient ON patient_access(patient_id);
CREATE INDEX idx_patient_access_user ON patient_access(user_id);
