// Package transport implements the WebSocket protocol and client for cbNP.
package transport

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"
)

// Message types.
const (
	TypeUpdate    = "update"
	TypeHeartbeat = "heartbeat"
)

// ProtocolVersion is the current protocol version.
const ProtocolVersion = "1"

// Envelope wraps every message sent over the WebSocket.
type Envelope struct {
	Type    string          `json:"type"`
	Auth    string          `json:"auth"`
	Version string          `json:"version"`
	SentAt  time.Time       `json:"sent_at"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

// UpdatePayload carries track information.
type UpdatePayload struct {
	Title   string `json:"title"`
	Artist  string `json:"artist"`
	Album   string `json:"album"`
	Artwork string `json:"artwork"` // base64-encoded
	TrackID string `json:"track_id"`
	Source  string `json:"source"`
}

// NewUpdateEnvelope creates a fully-formed update message.
func NewUpdateEnvelope(auth string, payload UpdatePayload) ([]byte, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal update payload: %w", err)
	}

	env := Envelope{
		Type:    TypeUpdate,
		Auth:    auth,
		Version: ProtocolVersion,
		SentAt:  time.Now().UTC(),
		Payload: raw,
	}

	data, err := json.Marshal(env)
	if err != nil {
		return nil, fmt.Errorf("marshal envelope: %w", err)
	}
	return data, nil
}

// NewHeartbeatEnvelope creates a heartbeat message.
func NewHeartbeatEnvelope(auth string) ([]byte, error) {
	env := Envelope{
		Type:    TypeHeartbeat,
		Auth:    auth,
		Version: ProtocolVersion,
		SentAt:  time.Now().UTC(),
	}

	data, err := json.Marshal(env)
	if err != nil {
		return nil, fmt.Errorf("marshal heartbeat: %w", err)
	}
	return data, nil
}

// ParseEnvelope deserializes an envelope from JSON.
func ParseEnvelope(data []byte) (*Envelope, error) {
	var env Envelope
	if err := json.Unmarshal(data, &env); err != nil {
		return nil, fmt.Errorf("unmarshal envelope: %w", err)
	}
	return &env, nil
}

// ParseUpdatePayload extracts the update payload from an envelope.
func ParseUpdatePayload(env *Envelope) (*UpdatePayload, error) {
	if env.Type != TypeUpdate {
		return nil, fmt.Errorf("expected type %q, got %q", TypeUpdate, env.Type)
	}
	var p UpdatePayload
	if err := json.Unmarshal(env.Payload, &p); err != nil {
		return nil, fmt.Errorf("unmarshal update payload: %w", err)
	}
	return &p, nil
}

// EncodeArtwork converts raw bytes to base64 for the protocol.
func EncodeArtwork(data []byte) string {
	if len(data) == 0 {
		return ""
	}
	return base64.StdEncoding.EncodeToString(data)
}
