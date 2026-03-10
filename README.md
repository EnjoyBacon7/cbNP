# klNP

A macOS menu bar app that retrieves now-playing data and sends it to a WebSocket endpoint. It supports Apple Music/Spotify via AppleScript and any media source via the bundled MediaRemote adapter.

<p align="center">
<img src="./assets/logo.png" alt="cbNP logo" width="200"/>
</p>

It lives as a menu bar application and is meant to run in the background. macOS only.

> [!WARNING]
> On macOS 26 (Tahoe), AppleScript artwork retrieval from Apple Music is unreliable. Use `MediaRemote` as the source if you need album artwork.

## Installation

### From release

Download the latest release from the [Releases](https://github.com/KinanLak/klNP/releases) page. Archives are provided for both arm64 (Apple Silicon) and amd64 (Intel).

macOS may block the application from running. To allow it, go to **System Preferences > Privacy & Security > Security** and click **Open Anyway**.

### From source

Requirements: Go 1.22+

```bash
# Build the binary
make build

# Or build the full .app bundle
make app
```

To run directly without creating an app bundle:

```bash
make run -- -e wss://example.com/ws -t my-token
```

## Usage

### CLI Flags

| Flag | Short | Description | Default |
|------|-------|-------------|---------|
| `--endpoint` | `-e` | WebSocket endpoint URL | `ws://localhost:8000` |
| `--token` | `-t` | Authentication token | (empty) |
| `--interval` | `-i` | Poll interval (e.g. `15s`, `30s`) | `15s` |
| `--source` | `-s` | Media source: `Music`, `Spotify`, or `MediaRemote` | `Music` |
| `--debug` | `-d` | Enable debug logging | `false` |
| `--version` | `-v` | Print version and exit | |
| `--config` | | Path to config file | `~/Library/Application Support/cbNP/config.yaml` |

### Configuration

Config is stored at `~/Library/Application Support/cbNP/config.yaml`:

```yaml
endpoint: "wss://example.com/ws"
token: "my-token"
interval: 15s
source: Music
heartbeat: 45s
debug: false
```

**Precedence**: CLI flags > config file > defaults.

The config file can also be opened from the menu bar via **Open Config...**.

### Menu Bar

```
[icon] cbNP
  ├── "Title by Artist"        (current track info)
  ├── ─────────
  ├── Update Now               (force poll)
  ├── ─────────
  ├── Open Config...           (opens config.yaml in editor)
  ├── Source ▸
  │     ├── ✓ Music
  │     ├──   Spotify
  │     └──   MediaRemote
  ├── ─────────
  ├── v4.0.0
  └── Quit
```

### Media Sources

- **Music** / **Spotify**: Uses AppleScript (`osascript`) to query track info from the respective app.
- **MediaRemote**: Uses a vendored private-framework adapter for system-wide now-playing metadata. Filtered to common music app bundle IDs (Apple Music, Spotify, TIDAL, Deezer, Cider, VOX). Falls back to Music AppleScript on failure.

## WebSocket Protocol

All messages use a common envelope:

```json
{
  "type": "update",
  "auth": "my-token",
  "version": "1",
  "sent_at": "2026-01-15T12:00:00Z",
  "payload": {
    "title": "Song Name",
    "artist": "Artist Name",
    "album": "Album Name",
    "artwork": "<base64-encoded image>",
    "track_id": "unique-track-id",
    "source": "Music"
  }
}
```

Heartbeat messages (sent at the configured interval):

```json
{
  "type": "heartbeat",
  "auth": "my-token",
  "version": "1",
  "sent_at": "2026-01-15T12:00:00Z"
}
```

### Key protocol changes from v3

- `auth` is now included in every message (including heartbeats)
- `version` and `sent_at` fields added to all messages
- Track field renamed from `name`/`track` to `title`
- `track_id` and `source` fields added to update payload
- Updates are only sent when the track changes (not every interval)

## Development

```bash
make lint    # Run golangci-lint
make test    # Run tests with race detector
make build   # Build binary
make app     # Build .app bundle
make clean   # Remove build artifacts
```

## Credits

- MediaRemote integration vendors the original `mediaremote-adapter` project: <https://github.com/ungive/mediaremote-adapter>
- Original adapter author: Jonas van den Berg (copyright (c) 2025), BSD 3-Clause license.
- Vendored version tracking: `mediaremote_adapter/VENDORING.md`.

## License

[Apache 2.0](LICENSE)
