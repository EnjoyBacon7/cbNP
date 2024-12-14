# cbNP

A python script which retrieves the current playing track from the Apple Music application on macOS and posts it to the provided webhook endpoint.

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