package config

import (
	"errors"
	"fmt"
	"os"
)

// Config centralizes all runtime parameters for the Lambda.
type Config struct {
	AppEnv               string
	AWSRegion            string
	AuroraDSNSecretARN   string
	AuroraDSN            string
	RDSProxyEndpoint     string
	DynamoTableSessions  string
	DynamoTableOfflineQ  string
	DynamoTableTaskLogs  string
	DynamoTableSchedules string
	DynamoSchedulePKName string
	DynamoScheduleSKName string
	HealthLakeEndpoint   string
	S3DocumentsBucket    string
	S3VoiceBucket        string
	OpenSearchEndpoint   string
	CognitoUserPoolID    string
	CognitoClientID      string
	CognitoIssuer        string
	CognitoJWKSURL       string
}

func Load() (Config, error) {
	cfg := Config{
		AppEnv:               getEnv("APP_ENV", "dev"),
		AWSRegion:            getEnv("AWS_REGION", "ap-south-1"),
		AuroraDSNSecretARN:   os.Getenv("AURORA_DSN_SECRET_ARN"),
		AuroraDSN:            os.Getenv("AURORA_DSN"),
		RDSProxyEndpoint:     os.Getenv("RDS_PROXY_ENDPOINT"),
		DynamoTableSessions:  getEnv("DDB_TABLE_SESSIONS", "prathamcare-sessions"),
		DynamoTableOfflineQ:  getEnv("DDB_TABLE_OFFLINE_QUEUE", "prathamcare-offline-queue"),
		DynamoTableTaskLogs:  getEnv("DDB_TABLE_TASK_LOGS", "prathamcare-task-logs"),
		DynamoTableSchedules: getEnv("DDB_TABLE_SCHEDULES", "prathamcare-schedules"),
		DynamoSchedulePKName: getEnv("DDB_SCHEDULE_PK", "physician_id"),
		DynamoScheduleSKName: getEnv("DDB_SCHEDULE_SK", "schedule_slot"),
		HealthLakeEndpoint:   os.Getenv("HEALTHLAKE_FHIR_ENDPOINT"),
		S3DocumentsBucket:    getEnv("S3_BUCKET_DOCUMENTS", "prathamcare-medical-documents"),
		S3VoiceBucket:        getEnv("S3_BUCKET_VOICE", "prathamcare-voice-recordings"),
		OpenSearchEndpoint:   os.Getenv("OPENSEARCH_ENDPOINT"),
		CognitoUserPoolID:    os.Getenv("COGNITO_USER_POOL_ID"),
		CognitoClientID:      os.Getenv("COGNITO_CLIENT_ID"),
	}

	if cfg.AWSRegion == "" {
		return Config{}, errors.New("AWS_REGION is required")
	}
	if cfg.CognitoUserPoolID != "" {
		cfg.CognitoIssuer = fmt.Sprintf("https://cognito-idp.%s.amazonaws.com/%s", cfg.AWSRegion, cfg.CognitoUserPoolID)
		cfg.CognitoJWKSURL = cfg.CognitoIssuer + "/.well-known/jwks.json"
	}
	return cfg, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
