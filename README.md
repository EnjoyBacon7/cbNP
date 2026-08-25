# cbNP

A native macOS menu bar app that reads now-playing data and posts it to a WebSocket endpoint. It supports Apple Music and Spotify (via AppleScript) and any media app via a bundled MediaRemote adapter.

The app lives in the menu bar (`LSUIElement`, no Dock icon) and runs in the background. macOS only.

> This is the Swift rewrite of cbNP and the actively maintained version.
> The original Python implementation is deprecated and preserved on the [`legacy-python`](https://github.com/EnjoyBacon7/cbNP/tree/legacy-python) branch.

## Requirements

- macOS 26.0 (Tahoe) or later
- Xcode 26 or later to build from source

## Install

[Download cbNP-4.0.2.dmg](https://github.com/EnjoyBacon7/cbNP/releases/download/v4.0.2/cbNP-4.0.2.dmg), open it, and drag **cbNP** to **Applications**.

> **The app is signed with a development certificate and is not notarized by Apple**, so macOS blocks the first launch — “Apple could not verify ‘cbNP’ is free of malware”. The app has to be allowed to run in **System Settings > Privacy & Security**:
>
> 1. Open cbNP, and dismiss the warning with **Done**.
> 2. In **System Settings > Privacy & Security**, scroll to **Security**. “cbNP was blocked to protect your Mac” now appears there — click **Open Anyway**.
> 3. Open cbNP again and confirm with **Open Anyway**.
>
> That entry expires roughly an hour after the blocked launch, so do it in one sitting; if it is gone, launch the app again to bring it back. Recent macOS removed the old right-click > **Open** bypass, so that shortcut does nothing. Only the first launch needs any of this.

The link is pinned to a release asset because the filename carries its version, so it has to be updated here on every release. A `/releases/latest/download/` URL would survive on its own, but only once releases ship the image under the unversioned name `cbNP.dmg`.

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

### Cutting a release

Bump the version, commit it, then release:

```bash
scripts/bump-version.sh 4.1.0
git commit -am 'chore: bump version to 4.1.0'
scripts/release.sh
```

The two are separate on purpose. `bump-version.sh` edits tracked source (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, across every build configuration so Debug and Release cannot drift); `release.sh` only reads the committed version and refuses to run against a dirty tree or an existing tag, so a published binary always corresponds to a commit.

`release.sh` builds unsigned and then re-signs the bundle, so the free personal team set in the Xcode project keeps working for local development without conflicting with the Developer ID identity used for distribution. Nested code inside `mediaremote_adapter` is signed before the enclosing bundle, which notarization requires.

The script needs two one-time credentials:

1. A **Developer ID Application** certificate for the LOGAMES team (`D793768BHW`): Xcode > Settings > Accounts > LOGAMES > Manage Certificates > **+** > Developer ID Application.
2. A notarytool keychain profile, using an [app-specific password](https://appleid.apple.com):

   ```bash
   xcrun notarytool store-credentials cbNP-notary \
     --apple-id <apple-id> --team-id D793768BHW --password <app-specific-password>
   ```

Neither credential is set up yet, so `release.sh` stops at its identity check and published builds are development-signed and unnotarized — which is what the Gatekeeper note under [Install](#install) describes.

To build a DMG by hand instead, build a Release `.app`, stage it next to an `/Applications` shortcut, and `hdiutil create -format UDZO`.

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
