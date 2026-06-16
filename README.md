# cbNP

A native macOS menu bar app that reads now-playing data and posts it to a WebSocket endpoint. It supports Apple Music and Spotify (via AppleScript) and any media app via a bundled MediaRemote adapter.

The app lives in the menu bar (`LSUIElement`, no Dock icon) and runs in the background. macOS only.

> This is the Swift rewrite of cbNP and the actively maintained version.
> The original Python implementation is deprecated and preserved on the [`legacy-python`](https://github.com/EnjoyBacon7/cbNP/tree/legacy-python) branch.

## Requirements

- macOS 26.0 (Tahoe) or later
- Xcode 26 or later to build from source

## Install

Download the latest `cbNP-x.y.z.dmg` from the [Releases](https://github.com/EnjoyBacon7/cbNP/releases) page, open it, and drag **cbNP** to **Applications**. The app is signed with a development certificate but not notarized, so on first launch right-click it and choose **Open** to clear Gatekeeper, then confirm.

## Building and running

### From Xcode

```bash
open cbNP.xcodeproj
```

Select the `cbNP` scheme and press **⌘R**. The app launches into the menu bar (no Dock icon); click the menu bar icon to open the popover. Quit it with the **Quit** button in the popover.

### From the command line

Build and launch a Debug build:

```bash
xcodebuild -scheme cbNP -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/cbNP.app
```

For a Release build, use `-configuration Release` (output lands under `build/Build/Products/Release/`).

### Packaging a DMG

Build a Release `.app`, then stage it alongside an `/Applications` shortcut and create a compressed disk image:

```bash
xcodebuild -scheme cbNP -configuration Release -derivedDataPath build build

stage=$(mktemp -d)
cp -R build/Build/Products/Release/cbNP.app "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "cbNP" -srcfolder "$stage" -ov -format UDZO cbNP.dmg
```

## Usage

Click the menu bar icon to open the popover, then configure:

- **Endpoint** — the WebSocket URL to post to (default `ws://localhost:8000`).
- **Token** — optional auth token sent with each update (redacted in logs).
- **Interval** — seconds between polls (integer ≥ 1, default `15`).
- **Source** — `Music`, `Spotify`, or `MediaRemote`.

`MediaRemote` uses a bundled private-framework adapter for now-playing metadata and artwork, and is the recommended source on macOS 26 where AppleScript artwork retrieval from Apple Music is unreliable.

## Endpoint protocol

The app sends JSON text frames over the WebSocket connection.

Periodic heartbeats:

```json
{ "type": "heartbeat" }
```

Track updates (sent when the playing track changes or on a forced refresh):

```json
{
  "type": "update",
  "payload": {
    "track": "string",
    "artist": "string",
    "album": "string",
    "id": "string",
    "artwork": "string (base64-encoded image)"
  },
  "auth": "string (token, may be empty)"
}
```

## Configuration and logs

- Preferences: `~/Library/Application Support/cbNP/Pref.json`
- Logs: `~/Library/Application Support/cbNP/error.log` (rotated at 512 KB; tokens are redacted)

Preferences written by the legacy Python implementation (`media_player` snake_case key) are read for backward compatibility.

## Credits

- MediaRemote integration vendors the [`mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter) project by Jonas van den Berg (copyright © 2025, BSD 3-Clause). Vendoring details are in `Resources/VENDORING.md`.
