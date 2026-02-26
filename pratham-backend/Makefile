.PHONY: tidy build fmt test

tidy:
	go mod tidy

build:
	go build ./cmd/api

fmt:
	gofmt -w ./cmd ./internal

test:
	go test ./...
