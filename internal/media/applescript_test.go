package media

import (
	"testing"
)

func TestDecodeHexArtwork(t *testing.T) {
	fallback := []byte("default")

	tests := []struct {
		name     string
		input    string
		wantLen  int
		wantData bool // false means we expect fallback
	}{
		{
			name:     "empty string",
			input:    "",
			wantData: false,
		},
		{
			name:     "valid hex",
			input:    "48656C6C6F", // "Hello"
			wantLen:  5,
			wantData: true,
		},
		{
			name:     "applescript data wrapper with hex content",
			input:    "«data 48656C6C6F»",
			wantLen:  5,
			wantData: true,
		},
		{
			name:     "odd length hex",
			input:    "48656C6C6F0", // odd, should trim last char
			wantLen:  5,
			wantData: true,
		},
		{
			name:     "non-hex chars filtered to valid hex",
			input:    "missing value", // after filtering non-hex: "aae" -> 1 byte
			wantLen:  1,
			wantData: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := decodeHexArtwork(tt.input, fallback)
			if !tt.wantData {
				if string(result) != string(fallback) {
					t.Errorf("expected fallback, got %v", result)
				}
				return
			}
			if len(result) != tt.wantLen {
				t.Errorf("expected len %d, got %d", tt.wantLen, len(result))
			}
		})
	}
}

func TestTrackEqual(t *testing.T) {
	t1 := &Track{ID: "abc"}
	t2 := &Track{ID: "abc"}
	t3 := &Track{ID: "def"}

	if !t1.Equal(t2) {
		t.Error("same ID tracks should be equal")
	}
	if t1.Equal(t3) {
		t.Error("different ID tracks should not be equal")
	}
	if t1.Equal(nil) {
		t.Error("track should not equal nil")
	}

	var nilTrack *Track
	if !nilTrack.Equal(nil) {
		t.Error("nil should equal nil")
	}
}

func TestTrackDisplayTitle(t *testing.T) {
	tests := []struct {
		name  string
		track *Track
		want  string
	}{
		{"nil track", nil, "Not Playing"},
		{"with artist", &Track{Title: "Song", Artist: "Band"}, "Song by Band"},
		{"no artist", &Track{Title: "Song"}, "Song"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.track.DisplayTitle()
			if got != tt.want {
				t.Errorf("DisplayTitle() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestIsAllowedMediaRemoteSource(t *testing.T) {
	boolTrue := true
	boolFalse := false

	tests := []struct {
		name       string
		bundleID   string
		isMusicApp *bool
		want       bool
	}{
		{"known bundle", "com.apple.Music", nil, true},
		{"known Spotify", "com.spotify.client", nil, true},
		{"unknown bundle", "com.unknown.app", nil, false},
		{"empty bundle with isMusicApp true", "", &boolTrue, true},
		{"empty bundle with isMusicApp false", "", &boolFalse, false},
		{"empty bundle with nil isMusicApp", "", nil, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isAllowedMediaRemoteSource(tt.bundleID, tt.isMusicApp)
			if got != tt.want {
				t.Errorf("isAllowedMediaRemoteSource(%q, %v) = %v, want %v",
					tt.bundleID, tt.isMusicApp, got, tt.want)
			}
		})
	}
}
