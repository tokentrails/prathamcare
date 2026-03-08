-- ASHA public intake + appointment workflow

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'asha_appointment_status') THEN
    CREATE TYPE asha_appointment_status AS ENUM (
      'requested',
      'assigned',
      'accepted',
      'in_progress',
      'completed',
      'cancelled',
      'unassigned'
    );
  END IF;
END $$;

ALTER TABLE IF EXISTS asha_profiles
  ADD COLUMN IF NOT EXISTS service_pincode VARCHAR(6),
  ADD COLUMN IF NOT EXISTS service_latitude NUMERIC(10,7),
  ADD COLUMN IF NOT EXISTS service_longitude NUMERIC(10,7),
  ADD COLUMN IF NOT EXISTS service_radius_km NUMERIC(5,2) NOT NULL DEFAULT 10;

CREATE TABLE IF NOT EXISTS asha_appointments (
  appointment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  asha_user_id UUID REFERENCES users(user_id),
  status asha_appointment_status NOT NULL DEFAULT 'requested',
  reason_code VARCHAR(64) NOT NULL,
  reason_text TEXT,
  preferred_date DATE,
  preferred_time_slot VARCHAR(32),
  visit_type VARCHAR(32) NOT NULL DEFAULT 'home_visit',
  source_channel VARCHAR(32) NOT NULL DEFAULT 'public_web',
  requestor_name VARCHAR(255) NOT NULL,
  requestor_phone VARCHAR(20) NOT NULL,
  requestor_email VARCHAR(255),
  address_line1 VARCHAR(255) NOT NULL,
  address_line2 VARCHAR(255),
  village_or_ward VARCHAR(120),
  gram_panchayat VARCHAR(120),
  block_or_taluk VARCHAR(120),
  district VARCHAR(120) NOT NULL,
  state VARCHAR(120) NOT NULL,
  pincode VARCHAR(6) NOT NULL,
  latitude NUMERIC(10,7),
  longitude NUMERIC(10,7),
  assigned_method VARCHAR(32),
  assignment_score NUMERIC(5,2),
  encounter_id UUID REFERENCES encounters(encounter_id),
  notes JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_asha_appointments_pincode CHECK (pincode ~ '^[0-9]{6}$'),
  CONSTRAINT chk_asha_appointments_time_slot CHECK (
    preferred_time_slot IS NULL OR lower(preferred_time_slot) IN ('morning', 'afternoon', 'evening')
  )
);

CREATE TABLE IF NOT EXISTS asha_appointment_events (
  event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id UUID NOT NULL REFERENCES asha_appointments(appointment_id) ON DELETE CASCADE,
  event_type VARCHAR(64) NOT NULL,
  event_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE IF EXISTS encounters
  ADD COLUMN IF NOT EXISTS appointment_id UUID;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'encounters'
      AND column_name = 'appointment_id'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'fk_encounters_appointment_id'
    ) THEN
      ALTER TABLE encounters
        ADD CONSTRAINT fk_encounters_appointment_id
        FOREIGN KEY (appointment_id)
        REFERENCES asha_appointments(appointment_id);
    END IF;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_asha_profiles_location
  ON asha_profiles (LOWER(assigned_district), LOWER(state), LOWER(assigned_block), LOWER(assigned_village));

CREATE INDEX IF NOT EXISTS idx_asha_profiles_service_pincode
  ON asha_profiles (service_pincode)
  WHERE service_pincode IS NOT NULL AND service_pincode <> '';

CREATE INDEX IF NOT EXISTS idx_asha_appointments_asha_status_date
  ON asha_appointments (asha_user_id, status, preferred_date, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_asha_appointments_status_created
  ON asha_appointments (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_asha_appointments_location
  ON asha_appointments (LOWER(district), LOWER(state), pincode);

CREATE INDEX IF NOT EXISTS idx_asha_appointments_phone_created
  ON asha_appointments (requestor_phone, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_asha_appointments_patient_created
  ON asha_appointments (patient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_asha_appointment_events_appointment_created
  ON asha_appointment_events (appointment_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_encounters_appointment_id
  ON encounters (appointment_id)
  WHERE appointment_id IS NOT NULL;
