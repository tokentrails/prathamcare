package models

import "time"

type Session struct {
	SessionID      string    `json:"session_id"`
	UserID         string    `json:"user_id"`
	DeviceID       string    `json:"device_id"`
	AccessTokenJTI string    `json:"access_token_jti"`
	RefreshTokenJTI string   `json:"refresh_token_jti,omitempty"`
	ExpiresAt      time.Time `json:"expires_at"`
	LastSeenAt     time.Time `json:"last_seen_at"`
}

type OfflineQueueItem struct {
	QueueID             string    `json:"queue_id"`
	UserID              string    `json:"user_id"`
	ActionType          string    `json:"action_type"`
	ResourceType        string    `json:"resource_type"`
	ResourceID          string    `json:"resource_id,omitempty"`
	Payload             string    `json:"payload"`
	Status              string    `json:"status"`
	ConflictResolution  string    `json:"conflict_resolution,omitempty"`
	RetryCount          int       `json:"retry_count"`
	NextRetryAt         time.Time `json:"next_retry_at,omitempty"`
	CreatedAt           time.Time `json:"created_at"`
	ProcessedAt         time.Time `json:"processed_at,omitempty"`
}

type TaskLog struct {
	TaskID             string    `json:"task_id"`
	ASHAUserID         string    `json:"asha_user_id"`
	PatientID          string    `json:"patient_id,omitempty"`
	TaskType           string    `json:"task_type"`
	Priority           string    `json:"priority"`
	CompletionStatus   string    `json:"completion_status"`
	DueAt              time.Time `json:"due_at,omitempty"`
	CompletedAt        time.Time `json:"completed_at,omitempty"`
	CreatedAt          time.Time `json:"created_at"`
}

type PhysicianScheduleSlot struct {
	PhysicianID        string    `json:"physician_id"`
	ScheduleDate       string    `json:"schedule_date"`
	SlotID             string    `json:"slot_id"`
	StartTime          time.Time `json:"start_time"`
	EndTime            time.Time `json:"end_time"`
	Status             string    `json:"status"`
	AppointmentID      string    `json:"appointment_id,omitempty"`
	ConsultMode        string    `json:"consult_mode"`
}
