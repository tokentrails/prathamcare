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
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	deps, err := app.NewDependencies(context.Background(), cfg)
	if err != nil {
		log.Fatalf("init dependencies: %v", err)
	}
	defer deps.Close()

	h := api.NewHandler(cfg)
	lambda.Start(func(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
		return h.Handle(ctx, req)
	})
}
