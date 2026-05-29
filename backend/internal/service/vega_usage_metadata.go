package service

import (
	"context"
	"strings"
	"unicode"
)

const (
	VegaHeaderScanID    = "X-Vega-Scan-ID"
	VegaHeaderProjectID = "X-Vega-Project-ID"
	VegaHeaderRequestID = "X-Vega-Request-ID"
	VegaHeaderRunnerID  = "X-Vega-Runner-ID"

	maxVegaMetadataValueLen = 128
)

type vegaUsageMetadataContextKey struct{}

// VegaUsageMetadata carries Vega-side identifiers through the gateway into usage_logs.
type VegaUsageMetadata struct {
	ScanID    string
	ProjectID string
	RequestID string
	RunnerID  string
}

func (m VegaUsageMetadata) Empty() bool {
	return m.ScanID == "" && m.ProjectID == "" && m.RequestID == "" && m.RunnerID == ""
}

func VegaUsageMetadataFromHeader(getHeader func(string) string) VegaUsageMetadata {
	if getHeader == nil {
		return VegaUsageMetadata{}
	}
	return VegaUsageMetadata{
		ScanID:    sanitizeVegaMetadataValue(getHeader(VegaHeaderScanID)),
		ProjectID: sanitizeVegaMetadataValue(getHeader(VegaHeaderProjectID)),
		RequestID: sanitizeVegaMetadataValue(getHeader(VegaHeaderRequestID)),
		RunnerID:  sanitizeVegaMetadataValue(getHeader(VegaHeaderRunnerID)),
	}
}

func WithVegaUsageMetadata(ctx context.Context, metadata VegaUsageMetadata) context.Context {
	if ctx == nil {
		ctx = context.Background()
	}
	if metadata.Empty() {
		return ctx
	}
	return context.WithValue(ctx, vegaUsageMetadataContextKey{}, metadata)
}

func VegaUsageMetadataFromContext(ctx context.Context) VegaUsageMetadata {
	if ctx == nil {
		return VegaUsageMetadata{}
	}
	metadata, _ := ctx.Value(vegaUsageMetadataContextKey{}).(VegaUsageMetadata)
	return metadata
}

func sanitizeVegaMetadataValue(value string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return ""
	}
	out := strings.Builder{}
	out.Grow(len(value))
	for _, r := range value {
		if r > unicode.MaxASCII || unicode.IsControl(r) {
			continue
		}
		out.WriteRune(r)
		if out.Len() >= maxVegaMetadataValueLen {
			break
		}
	}
	return out.String()
}
