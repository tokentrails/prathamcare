package models

import "time"

type Session struct {
	SessionID       string    `json:"session_id" dynamodbav:"sessionId"`
	UserID          string    `json:"user_id" dynamodbav:"userId"`
	DeviceID        string    `json:"device_id" dynamodbav:"deviceId"`
	AccessTokenJTI  string    `json:"access_token_jti" dynamodbav:"accessTokenJti"`
	RefreshTokenJTI string    `json:"refresh_token_jti,omitempty" dynamodbav:"refreshTokenJti,omitempty"`
	ExpiresAt       time.Time `json:"expires_at" dynamodbav:"expiresAt"`
	LastSeenAt      time.Time `json:"last_seen_at" dynamodbav:"lastSeenAt"`
}

type OfflineQueueItem struct {
	PatientID           string    `json:"patient_id" dynamodbav:"patientId"`
	Timestamp           string    `json:"timestamp" dynamodbav:"timestamp"`
	QueueID             string    `json:"queue_id" dynamodbav:"queueId"`
	UserID              string    `json:"user_id" dynamodbav:"userId"`
	ActionType          string    `json:"action_type" dynamodbav:"actionType"`
	ResourceType        string    `json:"resource_type" dynamodbav:"resourceType"`
	ResourceID          string    `json:"resource_id,omitempty" dynamodbav:"resourceId,omitempty"`
	Payload             string    `json:"payload" dynamodbav:"payload"`
	Status              string    `json:"status" dynamodbav:"status"`
	ConflictResolution  string    `json:"conflict_resolution,omitempty" dynamodbav:"conflictResolution,omitempty"`
	RetryCount          int       `json:"retry_count" dynamodbav:"retryCount"`
	NextRetryAt         time.Time `json:"next_retry_at,omitempty" dynamodbav:"nextRetryAt,omitempty"`
	CreatedAt           time.Time `json:"created_at" dynamodbav:"createdAt"`
	ProcessedAt         time.Time `json:"processed_at,omitempty" dynamodbav:"processedAt,omitempty"`
}

type TaskLog struct {
	TaskID           string    `json:"task_id" dynamodbav:"taskId"`
	ASHAUserID       string    `json:"asha_user_id" dynamodbav:"ashaUserId"`
	PatientID        string    `json:"patient_id,omitempty" dynamodbav:"patientId,omitempty"`
	TaskType         string    `json:"task_type" dynamodbav:"taskType"`
	Priority         string    `json:"priority" dynamodbav:"priority"`
	CompletionStatus string    `json:"completion_status" dynamodbav:"completionStatus"`
	DueAt            time.Time `json:"due_at,omitempty" dynamodbav:"dueAt,omitempty"`
	CompletedAt      time.Time `json:"completed_at,omitempty" dynamodbav:"completedAt,omitempty"`
	CreatedAt        time.Time `json:"created_at" dynamodbav:"createdAt"`
}

type PhysicianScheduleSlot struct {
	PhysicianID   string    `json:"physician_id" dynamodbav:"physician_id"`
	ScheduleDate  string    `json:"schedule_date" dynamodbav:"schedule_date"`
	SlotID        string    `json:"slot_id" dynamodbav:"slot_id"`
	StartTime     time.Time `json:"start_time" dynamodbav:"start_time"`
	EndTime       time.Time `json:"end_time" dynamodbav:"end_time"`
	Status        string    `json:"status" dynamodbav:"status"`
	AppointmentID string    `json:"appointment_id,omitempty" dynamodbav:"appointment_id,omitempty"`
	ConsultMode   string    `json:"consult_mode" dynamodbav:"consult_mode"`
}
