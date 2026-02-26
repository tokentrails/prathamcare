# DynamoDB Table Design (MVP)

## 1) sessions
- PK: `session_id` (S)
- Attributes: `user_id`, `device_id`, `access_token_jti`, `refresh_token_jti`, `expires_at`, `last_seen_at`
- TTL attribute: `expires_at`
- GSI1 (optional): `user_id` + `last_seen_at`

## 2) offline_queue
- PK: `queue_id` (S)
- SK: `user_id` (S) optional design (or store user as attribute)
- Attributes: `action_type`, `resource_type`, `resource_id`, `payload`, `status`, `retry_count`, `next_retry_at`, `created_at`, `processed_at`
- GSI1: `user_id` + `created_at`
- GSI2: `status` + `next_retry_at`

## 3) task_logs
- PK: `task_id` (S)
- Attributes: `asha_user_id`, `patient_id`, `task_type`, `priority`, `completion_status`, `due_at`, `completed_at`, `created_at`
- GSI1: `asha_user_id` + `created_at`
- GSI2: `asha_user_id` + `completion_status`

## 4) schedules
- PK: `physician_id` (S)
- SK: `schedule_date#slot_id` (S)
- Attributes: `start_time`, `end_time`, `status`, `appointment_id`, `consult_mode`
- Query pattern: all slots for physician by day; open slots for matching flow
