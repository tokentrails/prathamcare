package main

import (
	"context"
	"log"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/prathamcare/backend/internal/app"
	"github.com/prathamcare/backend/internal/api"
	"github.com/prathamcare/backend/internal/config"
)

func main() {
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
