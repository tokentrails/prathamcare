package dynamo

import (
	"context"

	"github.com/prathamcare/backend/internal/models"
)

type Repository interface {
	PutSession(ctx context.Context, session models.Session) error
	GetSession(ctx context.Context, sessionID string) (models.Session, error)
	DeleteSession(ctx context.Context, sessionID string) error

	EnqueueOfflineAction(ctx context.Context, item models.OfflineQueueItem) error
	ListOfflineQueueByUser(ctx context.Context, userID string, limit int) ([]models.OfflineQueueItem, error)
	MarkOfflineActionProcessed(ctx context.Context, queueID string) error

	PutASHATaskLog(ctx context.Context, task models.TaskLog) error
	ListASHATaskLogs(ctx context.Context, ashaUserID string, limit int) ([]models.TaskLog, error)

	PutPhysicianScheduleSlot(ctx context.Context, slot models.PhysicianScheduleSlot) error
	ListPhysicianScheduleSlots(ctx context.Context, physicianID, date string) ([]models.PhysicianScheduleSlot, error)
}
