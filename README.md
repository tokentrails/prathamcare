# PrathamCare — Unified AI-Powered Care for India

## One-line Pitch
One Flutter app (mobile + web) connecting Patients, ASHA workers, and Doctors with AWS AI for intelligent call-based triage, shared longitudinal EMR (FHIR), and 2-minute AI summaries.

## Mission and Constraints
- **Single app, three roles**: One Flutter codebase with role-aware UI for ASHA, Patient, and Physician experiences.
- **Cognito-first auth**: OTP login + RBAC via Amazon Cognito for every user, backend validates JWT on every request.
- **Go backend monolith**: A single Go Lambda (Gin/Chi + aws-lambda-go proxy) drives all APIs, avoiding microservices.
- **No extras**: MVP sticks to ASHA capture, call-based triage, doctor summary + SOAP, patient remarks; only basic logging/monitoring.

## Monorepo Layout (proposed)
```
/prathamcare
├── app/
│   └── flutter/            # Flutter app (mobile + web), Riverpod, Hive/sqflite local caching, Dio client
├── backend/
│   └── go/                 # Go monolith (handlers/services/repositories/models)
├── infra/                   # IaC for Cognito, Lambda, API Gateway, Aurora, HealthLake, S3, etc.
├── scripts/                 # Seed data loaders, doc helpers, automation
├── docs/                    # Design decisions, flow diagrams, AI prompts, glossary
└── README.md                # This file
```

## Tech Stack
- **Frontend**: Flutter + Dart, Riverpod, Hive/sqflite for offline, Dio for HTTP, qr/camera/record plugins, pdf generation.
- **Backend**: Go, Gin/Chi + aws-lambda-go proxy, AWS SDK Go v2, structured logging, JSON schema validation, retry/circuit-breaker wrappers.
- **Data stores**: Amazon HealthLake (FHIR R4) for Patient/Encounter/Observation/Condition/MedicationRequest/AllergyIntolerance/FamilyMemberHistory; Aurora PostgreSQL for users, physicians, schedules, appointments, remarks; DynamoDB for sessions/offline queue; S3 for documents/audio; OpenSearch Serverless for AI embeddings.
- **AI/Voice/Language**: Amazon Bedrock (summaries/triage/categorization), Amazon Lex (symptom intake), Amazon Connect (triage IVR), Amazon Transcribe Medical, Amazon Comprehend Medical, Amazon Translate, Amazon Textract, OpenSearch RAG.
- **Security**: Amazon Cognito (OTP + RBAC), AWS KMS (encryption), Secrets Manager, WAF, TLS everywhere.

## Core Flows
1. **ASHA Visit → EMR Update**: ASHA logs in → selects/creates patient → records vitals/voice → backend transcribes (Transcribe Medical) → Comprehend Medical maps entities → create HealthLake Encounter/Observation/Condition → store audio/docs in S3 + link references → Bedrock suggests next steps.
2. **Call Triage → Physician Match → Appointment**: Patient calls Connect number / app → Lex captures symptoms/language/location/ABHA → Lambda calls Bedrock for assessment → Aurora matcher finds physician (specialty + language + availability) → appointment + HealthLake placeholder encounter created → SNS + EventBridge reminders triggered.
3. **Doctor Consult → SOAP + Prescription**: Doctor sees appointments + AI summary (Bedrock + RAG) → dictates encounter → Transcribe Medical → Bedrock structures SOAP with Assessment/Plan → persist Encounter/Condition/MedicationRequest in HealthLake → generate e-prescription PDF in S3 (shared link).
4. **Patient Remark ↔ Highlights**: Patient adds remark (text/voice) → transcribe/translate → Bedrock categorizes/importance → save in Aurora (＋ optional FHIR Allergy/FamilyMemberHistory) → surfaces in doctor summary.

## Backend APIs (OpenAPI-focused)
| Area | Routes |
|------|--------|
| Auth | `Cognito` driven; backend checks JWT (`/auth/validate`).
| Patients | `GET /patients?query=`, `POST /patients`, `GET /patients/{id}/timeline`, `POST /patients/{id}/scan-abha`.
| Encounters | `POST /encounters`, `POST /encounters/{id}/voice-note`, `POST /encounters/{id}/soap`.
| Appointments | `POST /appointments`, `GET /appointments?role=doctor|patient`, `POST /appointments/{id}/summary`.
| Remarks | `POST /patients/{id}/remarks`.
| Documents | `POST /patients/{id}/documents` (signed upload), `GET /patients/{id}/documents`.
| Triage | `POST /triage/analyze`, `POST /triage/match`, `POST /triage/webhook` (Lex).
| Prescriptions | `POST /encounters/{id}/prescriptions`, `GET /prescriptions/{id}/pdf`.
| Sync/Offline | `POST /sync/queue`, `GET /sync/status`.

Each response includes privacy disclaimer (non-diagnostic, synthetic/public data). Errors follow shared schema with timestamp/request_id.

## Data Model Snapshot
- **HealthLake**: Patients, Practitioners, Encounters, Observations, Conditions, MedicationRequests, AllergyIntolerance, FamilyMemberHistory, DocumentReference for uploads.
- **Aurora**: `users` (cognito_sub, role, fhir refs), `physicians`, `physician_schedule`, `appointments`, `patient_remarks`, `waitlist`.
- **DynamoDB**: `sessions` (optional), `offline_queue` for disconnected ASHA work.
- **S3**: `medical-documents/{patientId}/{type}/{timestamp}/`, `voice-recordings/{userId}/{timestamp}/`.
- **OpenSearch**: Guideline docs, patient semantic summaries embeddings for RAG.

## Infrastructure & Deployment
- **Lambda + API Gateway**: Single Go binary behind API Gateway with WAF. Cognito authorizer validates OTP-issued JWTs.
- **Monitoring**: CloudWatch Logs (structured), basic alarms (error rate, latency). No heavy dashboards—keep focus on logs/alerts.
- **Config**: 100% env vars (DB URLs, AWS roles, log level); `.env.example` seeds required vars.
- **Local Dev**: `docker-compose` for Aurora/Postgres; optional LocalStack mocks for AWS (Transcribe/Bedrock stubbed) if needed. Provide scripts to seed demo users (ASHA/Doctor/Patient) and doctor schedules.

## Testing & Quality
- **Unit Tests**: Go tests for triage parsing, summary formatting, physician matching; Flutter widget/provider tests for each role.
- **Property Tests**: `gopter` harness ensures invariants (triage urgency, summary length < 400 words, matching correctness).
- **Integration**: API tests covering OTP login, ASHA capture, triage → appointment, SOAP note + prescription.
- **End-to-End**: Flutter integration tests for ASHA, Patient, Physician journeys.
- **Retry + Circuit Breaker**: Backend wraps AWS calls with configurable retries + circuit breaker.

## Security & Privacy
- RBAC enforced by Cognito roles; backend inspects JWT claims.
- Sensitive data: only FHIR IDs logged, ABHA numbers redacted, phone numbers partially masked.
- TLS everywhere, requests signed with KMS-backed secrets, uploads validated by type/size.
- API + UI disclaimers stressing non-diagnostic, synthetic/public data only.

## Next Steps
1. Scaffold Flutter + Go projects following the outlined layout.
2. Build API contracts (OpenAPI spec, sample payloads) for each route.
3. Script seed data + AWS infrastructure provisioning (Cognito, Lambda, Aurora, HealthLake, S3, DynamoDB, OpenSearch).

