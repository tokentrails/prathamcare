-- Extend patient demographics for ASHA registration/search workflow.
-- Safe/idempotent migration for Aurora PostgreSQL.

CREATE EXTENSION IF NOT EXISTS "pg_trgm";

ALTER TABLE patients
  ADD COLUMN IF NOT EXISTS abha_number VARCHAR(14),
  ADD COLUMN IF NOT EXISTS abha_address VARCHAR(255),
  ADD COLUMN IF NOT EXISTS first_name VARCHAR(100),
  ADD COLUMN IF NOT EXISTS middle_name VARCHAR(100),
  ADD COLUMN IF NOT EXISTS last_name VARCHAR(100),
  ADD COLUMN IF NOT EXISTS age_years SMALLINT,
  ADD COLUMN IF NOT EXISTS phone_number VARCHAR(20),
  ADD COLUMN IF NOT EXISTS phone_e164 VARCHAR(20),
  ADD COLUMN IF NOT EXISTS email VARCHAR(255),
  ADD COLUMN IF NOT EXISTS address_line1 VARCHAR(255),
  ADD COLUMN IF NOT EXISTS address_line2 VARCHAR(255),
  ADD COLUMN IF NOT EXISTS village_or_ward VARCHAR(120),
  ADD COLUMN IF NOT EXISTS gram_panchayat VARCHAR(120),
  ADD COLUMN IF NOT EXISTS block_or_taluk VARCHAR(120),
  ADD COLUMN IF NOT EXISTS district VARCHAR(120),
  ADD COLUMN IF NOT EXISTS state VARCHAR(120),
  ADD COLUMN IF NOT EXISTS pincode VARCHAR(6),
  ADD COLUMN IF NOT EXISTS landmark VARCHAR(255),
  ADD COLUMN IF NOT EXISTS consent_flags JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS created_by VARCHAR(255),
  ADD COLUMN IF NOT EXISTS updated_by VARCHAR(255),
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'active';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'patients'
      AND column_name = 'abha_id'
  ) THEN
    UPDATE patients
      SET abha_number = COALESCE(NULLIF(abha_number, ''), NULLIF(abha_id, ''))
      WHERE COALESCE(NULLIF(abha_number, ''), '') = '';
  END IF;
END $$;

UPDATE patients
SET
  phone_number = COALESCE(NULLIF(phone_number, ''), NULLIF(phone, '')),
  phone_e164 = COALESCE(NULLIF(phone_e164, ''), NULLIF(phone, '')),
  first_name = COALESCE(NULLIF(first_name, ''), split_part(full_name, ' ', 1)),
  last_name = COALESCE(
    NULLIF(last_name, ''),
    NULLIF(trim(regexp_replace(full_name, '^\S+\s*', '')), '')
  )
WHERE
  COALESCE(NULLIF(phone_number, ''), '') = ''
  OR COALESCE(NULLIF(phone_e164, ''), '') = ''
  OR COALESCE(NULLIF(first_name, ''), '') = ''
  OR COALESCE(NULLIF(last_name, ''), '') = '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_patients_abha
  ON patients (abha_number)
  WHERE abha_number IS NOT NULL AND abha_number <> '';

CREATE INDEX IF NOT EXISTS idx_patients_phone
  ON patients (phone_e164);

CREATE INDEX IF NOT EXISTS idx_patients_created_by_created_at
  ON patients (created_by, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_patients_name_trgm
  ON patients USING GIN (full_name gin_trgm_ops);
