package app

import (
	"context"
	"testing"
	"time"

	"github.com/KinanLak/klNP/internal/config"
	"github.com/KinanLak/klNP/internal/media"
)

// mockSource implements media.Source for testing.
type mockSource struct {
	name  string
	track *media.Track
	err   error
}

func (m *mockSource) Name() string { return m.name }

func (m *mockSource) NowPlaying(_ context.Context) (*media.Track, error) {
	return m.track, m.err
}

func TestAppPollOnlyOnChange(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Interval = 100 * time.Millisecond
	cfg.Heartbeat = 10 * time.Second
	cfg.Endpoint = "ws://127.0.0.1:1" // won't connect, that's fine

	src := &mockSource{
		name: "TestSource",
		track: &media.Track{
			Title:  "Test Song",
			Artist: "Test Artist",
			ID:     "test-123",
		},
	}

	a := New(cfg, src, "test")

	// Test that poll works without tray (headless)
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()

	a.poll(ctx)

	if a.lastTrack == nil {
		t.Fatal("expected lastTrack to be set after poll")
	}
	if a.lastTrack.Title != "Test Song" {
		t.Errorf("expected title 'Test Song', got %q", a.lastTrack.Title)
	}

	// Second poll with same track should not change lastTrack pointer
	prev := a.lastTrack
	a.poll(ctx)
	if a.lastTrack != prev {
		t.Error("lastTrack should not change when track ID is the same")
	}
}

func TestAppPollNewTrack(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Endpoint = "ws://127.0.0.1:1"

	src := &mockSource{
		name: "TestSource",
		track: &media.Track{
			Title:  "Song A",
			Artist: "Artist A",
			ID:     "a-1",
		},
	}

	a := New(cfg, src, "test")

	ctx := context.Background()
	a.poll(ctx)

	if a.lastTrack.Title != "Song A" {
		t.Fatal("expected Song A")
	}

	// Change the track
	src.track = &media.Track{
		Title:  "Song B",
		Artist: "Artist B",
		ID:     "b-2",
	}

	a.poll(ctx)

	if a.lastTrack.Title != "Song B" {
		t.Errorf("expected Song B after track change, got %q", a.lastTrack.Title)
	}
}
