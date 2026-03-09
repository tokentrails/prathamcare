package main

import (
	"context"
	"log"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/prathamcare/backend/internal/api"
	"github.com/prathamcare/backend/internal/app"
	"github.com/prathamcare/backend/internal/config"
)

const buildMarker = "2026-03-09-translate-summary-log-v1"

func main() {
	log.Printf("startup: build_marker=%s", buildMarker)
	log.Printf("startup: loading config")
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	log.Printf("startup: initializing dependencies")
	deps, err := app.NewDependencies(context.Background(), cfg)
	if err != nil {
		log.Fatalf("init dependencies: %v", err)
	}
	defer deps.Close()

	log.Printf("startup: initializing handler")
	h := api.NewHandler(cfg, deps)
	log.Printf("startup: lambda ready")
	lambda.Start(func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
		return h.Handle(ctx, req)
	})
}
