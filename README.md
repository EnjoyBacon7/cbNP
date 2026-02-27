# cbNP

A macOS application which retrieves the currently playing track from the Apple Music application through AppleScript and posts it to the provided webhook endpoint. Available as a native macOS app.

<p align="center">
<img src="./assets/logo.png" alt="drawing" width="200"/>
</p>

It lives as a menu bar application and is meant to run in the background. This application uses AppleScript, it is only compatible with macOS.

> [!WARNING]  
> cbNP does not play well with macOS 26 a.k.a. Tahoe due to the way AppleScript in Apple Music was updated. Spotify support should work the same. Issue discussed [here](https://www.macscripter.net/t/scripting-changes-or-lack-thereof-in-macos-tahoe/77173/11).

## Installation

### From release

Download the latest release from the release page and run the app. Only compiled for arm64 (M series chips). For x86_64, please compile from source.

Note that OSX may block the application from running. To allow it, go to `System Preferences > Privacy & Security > Security` and click `Open Anyway`. Keep in mind that apart from my word, there is no garantee this code is safe, I encourage you to compile the source code yourself.

### From source

Use the following command to compile the source code into an application bundle. In `dist` by default.

```bash
pyinstaller cbNP.spec
```

If you wish to work just with an executable file, you can compile with:

```bash
pyinstaller cbNP.py --onefile
```

Otherwise, it is enough to download the source code and run the python code directly.


notes: 
- You will need to install the required dependencies and pyinstaller using pip before compiling.
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
