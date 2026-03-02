# PrathamCare Backend Feature Implementation Plan (Phased)

This plan assumes the current scaffold is in place (Lambda entrypoint, core models, SQL migrations, repository interfaces).

## Product decision
- No patient mobile app for MVP.
- App users are providers/clinical workers.
- Patients receive visit summaries, reports, and lab records via SMS/email/WhatsApp secure share links.

## Phase 0: Platform Foundation (Mandatory)

## Goals
- Make backend deployable and testable in AWS dev environment.
- Finalize cross-cutting concerns before feature coding.

## Tasks
- Implement concrete repository adapters:
  - Aurora (`pgx` + RDS Proxy)
  - DynamoDB (AWS SDK v2)
  - S3 (presign + object metadata)
  - HealthLake and OpenSearch signed HTTP clients
- Add Cognito JWT middleware + RBAC enforcement.
- Add standard API error envelope + request IDs.
- Add migration runner and seed scripts for demo users/clinics.
- Add CI checks: `go test`, lint, build.

## Deliverables
- `GET /health` + `GET /ready` working in Lambda/API Gateway.
- Auth-protected route verified with Cognito token.
- Aurora + DynamoDB connectivity in dev.

---

## Phase 1: Core Operational Features (Choose First Feature Slice)

### Feature A: Clinician Identity, Clinic Membership, and Schedule

## Why first
- Required by almost all downstream features (triage booking, appointments, care coordination).

## APIs
- `GET /api/v1/me`
- `GET /api/v1/clinics/{id}/staff`
- `PUT /api/v1/physicians/{id}/schedule`
- `GET /api/v1/physicians/{id}/schedule?date=YYYY-MM-DD`

## Data dependencies
- `users`, `clinics`, `clinic_memberships`, `doctor_profiles`, `asha_profiles`, DynamoDB `schedules`.

## Effort
- Low-Medium

### Feature B: Appointments and Booking Lifecycle

## APIs
- `POST /api/v1/appointments`
- `GET /api/v1/appointments?role=doctor|asha_worker&from=&to=`
- `PATCH /api/v1/appointments/{id}/status`

## Data dependencies
- `appointments`, `appointment_events`, DynamoDB `schedules`.

## Effort
- Medium

### Feature B2: Notification and Share-Link Delivery

## APIs
- `POST /api/v1/patients/{id}/share-links`
- `POST /api/v1/notifications/send`
- `GET /api/v1/notifications/{id}/status`

## AWS services
- S3 (pre-signed read links), SNS (SMS), SES (email), WhatsApp provider bridge, EventBridge (retry).

## Outputs
- Time-bound secure link and delivery status by channel.

## Effort
- Medium

### Feature C: Patient Index Access (Read-only)

## APIs
- `GET /api/v1/patients/{id}`
- `GET /api/v1/patients?clinic_id=&query=`
- `GET /api/v1/patients/{id}/timeline` (HealthLake-backed)

## Data dependencies
- `patients`, `patient_access`, HealthLake patient/encounter/observation search.

## Effort
- Medium

---

## Phase 2: AI-Enabled Clinical Workflows

### Feature D: AI Call Triage + Physician Matching

## APIs
- `POST /api/v1/triage/analyze`
- `POST /api/v1/triage/match-physician`

## AWS services
- Connect + Lex + Transcribe + Bedrock + Aurora + DynamoDB schedules + SNS/EventBridge.

## Outputs
- severity, preliminary diagnosis, recommended specialty, ranked physician slots.

## Effort
- High

### Feature E: ASHA Voice Capture to Structured Encounter Inputs

## APIs
- `POST /api/v1/voice/presign`
- `POST /api/v1/voice/transcribe`

## AWS services
- S3 + Transcribe Medical + Comprehend Medical + Bedrock.

## Outputs
- transcription, extracted clinical entities, alerts.

## Effort
- Medium-High

### Feature F: Patient Remarks (Voice/Text) with Clinical Highlighting

## APIs
- `POST /api/v1/patients/{id}/remarks`
- `GET /api/v1/patients/{id}/remarks`

## AWS services
- S3 + Transcribe + Translate + Bedrock.

## Outputs
- categorized remarks, importance level, physician-visible flags.

## Effort
- Medium

---

## Phase 3: Physician EMR Intelligence

### Feature G: Pre-Consultation AI Summary

## APIs
- `GET /api/v1/patients/{id}/summary`

## AWS services
- HealthLake + Aurora remarks + Bedrock + cache layer.

## SLO
- `<3s` cached, `<5s` uncached.

## Effort
- Medium-High

### Feature H: Encounter Documentation + SOAP Generation

## APIs
- `POST /api/v1/encounters`
- `POST /api/v1/encounters/{id}/soap`

## AWS services
- Transcribe Medical + Bedrock + HealthLake writes.

## Effort
- High

---

## Phase 4: Search, Automation, and Observability

### Feature I: RAG Search over Clinical Knowledge and Patient Context

## APIs
- `POST /api/v1/search/semantic`

## AWS services
- OpenSearch Serverless + Bedrock embeddings/generation.

## Effort
- Medium

### Feature J: Event-driven Workflow Automation

## Scope
- reminders, follow-ups, escalation alerts via EventBridge + SNS.

## Effort
- Medium

### Feature K: Production Readiness

## Scope
- dashboards, alarms, traces, audit evidence, rate limits, retry policies.

## Effort
- Medium

---

## Recommended First Feature Targets (Pick One)

1. `Feature A + B` (Identity/Schedule/Appointments)
- Fastest path to operational core.
- De-risks later triage and consult flows.

2. `Feature F` (Patient Remarks)
- Strong demo impact with moderate complexity.
- Touches S3 + Transcribe/Translate + Bedrock + Aurora.

3. `Feature D` (Call Triage + Physician Matching)
- Highest hackathon wow factor.
- Highest integration complexity and risk.

---

## Phase 1 Execution Plan: ASHA Voice Visit (End-to-End AI Flow)

### Implementation status (current)
- Done:
  - `POST /api/v1/voice/presign` implemented with auth + size/type validation.
  - `POST /api/v1/voice/transcribe` wired for:
    - Transcribe job execution (or mock transcript path for UI simulation).
    - Bedrock JSON extraction fallback + deterministic regex fallback.
    - Comprehend Medical enrichment.
    - `voice_jobs` persistence in Aurora (best effort).
  - `POST /api/v1/encounters` wired for:
    - Aurora `encounters` + `encounter_alerts` writes.
    - Idempotency key handling.
    - Optional HealthLake FHIR `Encounter` write and sync status marking.
- In progress / remaining:
  - Seed `users` mapping for Cognito `sub` to internal `users.user_id` (required for strict FK writes).
  - Run backend dependency sync (`go mod tidy`) and deploy updated Lambda.
  - Run end-to-end smoke test with real audio upload + real transcription.

### Selected flow
- ASHA taps `Voice Visit` from dashboard (Figma node `6:100`), records visit note, uploads audio, receives AI-structured output, reviews/edits, and submits encounter.
- This is the best first slice because it demonstrates field usability + AI value + FHIR-aligned output in one loop.

### Scope for first milestone (2-3 week implementation)
- In-scope:
  - Voice recording/upload from Flutter ASHA app.
  - Backend transcription + entity extraction + alert generation.
  - Structured preview + confirm screen in app.
  - Encounter save to operational store + HealthLake.
  - Offline queue with retry when network is unavailable.
- Out-of-scope (defer):
  - Full multilingual translation for all languages (start with `hi-IN` + `en-IN`).
  - Advanced physician notification fan-out.
  - Complex conflict resolution UI.

### End-to-end sequence
1. ASHA opens home screen, selects `Voice Visit`.
2. App records `.wav` (<=10 MB) and requests presigned upload URL.
3. App uploads audio to S3.
4. App calls transcription endpoint with S3 key + context (`asha_home_visit`).
5. Backend runs Transcribe Medical (or Transcribe fallback), then Comprehend Medical + Bedrock extraction.
6. Backend returns:
   - transcription
   - extracted entities (patient name, visit type, vitals, symptoms)
   - risk flags/alerts
7. ASHA verifies/edit structured fields and submits encounter.
8. Backend writes encounter:
   - Aurora: workflow record
   - HealthLake: FHIR `Encounter` + `Observation` (+ optional `Condition`)
9. App marks local queue item as synced and updates visit card status.

### API contract (Phase 1)
- `POST /api/v1/voice/presign`
  - Request: `{ "content_type": "audio/wav", "file_size_bytes": 1234567, "context": "asha_home_visit" }`
  - Response: `{ "upload_url": "...", "object_key": "voice/...", "expires_in": 900 }`
- `POST /api/v1/voice/transcribe`
  - Request: `{ "object_key": "voice/...", "language": "hi-IN", "context": "asha_home_visit", "patient_id": "uuid-..." }`
  - Response: `{ "transcription": "...", "extracted_entities": {...}, "clinical_alerts": [...], "confidence": 0.0 }`
- `POST /api/v1/encounters`
  - Request: validated structured encounter payload from review screen
  - Response: `{ "encounter_id": "...", "fhir_encounter_ref": "Encounter/...", "sync_status": "synced|queued" }`
- `GET /api/v1/sync/status?device_id=...`
  - Response: pending queue counts for ASHA dashboard status pills.

### Data model additions
- Aurora:
  - `voice_jobs` (job_id, object_key, asha_user_id, status, error, created_at, completed_at)
  - `encounters` (encounter_id, patient_id, asha_user_id, visit_type, occurred_at, sync_status, source_audio_key)
  - `encounter_alerts` (encounter_id, severity, code, message)
- DynamoDB:
  - `OfflineQueue` items keyed by `device_id#timestamp` with operation type (`TRANSCRIBE`, `SUBMIT_ENCOUNTER`), retry count, backoff.
- S3:
  - `voice-visits/{clinic_id}/{date}/{uuid}.wav` with SSE-KMS and lifecycle policy.

### Backend work breakdown (Go + AWS)
1. Routing + handlers
  - Add routes for `voice/presign`, `voice/transcribe`, `encounters`.
  - Apply Cognito auth + role guard (`asha_worker`).
2. Storage and validation
  - Presigned URL generation with MIME and max-size checks.
  - Reject unsupported formats and oversized payloads.
3. AI orchestration service
  - Transcription adapter (Transcribe Medical; fallback to Transcribe standard when needed).
  - Entity extraction adapter (Comprehend Medical + Bedrock normalization).
  - Deterministic prompt contract for structured JSON extraction.
4. Encounter persistence
  - Write operational record to Aurora.
  - Map to FHIR resources and write to HealthLake.
5. Error model + idempotency
  - Idempotency key for `POST /encounters`.
  - Standard envelope with `request_id` and retry-safe error codes.
6. Async resiliency
  - Optional Step Functions/EventBridge for long-running transcription if >30s path is unstable.

### Frontend work breakdown (Flutter)
1. ASHA dashboard integration
  - Replace placeholder with Figma-aligned sections; wire `Voice Visit` CTA.
2. Voice capture flow
  - Record audio (`record` package), local playback, upload progress.
3. AI result review screen
  - Show transcription + extracted vitals/visit type + risk alerts.
  - Allow inline correction before submit.
4. Offline-first behavior
  - Store pending actions in Hive/sqflite queue.
  - Auto-retry via connectivity changes + manual retry.
5. UX states
  - Clear states: `Uploading`, `Transcribing`, `Needs Review`, `Synced`, `Failed`.
  - Friendly failure messages mapped from backend error codes.

### Security and compliance controls
- Enforce Cognito JWT and RBAC per endpoint.
- Encrypt audio in transit (TLS 1.3) and at rest (SSE-KMS).
- Strip PHI from logs; log only request IDs and operational metadata.
- Signed URL expiry <= 15 minutes; single-object scope only.

### Performance targets for this slice
- Presign response: <500ms p95.
- Upload start acknowledgement: <200ms client-side after tap.
- Transcription + extraction: <30s p95 for <=2-minute recordings.
- Encounter submit: <2s p95 excluding AI stage.

### Testing and acceptance criteria
- Backend:
  - Unit tests for handlers, validators, and AI response parsing.
  - Integration tests with mocked AWS clients + one dev-stack smoke test.
- Frontend:
  - Widget tests for recorder/review/submit states.
  - Offline integration test: airplane mode queue then sync.
- E2E acceptance:
  - ASHA can complete one Hindi voice visit and produce structured encounter + alert.
  - Encounter visible in backend store and represented in HealthLake.
  - Failure path shows retry without data loss.

### Delivery milestones
- Milestone 1 (Days 1-3): API contracts frozen + mock responses + Flutter flow stubs.
- Milestone 2 (Days 4-7): S3 upload + transcription pipeline + basic review UI.
- Milestone 3 (Days 8-11): Encounter write + HealthLake mapping + offline queue.
- Milestone 4 (Days 12-14): hardening, test pass, demo script, monitoring dashboard.

### Demo script for judging
1. Open ASHA dashboard, show `Pending Sync` count.
2. Record voice visit in Hindi from `Voice Visit`.
3. Show AI extracted vitals and high-risk flag.
4. Confirm and submit encounter.
5. Toggle offline and queue another visit; restore network and show sync success.

## Suggested execution order after selection
- Build one vertical slice fully: API contract -> repo/service -> tests -> AWS integration -> docs.
- Then move to next feature without broad parallelization.
