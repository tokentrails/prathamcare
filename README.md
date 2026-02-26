# PrathamCare

Unified AI-powered healthcare platform connecting ASHA workers, physicians, and patients on AWS.

## Detailed Summary
PrathamCare is designed to reduce fragmentation in care delivery by combining role-specific workflows into a single platform:
- ASHA workers capture field data quickly, including voice-first documentation and offline-first sync.
- Physicians get a structured clinical workspace with timeline context, AI-assisted summaries, and appointment intelligence.
- Patients can contribute updates, access records, and engage in triage/consult journeys.

The system uses FHIR-aligned clinical modeling in HealthLake, relational operational workflows in Aurora, and AWS AI services for transcription, extraction, categorization, and summarization.

## Features
### ASHA Worker Features
- Voice-first home-visit capture for rapid documentation.
- Offline data entry with queued sync behavior.
- Structured encounter creation (vitals, symptoms, observations).
- Multilingual capture support for field workflows.

### Physician Features
- Doctor dashboard with schedule-focused workflow.
- AI clinical briefing and summary-oriented review.
- Appointment cards with risk/status tagging.
- Quick actions for encounter start and note capture.

### Patient Features
- Patient-originated remarks (text/voice) for context sharing.
- Record visibility patterns aligned to clinical access controls.
- Triage and physician-matching oriented intake flows.

### Platform Features
- Cognito-based authentication and role-aware authorization.
- FHIR resource mapping across patient/encounter/observation/medication/condition.
- S3-backed media/document workflows via secure upload patterns.
- Real-time and near-real-time update patterns for clinical notifications.

## Core Workflows
- ASHA Voice Capture -> Transcription -> Entity extraction -> FHIR encounter updates.
- AI Triage -> Physician matching -> Appointment creation -> Provider notification.
- EMR Summary -> FHIR + operational data retrieval -> AI summarization.
- Patient Remarks -> Voice/text processing -> Categorization -> Physician visibility.

<img width="1357" height="905" alt="image" src="https://github.com/user-attachments/assets/3aa80e93-562b-49a8-a35f-f1c3f4782330" />

## Repository Layout
```text
prathamcare/
├── pratham-app/
│   └── prathamcare/              # Flutter app (mobile/web)
├── pratham-backend/              # Go Lambda backend scaffold
├── AGENTS.md                     # Project orchestration instructions
├── pratham.md                    # Product/problem context
└── README.md                     # This file
```

## Tech Stack
- Frontend: Flutter (Dart)
- Backend: Go (AWS Lambda-ready scaffold)
- Cloud/Data/AI targets: API Gateway, Cognito, HealthLake (FHIR), Aurora, DynamoDB, S3, Bedrock, Transcribe, Comprehend

## Run Frontend
```bash
cd pratham-app/prathamcare
flutter pub get
flutter run -d chrome
```

## Run Backend
```bash
cd pratham-backend
go mod tidy
go run ./cmd/api
```

## Backend Health Endpoints
- `GET /health`
- `GET /ready`
- `GET /api/v1/me` (Cognito JWT required)

## Notes
- Root logo source: `pratham-logo.png`
- App logo asset: `pratham-app/prathamcare/assets/images/pratham-logo.png`
- App font: `PlusJakartaSans` registered via `pubspec.yaml`
