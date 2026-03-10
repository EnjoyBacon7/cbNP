// Package tray manages the macOS system tray (menu bar) for cbNP.
package tray

import (
	"log/slog"
	"os/exec"
	"runtime"

	"fyne.io/systray"

	"github.com/KinanLak/klNP/internal/config"
)

// Events carries user interactions from the tray menu back to the app.
type Events struct {
	UpdateNow    chan struct{}
	SourceChange chan string
	OpenConfig   chan struct{}
	Quit         chan struct{}
}

// Tray holds references to menu items and event channels.
type Tray struct {
	events  Events
	version string

	trackItem      *systray.MenuItem
	connectionItem *systray.MenuItem
	sourceItems    map[string]*systray.MenuItem
}

// NewEvents creates a new Events with buffered channels.
func NewEvents() Events {
	return Events{
		UpdateNow:    make(chan struct{}, 1),
		SourceChange: make(chan string, 1),
		OpenConfig:   make(chan struct{}, 1),
		Quit:         make(chan struct{}, 1),
	}
}

// Setup initializes the system tray. Call from systray.Run's onReady callback.
func Setup(version string, currentSource string, events Events) *Tray {
	t := &Tray{
		events:      events,
		version:     version,
		sourceItems: make(map[string]*systray.MenuItem),
	}

	systray.SetTemplateIcon(TemplateIconData(), IconData())
	systray.SetTooltip("cbNP")

	// Suppress right-click menu — only left-click should open the menu
	systray.SetOnSecondaryTapped(func() {})

	// Track display (disabled info item)
	t.trackItem = systray.AddMenuItem("Not Playing", "Current track")
	t.trackItem.Disable()

	// Connection state (disabled info item)
	t.connectionItem = systray.AddMenuItem("Connecting...", "WebSocket connection state")
	t.connectionItem.Disable()

	systray.AddSeparator()

	// Update Now
	updateItem := systray.AddMenuItem("Update Now", "Force poll now")
	go func() {
		for range updateItem.ClickedCh {
			select {
			case events.UpdateNow <- struct{}{}:
			default:
			}
		}
	}()

	systray.AddSeparator()

	// Open Config
	configItem := systray.AddMenuItem("Open Config...", "Open config file in editor")
	go func() {
		for range configItem.ClickedCh {
			openConfigFile()
			select {
			case events.OpenConfig <- struct{}{}:
			default:
			}
		}
	}()

	// Source submenu
	sourceMenu := systray.AddMenuItem("Source", "Select media source")
	for _, src := range config.ValidSources {
		item := sourceMenu.AddSubMenuItem(src, "Use "+src+" as media source")
		t.sourceItems[src] = item
		if src == currentSource {
			item.Check()
		}
		// Capture src for goroutine
		srcName := src
		go func() {
			for range item.ClickedCh {
				select {
				case events.SourceChange <- srcName:
				default:
				}
			}
		}()
	}

	systray.AddSeparator()

	// Version
	versionItem := systray.AddMenuItem("v"+version, "")
	versionItem.Disable()

	// Quit
	quitItem := systray.AddMenuItem("Quit", "Quit cbNP")
	go func() {
		for range quitItem.ClickedCh {
			select {
			case events.Quit <- struct{}{}:
			default:
			}
		}
	}()

	return t
}

// SetTrackTitle updates the displayed track in the menu.
func (t *Tray) SetTrackTitle(title string) {
	t.trackItem.SetTitle(title)
	systray.SetTooltip(title)
}

// SetConnectionState updates the connection status display in the menu.
func (t *Tray) SetConnectionState(state string) {
	switch state {
	case "connected":
		t.connectionItem.SetTitle("Connected")
	case "connecting":
		t.connectionItem.SetTitle("Connecting...")
	default:
		t.connectionItem.SetTitle("Disconnected")
	}
}

// SetSource updates the checked state of the source submenu.
func (t *Tray) SetSource(source string) {
	for name, item := range t.sourceItems {
		if name == source {
			item.Check()
		} else {
			item.Uncheck()
		}
	}
}

func openConfigFile() {
	cfgPath, err := config.Path()
	if err != nil {
		slog.Error("could not determine config path", "error", err)
		return
	}

	var cmd *exec.Cmd
	if runtime.GOOS == "darwin" {
		cmd = exec.Command("open", "-t", cfgPath)
	} else {
		cmd = exec.Command("xdg-open", cfgPath)
	}

	if err := cmd.Start(); err != nil {
		slog.Error("could not open config file", "error", err)
	}
}
