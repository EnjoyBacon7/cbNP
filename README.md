# cbNP

A python script which retrieves the currently playing track from the Apple Music application through AppleScript and posts it to the provided webhook endpoint.

It lives as a menu bar application and is meant to run in the background. This application uses AppleScript, it is only compatible with macOS.

## Installation

### From release

Download the latest release from the release page and run the executable. Only compiled for arm64 (M series chips). For x86_64, please compile from source.

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

Running the menu bar application will not be discussed here.

Running the executable or the python script will depend on the following arguments for configuration:

Required arguments:
- `-e` - The endpoint to post the track information to.

Optional arguments:
- `-t` - The token to authenticate with the endpoint.
- `-i` - The interval in seconds between updates. Default is 30 seconds.
- `-d` - Debug mode. Will print additional information to the console.

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