package config

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestDefaultConfig(t *testing.T) {
	cfg := DefaultConfig()
	if cfg.Endpoint != "ws://localhost:8000" {
		t.Errorf("expected default endpoint ws://localhost:8000, got %s", cfg.Endpoint)
	}
	if cfg.Source != "Music" {
		t.Errorf("expected default source Music, got %s", cfg.Source)
	}
	if cfg.Interval != 15*time.Second {
		t.Errorf("expected default interval 15s, got %s", cfg.Interval)
	}
	if cfg.Heartbeat != 45*time.Second {
		t.Errorf("expected default heartbeat 45s, got %s", cfg.Heartbeat)
	}
}

func TestValidate(t *testing.T) {
	tests := []struct {
		name    string
		modify  func(*Config)
		wantErr bool
	}{
		{
			name:    "valid default config",
			modify:  func(_ *Config) {},
			wantErr: false,
		},
		{
			name:    "empty endpoint",
			modify:  func(c *Config) { c.Endpoint = "" },
			wantErr: true,
		},
		{
			name:    "interval too short",
			modify:  func(c *Config) { c.Interval = 500 * time.Millisecond },
			wantErr: true,
		},
		{
			name:    "interval too long",
			modify:  func(c *Config) { c.Interval = 10 * time.Minute },
			wantErr: true,
		},
		{
			name:    "heartbeat too short",
			modify:  func(c *Config) { c.Heartbeat = 2 * time.Second },
			wantErr: true,
		},
		{
			name:    "invalid source",
			modify:  func(c *Config) { c.Source = "VLC" },
			wantErr: true,
		},
		{
			name:    "valid Spotify source",
			modify:  func(c *Config) { c.Source = "Spotify" },
			wantErr: false,
		},
		{
			name:    "valid MediaRemote source",
			modify:  func(c *Config) { c.Source = "MediaRemote" },
			wantErr: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := DefaultConfig()
			tt.modify(&cfg)
			err := Validate(cfg)
			if (err != nil) != tt.wantErr {
				t.Errorf("Validate() error = %v, wantErr = %v", err, tt.wantErr)
			}
		})
	}
}

func TestSaveAndLoad(t *testing.T) {
	// Use a temp dir for config
	tmpDir := t.TempDir()
	origHome := os.Getenv("HOME")
	// Override HOME so config dir resolves to temp
	configDir := filepath.Join(tmpDir, "Library", "Application Support", appName)
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		t.Fatal(err)
	}

	// We can't easily override Dir() so we test Save/Load via file directly
	configPath := filepath.Join(configDir, configFileName)

	cfg := DefaultConfig()
	cfg.Endpoint = "wss://test.example.com/ws"
	cfg.Token = "secret-token"
	cfg.Source = "Spotify"
	cfg.Interval = 30 * time.Second

	// Save to known path
	data, err := marshalConfig(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(configPath, data, 0o644); err != nil {
		t.Fatal(err)
	}

	// Read back
	loaded, err := loadFromPath(configPath)
	if err != nil {
		t.Fatal(err)
	}

	if loaded.Endpoint != cfg.Endpoint {
		t.Errorf("endpoint: got %s, want %s", loaded.Endpoint, cfg.Endpoint)
	}
	if loaded.Token != cfg.Token {
		t.Errorf("token: got %s, want %s", loaded.Token, cfg.Token)
	}
	if loaded.Source != cfg.Source {
		t.Errorf("source: got %s, want %s", loaded.Source, cfg.Source)
	}
	if loaded.Interval != cfg.Interval {
		t.Errorf("interval: got %s, want %s", loaded.Interval, cfg.Interval)
	}
	_ = origHome
}

func TestMergeFlags(t *testing.T) {
	cfg := DefaultConfig()
	debug := true
	MergeFlags(&cfg, FlagValues{
		Endpoint: "wss://override.example.com",
		Token:    "flag-token",
		Source:   "Spotify",
		Debug:    &debug,
	})

	if cfg.Endpoint != "wss://override.example.com" {
		t.Errorf("endpoint not overridden: %s", cfg.Endpoint)
	}
	if cfg.Token != "flag-token" {
		t.Errorf("token not overridden: %s", cfg.Token)
	}
	if cfg.Source != "Spotify" {
		t.Errorf("source not overridden: %s", cfg.Source)
	}
	if !cfg.Debug {
		t.Error("debug not overridden")
	}
	// Interval should remain default since not set in flags
	if cfg.Interval != 15*time.Second {
		t.Errorf("interval should remain default, got %s", cfg.Interval)
	}
}
