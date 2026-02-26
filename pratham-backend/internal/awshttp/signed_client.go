package awshttp

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	v4 "github.com/aws/aws-sdk-go-v2/aws/signer/v4"
)

type SignedClient struct {
	cfg        aws.Config
	signer     *v4.Signer
	httpClient *http.Client
}

func NewSignedClient(ctx context.Context, region string) (*SignedClient, error) {
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}
	return &SignedClient{
		cfg:        cfg,
		signer:     v4.NewSigner(),
		httpClient: &http.Client{Timeout: 15 * time.Second},
	}, nil
}

func (c *SignedClient) Do(ctx context.Context, service, method, url string, body []byte, contentType string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, method, url, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	payloadHash, err := v4.HashPayload(bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	creds, err := c.cfg.Credentials.Retrieve(ctx)
	if err != nil {
		return nil, err
	}
	if err := c.signer.SignHTTP(ctx, creds, req, payloadHash, service, c.cfg.Region, time.Now().UTC()); err != nil {
		return nil, err
	}
	return c.httpClient.Do(req)
}

func ReadJSONBody(resp *http.Response) ([]byte, error) {
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("http status %d: %s", resp.StatusCode, string(b))
	}
	return b, nil
}
