# cbNP

A python script which retrieves the currently playing track from the Apple Music application through AppleScript and posts it to the provided webhook endpoint.

It lives as a menubar application and is meant to run in the background.

Meant to function on macOS. Only compiled for arm64 (M series chips). for x86_64, please compile from source using the following command:

```bash
pyinstaller --onefile cbNP.py
```

note: you will need to install the required dependencies and pyinstaller using pip before compiling.

## Usage

Download the latest release from the relase page and run the executable.

Required arguments:
- `-e` - The endpoint to post the track information to.

Optional arguments:
- `-t` - The token to authenticate with the endpoint.
- `-i` - The interval in seconds between updates. Default is 30 seconds.

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