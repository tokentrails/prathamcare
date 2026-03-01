-- Phase 1 Voice Visit schema additions
-- Adds encounter persistence for ASHA voice workflow, AI job tracking, and alert records.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'encounter_sync_status') THEN
    CREATE TYPE encounter_sync_status AS ENUM (
      'queued',
      'processing',
      'synced',
      'failed'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS encounters (
  encounter_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  asha_user_id UUID NOT NULL REFERENCES users(user_id),
  clinic_id UUID REFERENCES clinics(clinic_id),
  visit_type VARCHAR(50) NOT NULL DEFAULT 'home_visit', -- anc, pnc, fu, home_visit
  status VARCHAR(30) NOT NULL DEFAULT 'completed', -- completed/cancelled/in_progress
  occurred_at TIMESTAMPTZ NOT NULL,
  source_audio_bucket VARCHAR(255),
  source_audio_key VARCHAR(1024),
  transcription_text TEXT,
  translation_text TEXT,
  extracted_entities JSONB NOT NULL DEFAULT '{}'::jsonb,
  clinical_alerts JSONB NOT NULL DEFAULT '[]'::jsonb,
  fhir_encounter_id VARCHAR(255),
  sync_status encounter_sync_status NOT NULL DEFAULT 'synced',
  idempotency_key VARCHAR(128),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (idempotency_key)
);

CREATE TABLE IF NOT EXISTS encounter_alerts (
  encounter_alert_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  encounter_id UUID NOT NULL REFERENCES encounters(encounter_id) ON DELETE CASCADE,
  severity VARCHAR(20) NOT NULL, -- low, medium, high, critical
  alert_code VARCHAR(100),
  message TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS voice_jobs (
  voice_job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID REFERENCES patients(patient_id),
  asha_user_id UUID NOT NULL REFERENCES users(user_id),
  encounter_id UUID REFERENCES encounters(encounter_id),
  s3_bucket VARCHAR(255) NOT NULL,
  s3_key VARCHAR(1024) NOT NULL,
  language_code VARCHAR(10) NOT NULL DEFAULT 'hi-IN',
  context VARCHAR(50) NOT NULL DEFAULT 'asha_home_visit',
  transcription_job_id VARCHAR(255),
  processing_status VARCHAR(30) NOT NULL DEFAULT 'queued', -- queued, transcribing, extracting, completed, failed
  error_code VARCHAR(100),
  error_message TEXT,
  processing_started_at TIMESTAMPTZ,
  processing_completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_encounters_patient_time
  ON encounters(patient_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_encounters_asha_time
  ON encounters(asha_user_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_encounters_sync_status
  ON encounters(sync_status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_encounter_alerts_encounter
  ON encounter_alerts(encounter_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_voice_jobs_asha_time
  ON voice_jobs(asha_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_voice_jobs_status_time
  ON voice_jobs(processing_status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_voice_jobs_s3_key
  ON voice_jobs(s3_key);

