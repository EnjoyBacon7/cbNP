// Package media provides interfaces and implementations for retrieving
// now-playing track information from macOS media sources.
package media

import "context"

// Track represents the currently playing track.
type Track struct {
	Title   string
	Artist  string
	Album   string
	ID      string
	Artwork []byte // raw image bytes (not base64)
}

// Equal reports whether two tracks represent the same playing item.
func (t *Track) Equal(other *Track) bool {
	if t == nil && other == nil {
		return true
	}
	if t == nil || other == nil {
		return false
	}
	return t.ID == other.ID
}

// DisplayTitle returns a human-readable "Title by Artist" string.
func (t *Track) DisplayTitle() string {
	if t == nil {
		return "Not Playing"
	}
	if t.Artist != "" {
		return t.Title + " by " + t.Artist
	}
	return t.Title
}

// Source retrieves now-playing information from a media player.
type Source interface {
	// Name returns the source identifier (e.g. "Music", "Spotify", "MediaRemote").
	Name() string
	// NowPlaying fetches the current track. Returns nil if nothing is playing.
	NowPlaying(ctx context.Context) (*Track, error)
}
