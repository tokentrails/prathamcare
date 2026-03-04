-- Align voice job defaults with Kannada+English auto-detection.
-- Keeps inserts without explicit language from defaulting to Hindi.
ALTER TABLE IF EXISTS voice_jobs
  ALTER COLUMN language_code SET DEFAULT 'auto';
