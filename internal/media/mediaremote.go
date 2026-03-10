package media

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const (
	adapterDirname    = "mediaremote_adapter"
	adapterScript     = "mediaremote-adapter.pl"
	adapterFramework  = "MediaRemoteAdapter.framework"
	adapterTestClient = "MediaRemoteAdapterTestClient"
)

// AllowedMediaRemoteBundles is the set of bundle identifiers considered music apps.
var AllowedMediaRemoteBundles = map[string]bool{
	"com.apple.Music":          true,
	"com.spotify.client":       true,
	"com.tidal.desktop":        true,
	"com.deezer.DeezerDesktop": true,
	"com.ciderapp.Cider":       true,
	"com.voxapp.mac":           true,
}

// mediaRemotePayload matches the JSON output from the Perl adapter.
type mediaRemotePayload struct {
	Title                     string  `json:"title"`
	Artist                    string  `json:"artist"`
	Album                     string  `json:"album"`
	UniqueIdentifier          string  `json:"uniqueIdentifier"`
	ParentApplicationBundleID string  `json:"parentApplicationBundleIdentifier"`
	BundleIdentifier          string  `json:"bundleIdentifier"`
	IsMusicApp                *bool   `json:"isMusicApp"`
	ArtworkData               *string `json:"artworkData"`
}

// MediaRemoteSource retrieves now-playing info via the vendored MediaRemote adapter.
type MediaRemoteSource struct {
	adapterRoot    string
	scriptPath     string
	frameworkPath  string
	testClientPath string
	defaultArtwork []byte
	fallback       *AppleScriptSource // fallback to Music AppleScript
}

// NewMediaRemoteSource creates a MediaRemote source. adapterRoot is the path
// to the mediaremote_adapter directory. If empty, it resolves automatically by
// checking (in order):
//  1. Next to the executable (for development / standalone binary)
//  2. ../Resources/mediaremote_adapter (for .app bundles: Contents/MacOS/../Resources/)
//  3. Relative to the working directory (fallback)
func NewMediaRemoteSource(adapterRoot string, defaultArtwork []byte) (*MediaRemoteSource, error) {
	if adapterRoot == "" {
		adapterRoot = resolveAdapterRoot()
	}

	s := &MediaRemoteSource{
		adapterRoot:    adapterRoot,
		scriptPath:     filepath.Join(adapterRoot, adapterScript),
		frameworkPath:  filepath.Join(adapterRoot, adapterFramework),
		testClientPath: filepath.Join(adapterRoot, adapterTestClient),
		defaultArtwork: defaultArtwork,
		fallback:       NewAppleScriptSource("Music", defaultArtwork),
	}

	if err := s.ensureAdapterFiles(); err != nil {
		return nil, err
	}

	return s, nil
}

func (s *MediaRemoteSource) Name() string { return "MediaRemote" }

func (s *MediaRemoteSource) NowPlaying(ctx context.Context) (*Track, error) {
	track, err := s.fetchMediaRemote(ctx)
	if err != nil {
		slog.Warn("MediaRemote fetch failed, falling back to Music AppleScript", "error", err)
		return s.fallback.NowPlaying(ctx)
	}
	if track == nil {
		slog.Warn("MediaRemote returned no active track, falling back to Music AppleScript")
		return s.fallback.NowPlaying(ctx)
	}
	return track, nil
}

func (s *MediaRemoteSource) fetchMediaRemote(ctx context.Context) (*Track, error) {
	cmd := exec.CommandContext(ctx, "perl",
		s.scriptPath,
		s.frameworkPath,
		s.testClientPath,
		"get",
	)

	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("mediaremote adapter: %w", err)
	}

	output := strings.TrimSpace(string(out))
	if output == "" {
		return nil, nil
	}

	var payload mediaRemotePayload
	if err := json.Unmarshal([]byte(output), &payload); err != nil {
		return nil, fmt.Errorf("parse mediaremote output: %w", err)
	}

	if payload.Title == "" {
		return nil, nil
	}

	// Check if source is an allowed music app
	bundleID := payload.ParentApplicationBundleID
	if bundleID == "" {
		bundleID = payload.BundleIdentifier
	}
	if !isAllowedMediaRemoteSource(bundleID, payload.IsMusicApp) {
		return nil, fmt.Errorf("ignoring non-music app source: %s", bundleID)
	}

	// Decode artwork
	artwork := s.defaultArtwork
	if payload.ArtworkData != nil && *payload.ArtworkData != "" {
		decoded, err := base64.StdEncoding.DecodeString(*payload.ArtworkData)
		if err != nil {
			slog.Warn("failed to decode MediaRemote artwork", "error", err)
		} else {
			artwork = decoded
		}
	}

	trackID := payload.UniqueIdentifier
	if trackID == "" {
		trackID = fmt.Sprintf("%s:%s:%s", payload.Title, payload.Artist, payload.Album)
	}

	return &Track{
		Title:   payload.Title,
		Artist:  payload.Artist,
		Album:   payload.Album,
		ID:      trackID,
		Artwork: artwork,
	}, nil
}

func (s *MediaRemoteSource) ensureAdapterFiles() error {
	var missing []string
	for _, p := range []string{s.scriptPath, s.frameworkPath, s.testClientPath} {
		if _, err := os.Stat(p); err != nil {
			missing = append(missing, p)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("missing MediaRemote adapter assets: %s", strings.Join(missing, ", "))
	}
	return nil
}

// resolveAdapterRoot searches for the mediaremote_adapter directory in multiple
// locations to handle different execution contexts (development, standalone binary,
// .app bundle).
func resolveAdapterRoot() string {
	// Candidate directories, in priority order
	var candidates []string

	exePath, err := os.Executable()
	if err == nil {
		exeDir := filepath.Dir(exePath)
		// 1. Next to executable (development / standalone binary)
		candidates = append(candidates, filepath.Join(exeDir, adapterDirname))
		// 2. .app bundle: Contents/MacOS/../Resources/mediaremote_adapter
		candidates = append(candidates, filepath.Join(exeDir, "..", "Resources", adapterDirname))
	}

	// 3. Relative to working directory (fallback for `go run`)
	candidates = append(candidates, adapterDirname)

	for _, c := range candidates {
		if info, err := os.Stat(c); err == nil && info.IsDir() {
			slog.Debug("resolved mediaremote_adapter", "path", c)
			return c
		}
	}

	// None found; return the bare name and let ensureAdapterFiles produce a clear error
	return adapterDirname
}

func isAllowedMediaRemoteSource(bundleID string, isMusicApp *bool) bool {
	if AllowedMediaRemoteBundles[bundleID] {
		return true
	}
	if bundleID == "" && isMusicApp != nil {
		return *isMusicApp
	}
	return false
}
