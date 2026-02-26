# PrathamCare Backend (Go Lambda)

Initial backend scaffold for AWS Lambda with mixed data stores:
- DynamoDB for sessions/offline queue/task logs/schedules
- Aurora PostgreSQL (+ RDS Proxy) for app relational workflows
- HealthLake for FHIR clinical resources
- S3 for documents and voice recordings
- OpenSearch Serverless for RAG vectors

## Structure
- `cmd/api`: Lambda entrypoint
- `internal/config`: env-based runtime config
- `internal/api`: HTTP handler for API Gateway proxy events
- `internal/models`: domain models by storage type
- `internal/repositories/*`: repository interfaces for each datastore
- `db/migrations`: Aurora SQL migrations
- `docs`: data model and table design docs

## Local bootstrap
```bash
cd pratham-backend
go mod tidy
go build ./cmd/api
```

## Environment
Copy `.env.example` and set real values in Lambda environment variables.

## Current route
- `GET /health`
- `GET /ready`
- `GET /api/v1/me` (Cognito JWT required)

## Next implementation
1. Add feature services on top of repositories (appointments, remarks, triage).
2. Add OpenAPI v1 contracts and request validation.
3. Add migration runner and seed scripts.
4. Add endpoint-level unit/integration tests.
