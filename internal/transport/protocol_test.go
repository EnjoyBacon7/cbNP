package transport

import (
	"encoding/json"
	"testing"
	"time"
)

func TestNewUpdateEnvelope(t *testing.T) {
	payload := UpdatePayload{
		Title:   "Test Song",
		Artist:  "Test Artist",
		Album:   "Test Album",
		Artwork: "base64data",
		TrackID: "123",
		Source:  "Music",
	}

	data, err := NewUpdateEnvelope("my-token", payload)
	if err != nil {
		t.Fatalf("NewUpdateEnvelope: %v", err)
	}

	env, err := ParseEnvelope(data)
	if err != nil {
		t.Fatalf("ParseEnvelope: %v", err)
	}

	if env.Type != TypeUpdate {
		t.Errorf("type: got %q, want %q", env.Type, TypeUpdate)
	}
	if env.Auth != "my-token" {
		t.Errorf("auth: got %q, want %q", env.Auth, "my-token")
	}
	if env.Version != ProtocolVersion {
		t.Errorf("version: got %q, want %q", env.Version, ProtocolVersion)
	}
	if env.SentAt.IsZero() {
		t.Error("sent_at should not be zero")
	}

	p, err := ParseUpdatePayload(env)
	if err != nil {
		t.Fatalf("ParseUpdatePayload: %v", err)
	}
	if p.Title != "Test Song" {
		t.Errorf("title: got %q, want %q", p.Title, "Test Song")
	}
	if p.Artist != "Test Artist" {
		t.Errorf("artist: got %q, want %q", p.Artist, "Test Artist")
	}
	if p.TrackID != "123" {
		t.Errorf("track_id: got %q, want %q", p.TrackID, "123")
	}
	if p.Source != "Music" {
		t.Errorf("source: got %q, want %q", p.Source, "Music")
	}
}

func TestNewHeartbeatEnvelope(t *testing.T) {
	data, err := NewHeartbeatEnvelope("my-token")
	if err != nil {
		t.Fatalf("NewHeartbeatEnvelope: %v", err)
	}

	env, err := ParseEnvelope(data)
	if err != nil {
		t.Fatalf("ParseEnvelope: %v", err)
	}

	if env.Type != TypeHeartbeat {
		t.Errorf("type: got %q, want %q", env.Type, TypeHeartbeat)
	}
	if env.Auth != "my-token" {
		t.Errorf("auth: got %q, want %q", env.Auth, "my-token")
	}
	if env.Version != ProtocolVersion {
		t.Errorf("version: got %q, want %q", env.Version, ProtocolVersion)
	}
	if len(env.Payload) != 0 {
		t.Errorf("heartbeat should have no payload, got %s", env.Payload)
	}
}

func TestRoundTripJSON(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Second)
	original := Envelope{
		Type:    TypeUpdate,
		Auth:    "token123",
		Version: "1",
		SentAt:  now,
		Payload: json.RawMessage(`{"title":"Song","artist":"Artist"}`),
	}

	data, err := json.Marshal(original)
	if err != nil {
		t.Fatal(err)
	}

	var decoded Envelope
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatal(err)
	}

	if decoded.Type != original.Type {
		t.Errorf("type mismatch: %q vs %q", decoded.Type, original.Type)
	}
	if decoded.Auth != original.Auth {
		t.Errorf("auth mismatch: %q vs %q", decoded.Auth, original.Auth)
	}
	if !decoded.SentAt.Equal(original.SentAt) {
		t.Errorf("sent_at mismatch: %v vs %v", decoded.SentAt, original.SentAt)
	}
}

func TestEncodeArtwork(t *testing.T) {
	if got := EncodeArtwork(nil); got != "" {
		t.Errorf("nil should encode to empty, got %q", got)
	}
	if got := EncodeArtwork([]byte{}); got != "" {
		t.Errorf("empty should encode to empty, got %q", got)
	}
	if got := EncodeArtwork([]byte("hello")); got == "" {
		t.Error("non-empty should produce non-empty base64")
	}
}

func TestParseUpdatePayloadWrongType(t *testing.T) {
	env := &Envelope{Type: TypeHeartbeat}
	_, err := ParseUpdatePayload(env)
	if err == nil {
		t.Error("expected error for wrong type")
	}
}
