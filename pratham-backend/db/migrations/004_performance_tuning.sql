-- Performance and maintainability tuning for core + voice workflow tables.
-- Safe/idempotent migration for Aurora PostgreSQL.

CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Keep updated_at accurate on UPDATE statements.
CREATE OR REPLACE FUNCTION set_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  -- Core tables from 001
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'clinics') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_clinics ON clinics;
    CREATE TRIGGER trg_set_updated_at_clinics
      BEFORE UPDATE ON clinics
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'users') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_users ON users;
    CREATE TRIGGER trg_set_updated_at_users
      BEFORE UPDATE ON users
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'clinic_memberships') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_clinic_memberships ON clinic_memberships;
    CREATE TRIGGER trg_set_updated_at_clinic_memberships
      BEFORE UPDATE ON clinic_memberships
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'doctor_profiles') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_doctor_profiles ON doctor_profiles;
    CREATE TRIGGER trg_set_updated_at_doctor_profiles
      BEFORE UPDATE ON doctor_profiles
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'asha_profiles') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_asha_profiles ON asha_profiles;
    CREATE TRIGGER trg_set_updated_at_asha_profiles
      BEFORE UPDATE ON asha_profiles
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'patients') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_patients ON patients;
    CREATE TRIGGER trg_set_updated_at_patients
      BEFORE UPDATE ON patients
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;

  -- Workflow tables from 002
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'appointments') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_appointments ON appointments;
    CREATE TRIGGER trg_set_updated_at_appointments
      BEFORE UPDATE ON appointments
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'daily_clinical_metrics') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_daily_clinical_metrics ON daily_clinical_metrics;
    CREATE TRIGGER trg_set_updated_at_daily_clinical_metrics
      BEFORE UPDATE ON daily_clinical_metrics
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;

  -- Voice workflow tables from 003
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'encounters') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_encounters ON encounters;
    CREATE TRIGGER trg_set_updated_at_encounters
      BEFORE UPDATE ON encounters
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'voice_jobs') THEN
    DROP TRIGGER IF EXISTS trg_set_updated_at_voice_jobs ON voice_jobs;
    CREATE TRIGGER trg_set_updated_at_voice_jobs
      BEFORE UPDATE ON voice_jobs
      FOR EACH ROW EXECUTE FUNCTION set_updated_at_timestamp();
  END IF;
END $$;

-- Composite indexes for common access paths.
CREATE INDEX IF NOT EXISTS idx_patient_access_user_patient
  ON patient_access(user_id, patient_id);

CREATE INDEX IF NOT EXISTS idx_patients_clinic_updated
  ON patients(primary_clinic_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_clinic_memberships_clinic_status
  ON clinic_memberships(clinic_id, status);

CREATE INDEX IF NOT EXISTS idx_appointments_status_start
  ON appointments(status, scheduled_start_at);

CREATE INDEX IF NOT EXISTS idx_patient_remarks_importance_time
  ON patient_remarks(importance, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_encounters_clinic_time
  ON encounters(clinic_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_encounters_fhir_id
  ON encounters(fhir_encounter_id);

CREATE INDEX IF NOT EXISTS idx_voice_jobs_encounter
  ON voice_jobs(encounter_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_voice_jobs_transcription_job
  ON voice_jobs(transcription_job_id);

-- Faster partial-name searches for UI lookups.
CREATE INDEX IF NOT EXISTS idx_patients_full_name_trgm
  ON patients USING GIN (full_name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_users_full_name_trgm
  ON users USING GIN (full_name gin_trgm_ops);

