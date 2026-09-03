# cbNP

A native macOS menu bar app that reads now-playing data and posts it to a WebSocket endpoint. It supports Apple Music and Spotify (via AppleScript) and any media app via a bundled MediaRemote adapter.

<p align="center">
<img src="./assets/logo.png" alt="cbNP logo" width="200"/>
</p>

The app lives in the menu bar (`LSUIElement`, no Dock icon) and runs in the background. macOS only.

> This is the Swift rewrite of cbNP and the actively maintained version.
> The original Python implementation is deprecated and preserved on the [`legacy-python`](https://github.com/EnjoyBacon7/cbNP/tree/legacy-python) branch.

## Requirements

- macOS 26.0 (Tahoe) or later
- Xcode 26 or later to build from source

## Install

[Download cbNP-4.0.3.dmg](https://github.com/EnjoyBacon7/cbNP/releases/download/v4.0.3/cbNP-4.0.3.dmg), open it, and drag **cbNP** to **Applications**.

> **The app is signed with a development certificate and is not notarized by Apple**, so macOS blocks the first launch — “Apple could not verify ‘cbNP’ is free of malware”. The app has to be allowed to run in **System Settings > Privacy & Security**:
>
> 1. Open cbNP, and dismiss the warning with **Done**.
> 2. In **System Settings > Privacy & Security**, scroll to **Security**. “cbNP was blocked to protect your Mac” now appears there — click **Open Anyway**.
> 3. Open cbNP again and confirm with **Open Anyway**.
>
> That entry expires roughly an hour after the blocked launch, so do it in one sitting; if it is gone, launch the app again to bring it back. Recent macOS removed the old right-click > **Open** bypass, so that shortcut does nothing. Only the first launch needs any of this.

## Usage

Click the menu bar icon to open the popover, then configure:

- **Endpoint** — the WebSocket URL to post to (default `ws://localhost:8000`).
- **Token** — optional auth token sent with each update (redacted in logs).
- **Interval** — seconds between polls (integer ≥ 1, default `15`).
- **Source** — `Music`, `Spotify`, or `MediaRemote`.

`MediaRemote` uses a bundled private-framework adapter for now-playing metadata and artwork, and is the recommended source on macOS 26 where AppleScript artwork retrieval from Apple Music is unreliable.

## Endpoint protocol

The app sends JSON text frames over the WebSocket connection. It never expects a reply — anything the server sends back is ignored.

### Heartbeat

Sent once immediately after connecting, then every 45 seconds. A heartbeat that fails to send marks the connection as dropped.

```json
{ "type": "heartbeat" }
```

### Update

Sent right after connecting, and afterwards whenever a poll finds a different track `id` than the last one sent. Polls happen on the configured **Interval**; an unchanged track produces no frame.

```json
{
  "type": "update",
  "payload": {
    "name": "Idioteque",
    "artist": "Radiohead",
    "album": "Kid A",
    "artwork": "iVBORw0KGgoAAAANSUhEUgAA…",
    "id": "1109714933"
  },
  "auth": ""
}
```

| Field | Type | Notes |
| --- | --- | --- |
| `payload.name` | string | Track title. |
| `payload.artist` | string | |
| `payload.album` | string | |
| `payload.artwork` | string | Base64-encoded image data, no data-URI prefix. Empty string when the source returns no artwork. |
| `payload.id` | string | Track identifier from the source; used to detect track changes. |
| `auth` | string | The configured **Token**. Empty string when no token is set. |

Every field is always present. Strings may be empty, but are never `null`.

## Building from source

Open the project and run it from Xcode:

```bash
open cbNP.xcodeproj
```

Select the `cbNP` scheme and press **⌘R**. The app launches into the menu bar (no Dock icon); click the menu bar icon to open the popover. Quit it with the **Quit** button in the popover.

Or build and launch from the command line:

```bash
xcodebuild -scheme cbNP -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/cbNP.app
```

For a Release build, use `-configuration Release` (output lands under `build/Build/Products/Release/`).

Packaging and signing a release is documented in [`docs/RELEASING.md`](docs/RELEASING.md).

## Configuration and logs

- Preferences: `~/Library/Application Support/cbNP/Pref.json`
- Logs: `~/Library/Application Support/cbNP/error.log` (rotated at 512 KB; tokens are redacted)

Preferences saved by the Python version are read as-is, so settings carry over on upgrade.

## Credits

- MediaRemote integration vendors the [`mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter) project by Jonas van den Berg (copyright © 2025, BSD 3-Clause). Vendoring details are in `Resources/VENDORING.md`.
