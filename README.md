# cbNP

A macOS menu bar app that retrieves now-playing data and posts it to a websocket endpoint. It supports Apple Music/Spotify via AppleScript and MediaRemote via a bundled adapter.

<p align="center">
<img src="./assets/logo.png" alt="drawing" width="200"/>
</p>

It lives as a menu bar application and is meant to run in the background. It is only compatible with macOS.

> [!WARNING]  
> On macOS 26 (Tahoe), AppleScript artwork retrieval from Apple Music is unreliable/unavailable. Use `MediaRemote` as the source if you need album artwork.

## Installation

### From release

Download the latest release from the release page and run the app. Only compiled for arm64 (M series chips). For x86_64, please compile from source.

Note that OSX may block the application from running. To allow it, go to `System Preferences > Privacy & Security > Security` and click `Open Anyway`. Keep in mind that apart from my word, there is no garantee this code is safe, I encourage you to compile the source code yourself.

### From source

Use the following command to compile the source code into an application bundle in `dist`:

```bash
uv run pyinstaller cbNP.spec
```

If you wish to work just with an executable file, you can compile with:

```bash
uv run pyinstaller cbNP.py --onefile
```

Otherwise, it is enough to download the source code and run the python code directly.


notes: 
- Install dependencies first: `uv sync`
- Compiling for the executable does work, but is not any more lightweight as the application still compiles with the GUI libraries
- Running the application as an executable will create an unused json file in the same directory as the executable. It is unused and pointless in this case.

## Usage

<p align="center">
<img src="./assets/Demo - 1.2.0.png" alt="drawing"/>
</p>


Running the menu bar application will not be discussed here.

Running the executable or the python script will depend on the following arguments for configuration:

Required arguments:
- `-e` - The endpoint to post the track information to.

Optional arguments:
- `-t` - The token to authenticate with the endpoint.
- `-i` - The interval in seconds between updates. Default is 15 seconds.
- `-d` - Debug mode. Will print additional information to the console.
- `-m` - Media source: `Music`, `Spotify`, or `MediaRemote`.

`MediaRemote` uses a bundled private-framework adapter for now-playing metadata and artwork retrieval.
For signal quality, `MediaRemote` updates are filtered to common music app bundle IDs (Apple Music, Spotify, TIDAL, Deezer, Cider, VOX).
When source is `Music` on Tahoe, the menu bar shows a warning recommending `MediaRemote` for artwork.

## Credits

- MediaRemote integration vendors the original `mediaremote-adapter` project: <https://github.com/ungive/mediaremote-adapter>
- Original adapter author credit: Jonas van den Berg (copyright (c) 2025), BSD 3-Clause license.
- Vendored version tracking is documented in `mediaremote_adapter/VENDORING.md`.

## Configuration and logs

- Preferences are saved to `~/Library/Application Support/cbNP/Pref.json`.
- Logs are written to `~/Library/Application Support/cbNP/error.log`.
- Tokens are redacted in logs.

## Endpoint

The websocket server will receive a json object structured like follows:

```json
{
  "type": "object",
  "properties": {
    "type": {
        "type": "string",
    },
    "payload": {
        "type": "object",
        "properties": {
            "artist": {
                "type": "string",
            },
            "album": {
                "type": "string",
            },
            "track": {
                "type": "string",
            },
            "artwork": {
                "type": "string", // base64 encoded image
            }
        },
    },
    "auth": {
        "type": "string",
    }
  },
  "required": ["type", "payload", "auth"]
}
```
