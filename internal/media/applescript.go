package media

import (
	"context"
	"encoding/hex"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

const separator = "␟"

// AppleScriptSource retrieves now-playing info from Apple Music or Spotify via osascript.
type AppleScriptSource struct {
	player         string // "Music" or "Spotify"
	defaultArtwork []byte
	httpClient     *http.Client
}

// NewAppleScriptSource creates a source for the given player ("Music" or "Spotify").
func NewAppleScriptSource(player string, defaultArtwork []byte) *AppleScriptSource {
	return &AppleScriptSource{
		player:         player,
		defaultArtwork: defaultArtwork,
		httpClient: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

func (s *AppleScriptSource) Name() string { return s.player }

func (s *AppleScriptSource) NowPlaying(ctx context.Context) (*Track, error) {
	script := s.buildScript()

	cmd := exec.CommandContext(ctx, "osascript", "-e", script)
	out, err := cmd.Output()
	if err != nil {
		if ctx.Err() != nil {
			return nil, fmt.Errorf("applescript timed out: %w", ctx.Err())
		}
		return nil, fmt.Errorf("applescript: %w", err)
	}

	output := strings.TrimSpace(string(out))
	if output == "" {
		return nil, nil // not playing
	}

	return s.parseOutput(output)
}

func (s *AppleScriptSource) buildScript() string {
	var artworkExpr string
	if s.player == "Spotify" {
		artworkExpr = "get artwork url of current track"
	} else {
		artworkExpr = "data of artwork 1 of current track"
	}

	// Build an AppleScript that checks if the app is running, then fetches track info.
	// Fields are separated by ␟ (unit separator).
	return fmt.Sprintf(`
if application "%s" is running then
	tell application "%s"
		set trackName to name of current track
		set trackArtist to artist of current track
		set trackAlbum to album of current track
		set trackId to id of current track as string
		try
			set artworkData to %s
		on error
			set artworkData to "missing value"
		end try
		set trackName to trackName & "%s"
		set trackArtist to trackArtist & "%s"
		set trackAlbum to trackAlbum & "%s"
		set trackId to trackId & "%s"
		return {trackName, trackArtist, trackAlbum, trackId, artworkData}
	end tell
end if
`, s.player, s.player, artworkExpr, separator, separator, separator, separator)
}

func (s *AppleScriptSource) parseOutput(output string) (*Track, error) {
	// Output format: "Title␟, Artist␟, Album␟, ID␟, ArtworkData"
	parts := strings.SplitN(output, separator+", ", 4)
	if len(parts) < 4 {
		return nil, fmt.Errorf("unexpected applescript output format: got %d parts", len(parts))
	}

	// The last part contains "ID␟, ArtworkData" - split once more
	lastParts := strings.SplitN(parts[3], separator+", ", 2)
	if len(lastParts) < 2 {
		return nil, fmt.Errorf("unexpected applescript output format: missing artwork in last segment")
	}

	title := parts[0]
	artist := parts[1]
	album := parts[2]
	id := lastParts[0]
	rawArtwork := lastParts[1]

	artwork := s.extractArtwork(rawArtwork)

	return &Track{
		Title:   title,
		Artist:  artist,
		Album:   album,
		ID:      id,
		Artwork: artwork,
	}, nil
}

// extractArtwork normalizes raw artwork data from AppleScript.
// It handles HTTP URLs, hex-encoded AppleScript «data» blobs, and missing values.
func (s *AppleScriptSource) extractArtwork(raw string) []byte {
	raw = strings.TrimSpace(raw)
	if raw == "" || raw == "missing value" {
		return s.defaultArtwork
	}

	// HTTP URL (Spotify artwork)
	if strings.HasPrefix(raw, "http") {
		data, err := s.fetchArtworkURL(raw)
		if err != nil {
			slog.Warn("failed to fetch artwork URL", "url", raw, "error", err)
			return s.defaultArtwork
		}
		return data
	}

	// Hex-encoded AppleScript data blob: «data tdta...»
	return decodeHexArtwork(raw, s.defaultArtwork)
}

func (s *AppleScriptSource) fetchArtworkURL(url string) ([]byte, error) {
	resp, err := s.httpClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("artwork HTTP %d", resp.StatusCode)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read artwork body: %w", err)
	}
	return data, nil
}

var nonHexRegex = regexp.MustCompile(`[^0-9A-Fa-f]`)

// decodeHexArtwork strips AppleScript «data ...» wrapper and decodes hex.
func decodeHexArtwork(raw string, fallback []byte) []byte {
	cleaned := strings.ReplaceAll(raw, "«data ", "")
	cleaned = strings.ReplaceAll(cleaned, "»", "")
	cleaned = nonHexRegex.ReplaceAllString(cleaned, "")

	// Ensure even length
	if len(cleaned)%2 != 0 {
		cleaned = cleaned[:len(cleaned)-1]
	}

	if cleaned == "" {
		return fallback
	}

	data, err := hex.DecodeString(cleaned)
	if err != nil {
		slog.Warn("failed to decode hex artwork", "error", err)
		return fallback
	}
	return data
}
