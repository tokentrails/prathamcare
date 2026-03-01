package dynamo

import (
	"context"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/prathamcare/backend/internal/models"
)

type DynamoRepository struct {
	client         *dynamodb.Client
	tableSessions  string
	tableOfflineQ  string
	tableTaskLogs  string
	tableSchedules string
	schedulePKName string
	scheduleSKName string
}

type Config struct {
	Region         string
	TableSessions  string
	TableOfflineQ  string
	TableTaskLogs  string
	TableSchedules string
	SchedulePKName string
	ScheduleSKName string
}

func NewDynamoRepository(ctx context.Context, cfg Config) (*DynamoRepository, error) {
	awsCfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(cfg.Region))
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}
	return &DynamoRepository{
		client:         dynamodb.NewFromConfig(awsCfg),
		tableSessions:  cfg.TableSessions,
		tableOfflineQ:  cfg.TableOfflineQ,
		tableTaskLogs:  cfg.TableTaskLogs,
		tableSchedules: cfg.TableSchedules,
		schedulePKName: cfg.SchedulePKName,
		scheduleSKName: cfg.ScheduleSKName,
	}, nil
}

func (r *DynamoRepository) PutSession(ctx context.Context, session models.Session) error {
	item, err := attributevalue.MarshalMap(session)
	if err != nil {
		return err
	}
	_, err = r.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(r.tableSessions), Item: item})
	return err
}

func (r *DynamoRepository) GetSession(ctx context.Context, sessionID string) (models.Session, error) {
	out, err := r.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(r.tableSessions),
		Key: map[string]types.AttributeValue{
			"sessionId": &types.AttributeValueMemberS{Value: sessionID},
		},
	})
	if err != nil {
		return models.Session{}, err
	}
	if len(out.Item) == 0 {
		return models.Session{}, fmt.Errorf("session not found")
	}
	var session models.Session
	if err := attributevalue.UnmarshalMap(out.Item, &session); err != nil {
		return models.Session{}, err
	}
	return session, nil
}

func (r *DynamoRepository) DeleteSession(ctx context.Context, sessionID string) error {
	_, err := r.client.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(r.tableSessions),
		Key: map[string]types.AttributeValue{
			"sessionId": &types.AttributeValueMemberS{Value: sessionID},
		},
	})
	return err
}

func (r *DynamoRepository) EnqueueOfflineAction(ctx context.Context, item models.OfflineQueueItem) error {
	if item.PatientID == "" {
		if item.ResourceID != "" {
			item.PatientID = item.ResourceID
		} else {
			item.PatientID = "user#" + item.UserID
		}
	}
	if item.Timestamp == "" {
		t := item.CreatedAt
		if t.IsZero() {
			t = time.Now().UTC()
			item.CreatedAt = t
		}
		item.Timestamp = t.Format(time.RFC3339Nano)
	}
	av, err := attributevalue.MarshalMap(item)
	if err != nil {
		return err
	}
	_, err = r.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(r.tableOfflineQ), Item: av})
	return err
}

func (r *DynamoRepository) ListOfflineQueueByUser(ctx context.Context, userID string, limit int) ([]models.OfflineQueueItem, error) {
	if limit <= 0 || limit > 100 {
		limit = 25
	}
	out, err := r.client.Scan(ctx, &dynamodb.ScanInput{
		TableName:                 aws.String(r.tableOfflineQ),
		Limit:                     aws.Int32(int32(limit)),
		FilterExpression:          aws.String("userId = :uid"),
		ExpressionAttributeValues: map[string]types.AttributeValue{":uid": &types.AttributeValueMemberS{Value: userID}},
	})
	if err != nil {
		return nil, err
	}
	items := make([]models.OfflineQueueItem, 0, len(out.Items))
	for _, raw := range out.Items {
		var item models.OfflineQueueItem
		if err := attributevalue.UnmarshalMap(raw, &item); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, nil
}

func (r *DynamoRepository) MarkOfflineActionProcessed(ctx context.Context, queueID string) error {
	lookup, err := r.client.Scan(ctx, &dynamodb.ScanInput{
		TableName:                 aws.String(r.tableOfflineQ),
		Limit:                     aws.Int32(1),
		FilterExpression:          aws.String("queueId = :qid"),
		ExpressionAttributeValues: map[string]types.AttributeValue{":qid": &types.AttributeValueMemberS{Value: queueID}},
	})
	if err != nil {
		return err
	}
	if len(lookup.Items) == 0 {
		return fmt.Errorf("offline queue item not found: %s", queueID)
	}

	var item models.OfflineQueueItem
	if err := attributevalue.UnmarshalMap(lookup.Items[0], &item); err != nil {
		return err
	}
	if item.PatientID == "" || item.Timestamp == "" {
		return fmt.Errorf("offline queue item missing keys: patientId/timestamp")
	}

	_, err := r.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(r.tableOfflineQ),
		Key: map[string]types.AttributeValue{
			"patientId": &types.AttributeValueMemberS{Value: item.PatientID},
			"timestamp": &types.AttributeValueMemberS{Value: item.Timestamp},
		},
		UpdateExpression: aws.String("SET #status = :status, processedAt = :processed_at"),
		ExpressionAttributeNames: map[string]string{
			"#status": "status",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":status":       &types.AttributeValueMemberS{Value: "processed"},
			":processed_at": &types.AttributeValueMemberS{Value: time.Now().UTC().Format(time.RFC3339)},
		},
	})
	return err
}

func (r *DynamoRepository) PutASHATaskLog(ctx context.Context, task models.TaskLog) error {
	item, err := attributevalue.MarshalMap(task)
	if err != nil {
		return err
	}
	_, err = r.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(r.tableTaskLogs), Item: item})
	return err
}

func (r *DynamoRepository) ListASHATaskLogs(ctx context.Context, ashaUserID string, limit int) ([]models.TaskLog, error) {
	if limit <= 0 || limit > 100 {
		limit = 25
	}
	out, err := r.client.Scan(ctx, &dynamodb.ScanInput{
		TableName:                 aws.String(r.tableTaskLogs),
		Limit:                     aws.Int32(int32(limit)),
		FilterExpression:          aws.String("ashaUserId = :aid"),
		ExpressionAttributeValues: map[string]types.AttributeValue{":aid": &types.AttributeValueMemberS{Value: ashaUserID}},
	})
	if err != nil {
		return nil, err
	}
	items := make([]models.TaskLog, 0, len(out.Items))
	for _, raw := range out.Items {
		var item models.TaskLog
		if err := attributevalue.UnmarshalMap(raw, &item); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, nil
}

func (r *DynamoRepository) PutPhysicianScheduleSlot(ctx context.Context, slot models.PhysicianScheduleSlot) error {
	item, err := attributevalue.MarshalMap(slot)
	if err != nil {
		return err
	}
	if r.schedulePKName != "" {
		item[r.schedulePKName] = &types.AttributeValueMemberS{Value: slot.PhysicianID}
	}
	if r.scheduleSKName != "" {
		item[r.scheduleSKName] = &types.AttributeValueMemberS{Value: fmt.Sprintf("%s#%s", slot.ScheduleDate, slot.SlotID)}
	}
	_, err = r.client.PutItem(ctx, &dynamodb.PutItemInput{TableName: aws.String(r.tableSchedules), Item: item})
	return err
}

func (r *DynamoRepository) ListPhysicianScheduleSlots(ctx context.Context, physicianID, date string) ([]models.PhysicianScheduleSlot, error) {
	if r.schedulePKName == "" || r.scheduleSKName == "" {
		return nil, fmt.Errorf("schedule key names not configured")
	}
	keyCondition := fmt.Sprintf("%s = :pid AND begins_with(%s, :date)", r.schedulePKName, r.scheduleSKName)
	out, err := r.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(r.tableSchedules),
		KeyConditionExpression: aws.String(keyCondition),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":pid":  &types.AttributeValueMemberS{Value: physicianID},
			":date": &types.AttributeValueMemberS{Value: date + "#"},
		},
	})
	if err != nil {
		return nil, err
	}

	items := make([]models.PhysicianScheduleSlot, 0, len(out.Items))
	for _, raw := range out.Items {
		var item models.PhysicianScheduleSlot
		if err := attributevalue.UnmarshalMap(raw, &item); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, nil
}

var _ Repository = (*DynamoRepository)(nil)
