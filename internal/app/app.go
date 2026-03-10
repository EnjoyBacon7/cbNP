// Package app is the main orchestrator that ties media polling, WebSocket transport,
// and the system tray together.
package app

import (
	"context"
	"log/slog"
	"time"

	"fyne.io/systray"

	"github.com/KinanLak/klNP/internal/config"
	"github.com/KinanLak/klNP/internal/media"
	"github.com/KinanLak/klNP/internal/transport"
	"github.com/KinanLak/klNP/internal/tray"
)

// App orchestrates the poll loop, heartbeat, WebSocket client, and tray.
type App struct {
	cfg    config.Config
	source media.Source
	client *transport.Client
	tray   *tray.Tray
	events tray.Events

	lastTrack *media.Track
	version   string
}

// New creates a new App.
func New(cfg config.Config, source media.Source, version string) *App {
	return &App{
		cfg:     cfg,
		source:  source,
		version: version,
		events:  tray.NewEvents(),
	}
}

// Events returns the tray events for wiring with systray.Run.
func (a *App) Events() tray.Events {
	return a.events
}

// SetupTray initializes the system tray. Must be called from systray.Run's onReady.
func (a *App) SetupTray() {
	a.tray = tray.Setup(a.version, a.cfg.Source, a.events)
}

// Run is the main event loop. It blocks until ctx is canceled.
func (a *App) Run(ctx context.Context) {
	// Start WebSocket client
	a.client = transport.NewClient(a.cfg.Endpoint, a.cfg.Token)
	go a.client.Run(ctx)

	// Start config file watcher
	configCh, err := config.Watch(ctx)
	if err != nil {
		slog.Warn("could not watch config file, auto-reload disabled", "error", err)
		// Use a nil channel so the select case is never triggered
		configCh = nil
	}

	pollTicker := time.NewTicker(a.cfg.Interval)
	defer pollTicker.Stop()

	heartbeatTicker := time.NewTicker(a.cfg.Heartbeat)
	defer heartbeatTicker.Stop()

	// Do an initial poll immediately
	a.poll(ctx)

	for {
		select {
		case <-ctx.Done():
			a.client.Close()
			systray.Quit()
			return

		case <-pollTicker.C:
			a.poll(ctx)

		case <-heartbeatTicker.C:
			a.sendHeartbeat()

		case state := <-a.client.State():
			slog.Info("connection state changed", "state", state.String())
			if a.tray != nil {
				a.tray.SetConnectionState(state.String())
			}
			// Poll immediately on (re)connect so the server gets current data fast
			if state == transport.StateConnected {
				a.lastTrack = nil // force re-send
				a.poll(ctx)
			}

		case newCfg := <-configCh:
			a.applyConfig(ctx, newCfg, pollTicker, heartbeatTicker)

		case <-a.events.UpdateNow:
			slog.Info("manual update requested")
			a.poll(ctx)

		case src := <-a.events.SourceChange:
			a.handleSourceChange(ctx, src)

		case <-a.events.OpenConfig:
			slog.Info("config file opened for editing")

		case <-a.events.Quit:
			slog.Info("quit requested")
			a.client.Close()
			systray.Quit()
			return
		}
	}
}

func (a *App) poll(ctx context.Context) {
	pollCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	track, err := a.source.NowPlaying(pollCtx)
	if err != nil {
		slog.Error("failed to get now playing", "source", a.source.Name(), "error", err)
		if a.tray != nil {
			a.tray.SetTrackTitle("Error fetching track")
		}
		return
	}

	if track == nil {
		if a.tray != nil {
			a.tray.SetTrackTitle("Not Playing")
		}
		return
	}

	// Update tray display
	if a.tray != nil {
		a.tray.SetTrackTitle(track.DisplayTitle())
	}

	// Only send update if track changed (fix: don't send every interval)
	if a.lastTrack != nil && a.lastTrack.Equal(track) {
		return
	}

	a.lastTrack = track
	a.sendUpdate(track)
}

func (a *App) sendUpdate(track *media.Track) {
	if a.client == nil || a.client.CurrentState() != transport.StateConnected {
		slog.Debug("skipping update, not connected")
		return
	}

	payload := transport.UpdatePayload{
		Title:   track.Title,
		Artist:  track.Artist,
		Album:   track.Album,
		Artwork: transport.EncodeArtwork(track.Artwork),
		TrackID: track.ID,
		Source:  a.source.Name(),
	}

	msg, err := transport.NewUpdateEnvelope(a.cfg.Token, payload)
	if err != nil {
		slog.Error("failed to create update envelope", "error", err)
		return
	}

	a.client.Send(msg)
	slog.Info("sent update", "title", track.Title, "artist", track.Artist)
}

func (a *App) sendHeartbeat() {
	if a.client == nil || a.client.CurrentState() != transport.StateConnected {
		slog.Debug("skipping heartbeat, not connected")
		return
	}

	msg, err := transport.NewHeartbeatEnvelope(a.cfg.Token)
	if err != nil {
		slog.Error("failed to create heartbeat envelope", "error", err)
		return
	}

	a.client.Send(msg)
	slog.Debug("sent heartbeat")
}

// applyConfig applies a newly loaded config, updating timers, client, and source as needed.
func (a *App) applyConfig(ctx context.Context, newCfg config.Config, pollTicker, heartbeatTicker *time.Ticker) {
	old := a.cfg
	a.cfg = newCfg

	// Update poll interval
	if newCfg.Interval != old.Interval {
		pollTicker.Reset(newCfg.Interval)
		slog.Info("poll interval updated", "interval", newCfg.Interval)
	}

	// Update heartbeat interval
	if newCfg.Heartbeat != old.Heartbeat {
		heartbeatTicker.Reset(newCfg.Heartbeat)
		slog.Info("heartbeat interval updated", "heartbeat", newCfg.Heartbeat)
	}

	// Update WebSocket endpoint
	if newCfg.Endpoint != old.Endpoint {
		a.client.UpdateEndpoint(newCfg.Endpoint)
		slog.Info("endpoint updated", "endpoint", newCfg.Endpoint)
	}

	// Update auth token
	if newCfg.Token != old.Token {
		a.client.UpdateAuth(newCfg.Token)
		slog.Info("auth token updated")
	}

	// Update debug logging
	if newCfg.Debug != old.Debug {
		slog.Info("debug mode changed", "debug", newCfg.Debug)
	}

	// Update source
	if newCfg.Source != old.Source {
		a.handleSourceChange(ctx, newCfg.Source)
	}
}

func (a *App) handleSourceChange(ctx context.Context, srcName string) {
	slog.Info("source change requested", "source", srcName)

	a.cfg.Source = srcName
	defaultArtwork := tray.IconData()

	var newSource media.Source
	switch srcName {
	case "Music", "Spotify":
		newSource = media.NewAppleScriptSource(srcName, defaultArtwork)
	case "MediaRemote":
		s, err := media.NewMediaRemoteSource("", defaultArtwork)
		if err != nil {
			slog.Error("failed to create MediaRemote source", "error", err)
			return
		}
		newSource = s
	default:
		slog.Error("unknown source", "source", srcName)
		return
	}

	a.source = newSource
	a.lastTrack = nil // Force re-send on next poll

	if a.tray != nil {
		a.tray.SetSource(srcName)
	}

	// Save to config
	if err := config.Save(a.cfg); err != nil {
		slog.Error("failed to save config after source change", "error", err)
	}

	// Poll immediately with new source
	a.poll(ctx)
}
