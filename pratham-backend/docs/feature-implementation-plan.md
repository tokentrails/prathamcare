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

## Suggested execution order after selection
- Build one vertical slice fully: API contract -> repo/service -> tests -> AWS integration -> docs.
- Then move to next feature without broad parallelization.
