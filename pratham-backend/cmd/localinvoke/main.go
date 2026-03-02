package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/prathamcare/backend/internal/api"
	"github.com/prathamcare/backend/internal/app"
	"github.com/prathamcare/backend/internal/config"
)

func main() {
	eventPath := flag.String("event", "", "path to APIGatewayV2HTTPRequest JSON file")
	flag.Parse()

	if *eventPath == "" {
		log.Fatal("missing required -event <path>")
	}

	// Best-effort .env load for local runs; existing process env still wins.
	_ = loadDotEnv(".env")

	raw, err := os.ReadFile(*eventPath)
	if err != nil {
		log.Fatalf("read event file: %v", err)
	}

	var req events.APIGatewayV2HTTPRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		log.Fatalf("parse event json: %v", err)
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	deps, err := app.NewDependencies(context.Background(), cfg)
	if err != nil {
		log.Fatalf("init dependencies: %v", err)
	}
	defer deps.Close()

	h := api.NewHandler(cfg, deps)
	resp, err := h.Handle(context.Background(), req)
	if err != nil {
		log.Fatalf("invoke handler: %v", err)
	}

	out, _ := json.MarshalIndent(resp, "", "  ")
	fmt.Println(string(out))
}

func loadDotEnv(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := strings.TrimSpace(parts[0])
		val := strings.TrimSpace(parts[1])
		if key == "" {
			continue
		}
		// Respect explicitly set environment variables.
		if _, exists := os.LookupEnv(key); exists {
			continue
		}
		_ = os.Setenv(key, val)
	}
	return scanner.Err()
}
