// Package config manages application configuration for cbNP.
//
// Configuration is loaded from a YAML file at ~/Library/Application Support/cbNP/config.yaml,
// with CLI flag overrides applied on top. Precedence: CLI flags > config file > defaults.
package config

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"github.com/fsnotify/fsnotify"
	"gopkg.in/yaml.v3"
)

const (
	appName        = "cbNP"
	configFileName = "config.yaml"
)

// Config holds all application settings.
type Config struct {
	Endpoint  string        `yaml:"endpoint"`
	Token     string        `yaml:"token"`
	Interval  time.Duration `yaml:"interval"`
	Source    string        `yaml:"source"`
	Heartbeat time.Duration `yaml:"heartbeat"`
	Debug     bool          `yaml:"debug"`
}

// DefaultConfig returns a Config with sensible defaults.
func DefaultConfig() Config {
	return Config{
		Endpoint:  "ws://localhost:8000",
		Token:     "",
		Interval:  15 * time.Second,
		Source:    "Music",
		Heartbeat: 45 * time.Second,
		Debug:     false,
	}
}

// ValidSources lists the allowed media source values.
var ValidSources = []string{"Music", "Spotify", "MediaRemote"}

// Dir returns the configuration directory path.
func Dir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("get home dir: %w", err)
	}
	return filepath.Join(home, "Library", "Application Support", appName), nil
}

// Path returns the full path to the config file.
func Path() (string, error) {
	dir, err := Dir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, configFileName), nil
}

// Load reads configuration from the YAML file. If the file does not exist,
// it creates one with defaults and returns the default config.
func Load() (Config, error) {
	cfg := DefaultConfig()

	p, err := Path()
	if err != nil {
		return cfg, err
	}

	data, err := os.ReadFile(p)
	if errors.Is(err, os.ErrNotExist) {
		// Create config dir and write defaults
		if mkErr := os.MkdirAll(filepath.Dir(p), 0o755); mkErr != nil {
			return cfg, fmt.Errorf("create config dir: %w", mkErr)
		}
		if saveErr := Save(cfg); saveErr != nil {
			return cfg, fmt.Errorf("save default config: %w", saveErr)
		}
		return cfg, nil
	}
	if err != nil {
		return cfg, fmt.Errorf("read config: %w", err)
	}

	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("parse config: %w", err)
	}

	return cfg, nil
}

// Save writes the configuration to the YAML file.
func Save(cfg Config) error {
	p, err := Path()
	if err != nil {
		return err
	}

	if mkErr := os.MkdirAll(filepath.Dir(p), 0o755); mkErr != nil {
		return fmt.Errorf("create config dir: %w", mkErr)
	}

	data, err := yaml.Marshal(cfg)
	if err != nil {
		return fmt.Errorf("marshal config: %w", err)
	}

	return os.WriteFile(p, data, 0o644)
}

// Validate checks that config values are within acceptable ranges.
func Validate(cfg Config) error {
	if cfg.Endpoint == "" {
		return errors.New("endpoint must not be empty")
	}
	if cfg.Interval < 1*time.Second {
		return errors.New("interval must be at least 1s")
	}
	if cfg.Interval > 5*time.Minute {
		return errors.New("interval must be at most 5m")
	}
	if cfg.Heartbeat < 5*time.Second {
		return errors.New("heartbeat must be at least 5s")
	}
	if !isValidSource(cfg.Source) {
		return fmt.Errorf("invalid source %q; must be one of %v", cfg.Source, ValidSources)
	}
	return nil
}

func isValidSource(s string) bool {
	for _, v := range ValidSources {
		if v == s {
			return true
		}
	}
	return false
}

// marshalConfig serializes config to YAML bytes.
func marshalConfig(cfg Config) ([]byte, error) {
	return yaml.Marshal(cfg)
}

// loadFromPath reads and parses a config from a specific file path.
func loadFromPath(path string) (Config, error) {
	cfg := DefaultConfig()
	data, err := os.ReadFile(path)
	if err != nil {
		return cfg, fmt.Errorf("read config: %w", err)
	}
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("parse config: %w", err)
	}
	return cfg, nil
}

// MergeFlags overlays non-zero CLI flag values onto the config.
type FlagValues struct {
	Endpoint string
	Token    string
	Interval time.Duration
	Source   string
	Debug    *bool // pointer to distinguish "not set" from "false"
}

// MergeFlags applies CLI flag overrides to cfg.
func MergeFlags(cfg *Config, flags FlagValues) {
	if flags.Endpoint != "" {
		cfg.Endpoint = flags.Endpoint
	}
	if flags.Token != "" {
		cfg.Token = flags.Token
	}
	if flags.Interval > 0 {
		cfg.Interval = flags.Interval
	}
	if flags.Source != "" {
		cfg.Source = flags.Source
	}
	if flags.Debug != nil {
		cfg.Debug = *flags.Debug
	}
}

// Watch monitors the config file for changes and sends the new config on the
// returned channel. It debounces rapid writes (editors often write multiple
// times on save). The watcher stops when ctx is canceled.
func Watch(ctx context.Context) (<-chan Config, error) {
	cfgPath, err := Path()
	if err != nil {
		return nil, fmt.Errorf("config path: %w", err)
	}

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		return nil, fmt.Errorf("create watcher: %w", err)
	}

	// Watch the directory (not the file directly) because many editors
	// do atomic save (write tmp + rename), which removes the watched inode.
	cfgDir := filepath.Dir(cfgPath)
	if err := watcher.Add(cfgDir); err != nil {
		watcher.Close()
		return nil, fmt.Errorf("watch %s: %w", cfgDir, err)
	}

	ch := make(chan Config, 1)

	go func() {
		defer watcher.Close()
		defer close(ch)

		const debounce = 500 * time.Millisecond
		var timer *time.Timer

		for {
			select {
			case <-ctx.Done():
				if timer != nil {
					timer.Stop()
				}
				return

			case event, ok := <-watcher.Events:
				if !ok {
					return
				}
				// Only react to writes/creates/renames of our config file
				if filepath.Base(event.Name) != configFileName {
					continue
				}
				if !event.Has(fsnotify.Write) && !event.Has(fsnotify.Create) && !event.Has(fsnotify.Rename) {
					continue
				}

				// Debounce: reset timer on each event
				if timer != nil {
					timer.Stop()
				}
				timer = time.AfterFunc(debounce, func() {
					newCfg, err := Load()
					if err != nil {
						slog.Warn("failed to reload config", "error", err)
						return
					}
					if err := Validate(newCfg); err != nil {
						slog.Warn("reloaded config is invalid, ignoring", "error", err)
						return
					}
					select {
					case ch <- newCfg:
						slog.Info("config reloaded")
					default:
						// Previous reload not yet consumed; skip
					}
				})

			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				slog.Warn("config watcher error", "error", err)
			}
		}
	}()

	return ch, nil
}
