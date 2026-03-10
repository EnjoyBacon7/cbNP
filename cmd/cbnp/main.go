// cbNP is a macOS menu bar application that retrieves now-playing media data
// and sends it to a WebSocket endpoint.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"fyne.io/systray"
	flag "github.com/spf13/pflag"

	"github.com/KinanLak/klNP/internal/app"
	"github.com/KinanLak/klNP/internal/config"
	"github.com/KinanLak/klNP/internal/media"
	"github.com/KinanLak/klNP/internal/tray"
)

// Injected at build time via -ldflags.
var (
	version = "dev"
	commit  = "unknown"
)

func main() {
	// CLI flags
	endpoint := flag.StringP("endpoint", "e", "", "WebSocket endpoint URL")
	token := flag.StringP("token", "t", "", "Authentication token")
	interval := flag.DurationP("interval", "i", 0, "Poll interval (e.g. 15s)")
	source := flag.StringP("source", "s", "", "Media source: Music, Spotify, or MediaRemote")
	debug := flag.BoolP("debug", "d", false, "Enable debug logging")
	showVersion := flag.BoolP("version", "v", false, "Print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Printf("cbNP %s (%s)\n", version, commit)
		os.Exit(0)
	}

	// Configure logging
	logLevel := slog.LevelInfo
	if *debug {
		logLevel = slog.LevelDebug
	}
	setupLogging(logLevel)

	slog.Info("starting cbNP", "version", version, "commit", commit)

	// Load config
	cfg, err := config.Load()
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	// Apply CLI flag overrides
	var debugPtr *bool
	if flag.Lookup("debug").Changed {
		debugPtr = debug
	}
	config.MergeFlags(&cfg, config.FlagValues{
		Endpoint: *endpoint,
		Token:    *token,
		Interval: *interval,
		Source:   *source,
		Debug:    debugPtr,
	})

	// Re-check debug after merge
	if cfg.Debug {
		setupLogging(slog.LevelDebug)
	}

	if err := config.Validate(cfg); err != nil {
		slog.Error("invalid config", "error", err)
		os.Exit(1)
	}

	slog.Info("config loaded",
		"endpoint", cfg.Endpoint,
		"source", cfg.Source,
		"interval", cfg.Interval,
		"heartbeat", cfg.Heartbeat,
	)

	// Create media source
	defaultArtwork := tray.IconData()
	var mediaSource media.Source
	switch cfg.Source {
	case "Music", "Spotify":
		mediaSource = media.NewAppleScriptSource(cfg.Source, defaultArtwork)
	case "MediaRemote":
		mediaSource, err = media.NewMediaRemoteSource("", defaultArtwork)
		if err != nil {
			slog.Error("failed to create MediaRemote source", "error", err)
			os.Exit(1)
		}
	default:
		slog.Error("unknown source", "source", cfg.Source)
		os.Exit(1)
	}

	// Create app
	application := app.New(cfg, mediaSource, version)

	// Context with signal cancellation
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	// systray.Run must be called on the main thread (macOS requirement).
	// The app event loop runs in a goroutine.
	systray.Run(
		func() {
			// onReady - called when systray is initialized
			application.SetupTray()
			go application.Run(ctx)
		},
		func() {
			// onExit - called when systray exits
			cancel()
		},
	)
}

func setupLogging(level slog.Level) {
	// Set up slog with a text handler writing to stderr.
	// For a production build, we could also add file-based logging with rotation.
	handler := slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
		Level: level,
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			if a.Key == slog.TimeKey {
				a.Value = slog.StringValue(a.Value.Time().Format(time.DateTime))
			}
			return a
		},
	})
	slog.SetDefault(slog.New(handler))
}
