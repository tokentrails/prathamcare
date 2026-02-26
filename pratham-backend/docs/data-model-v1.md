# PrathamCare Data Model (Lambda + Mixed DB)

## Storage split
- `Aurora PostgreSQL + RDS Proxy`: users, clinics, profiles, patients index, appointments, remarks, triage assessments, daily metrics
- `DynamoDB`: sessions, offline queue, ASHA task logs, physician schedule slots
- `Amazon HealthLake`: all clinical FHIR resources (Patient/Encounter/Observation/Condition/MedicationRequest/etc.)
- `S3`: documents + voice recordings
- `OpenSearch Serverless`: vectorized chunks for RAG search

## Aurora models
- `clinics`
- `users`
- `clinic_memberships`
- `doctor_profiles`
- `asha_profiles`
- `patients` (read-only index from HealthLake)
- `patient_access`
- `appointments`
- `appointment_events`
- `patient_remarks`
- `triage_assessments`
- `daily_clinical_metrics`

## DynamoDB entities
- `Session`
- `OfflineQueueItem`
- `TaskLog`
- `PhysicianScheduleSlot`

## Read-only patient policy
- App treats patient demographic record as read-only.
- Patient data changes must come from FHIR sync/import workflows.
- Clinical changes are written as FHIR resources to HealthLake.

## Go model coverage
- Aurora structs: `internal/models/aurora.go`
- DynamoDB structs: `internal/models/dynamodb.go`
- FHIR payload structs: `internal/models/fhir.go`
- S3 document/voice structs: `internal/models/storage.go`
- OpenSearch vector structs: `internal/models/search.go`

## Next implementation step
- Implement concrete repository adapters for:
  - Aurora (`pgx` via RDS Proxy)
  - DynamoDB (`aws-sdk-go-v2/service/dynamodb`)
  - S3 (`aws-sdk-go-v2/service/s3`)
  - HealthLake/OpenSearch (signed HTTP clients)
