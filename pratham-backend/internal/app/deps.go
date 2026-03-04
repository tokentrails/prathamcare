package app

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/prathamcare/backend/internal/config"
	repoaurora "github.com/prathamcare/backend/internal/repositories/aurora"
	repodynamo "github.com/prathamcare/backend/internal/repositories/dynamo"
	repohealthlake "github.com/prathamcare/backend/internal/repositories/healthlake"
	reposearch "github.com/prathamcare/backend/internal/repositories/search"
	repostorage "github.com/prathamcare/backend/internal/repositories/storage"
)

type Dependencies struct {
	Aurora     *repoaurora.PgxRepository
	Dynamo     *repodynamo.DynamoRepository
	HealthLake *repohealthlake.HTTPRepository
	Storage    *repostorage.S3Repository
	Search     *reposearch.OpenSearchRepository
}

func NewDependencies(ctx context.Context, cfg config.Config) (*Dependencies, error) {
	deps := &Dependencies{}

	if cfg.AuroraDSN != "" {
		auroraCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
		auroraRepo, err := repoaurora.NewPgxRepository(auroraCtx, cfg.AuroraDSN)
		cancel()
		if err != nil {
			log.Printf("warning: aurora repo init failed; continuing without aurora: %v", err)
		} else {
			deps.Aurora = auroraRepo
		}
	}

	dynamoCtx, cancelDynamo := context.WithTimeout(ctx, 4*time.Second)
	dynamoRepo, err := repodynamo.NewDynamoRepository(dynamoCtx, repodynamo.Config{
		Region:         cfg.AWSRegion,
		TableSessions:  cfg.DynamoTableSessions,
		TableOfflineQ:  cfg.DynamoTableOfflineQ,
		TableTaskLogs:  cfg.DynamoTableTaskLogs,
		TableSchedules: cfg.DynamoTableSchedules,
		SchedulePKName: cfg.DynamoSchedulePKName,
		ScheduleSKName: cfg.DynamoScheduleSKName,
	})
	cancelDynamo()
	if err != nil {
		log.Printf("warning: dynamo repo init failed; continuing without dynamo: %v", err)
	} else {
		deps.Dynamo = dynamoRepo
	}

	storageCtx, cancelStorage := context.WithTimeout(ctx, 4*time.Second)
	storageRepo, err := repostorage.NewS3Repository(storageCtx, cfg.AWSRegion)
	cancelStorage()
	if err != nil {
		log.Printf("warning: s3 repo init failed; continuing without storage: %v", err)
	} else {
		deps.Storage = storageRepo
	}

	if cfg.HealthLakeEnabled && cfg.HealthLakeEndpoint != "" {
		hlCtx, cancelHealthLake := context.WithTimeout(ctx, 4*time.Second)
		hlRepo, err := repohealthlake.NewHTTPRepository(hlCtx, cfg.AWSRegion, cfg.HealthLakeEndpoint)
		cancelHealthLake()
		if err != nil {
			log.Printf("warning: healthlake repo init failed; continuing without healthlake: %v", err)
		} else {
			deps.HealthLake = hlRepo
		}
	} else if !cfg.HealthLakeEnabled {
		log.Printf("info: healthlake integration disabled by HEALTHLAKE_ENABLED=false")
	}

	if cfg.OpenSearchEndpoint != "" {
		searchCtx, cancelSearch := context.WithTimeout(ctx, 4*time.Second)
		searchRepo, err := reposearch.NewOpenSearchRepository(searchCtx, cfg.AWSRegion, cfg.OpenSearchEndpoint, "prathamcare-vectors")
		cancelSearch()
		if err != nil {
			log.Printf("warning: opensearch repo init failed; continuing without opensearch: %v", err)
		} else {
			deps.Search = searchRepo
		}
	}

	if deps.Aurora == nil && deps.Dynamo == nil && deps.Storage == nil && deps.HealthLake == nil && deps.Search == nil {
		return deps, fmt.Errorf("all dependencies failed to initialize")
	}
	return deps, nil
}

func (d *Dependencies) Close() {
	if d == nil {
		return
	}
	if d.Aurora != nil {
		d.Aurora.Close()
	}
}
