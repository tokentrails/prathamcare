package app

import (
	"context"
	"fmt"

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
		auroraRepo, err := repoaurora.NewPgxRepository(ctx, cfg.AuroraDSN)
		if err != nil {
			return nil, fmt.Errorf("aurora repo: %w", err)
		}
		deps.Aurora = auroraRepo
	}

	dynamoRepo, err := repodynamo.NewDynamoRepository(ctx, repodynamo.Config{
		Region:         cfg.AWSRegion,
		TableSessions:  cfg.DynamoTableSessions,
		TableOfflineQ:  cfg.DynamoTableOfflineQ,
		TableTaskLogs:  cfg.DynamoTableTaskLogs,
		TableSchedules: cfg.DynamoTableSchedules,
		SchedulePKName: cfg.DynamoSchedulePKName,
		ScheduleSKName: cfg.DynamoScheduleSKName,
	})
	if err != nil {
		return nil, fmt.Errorf("dynamo repo: %w", err)
	}
	deps.Dynamo = dynamoRepo

	storageRepo, err := repostorage.NewS3Repository(ctx, cfg.AWSRegion)
	if err != nil {
		return nil, fmt.Errorf("s3 repo: %w", err)
	}
	deps.Storage = storageRepo

	if cfg.HealthLakeEndpoint != "" {
		hlRepo, err := repohealthlake.NewHTTPRepository(ctx, cfg.AWSRegion, cfg.HealthLakeEndpoint)
		if err != nil {
			return nil, fmt.Errorf("healthlake repo: %w", err)
		}
		deps.HealthLake = hlRepo
	}

	if cfg.OpenSearchEndpoint != "" {
		searchRepo, err := reposearch.NewOpenSearchRepository(ctx, cfg.AWSRegion, cfg.OpenSearchEndpoint, "prathamcare-vectors")
		if err != nil {
			return nil, fmt.Errorf("opensearch repo: %w", err)
		}
		deps.Search = searchRepo
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
