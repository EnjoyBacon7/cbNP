import subprocess
import os
import re
import websockets
import asyncio
import json
import base64
import argparse
import os
import time
import threading

ENDPOINT = ""
API_TOK = ""

def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-e", "--endpoint", help="The endpoint to connect to.")
    parser.add_argument("-t", "--token", help="The API token to use.")
    parser.add_argument("-i", "--interval", help="The interval in seconds to check for updates.", default=30)
    return parser.parse_args()

class Track:
    def __init__(self, name, artist, album, artwork):
        self.name = name
        self.artist = artist
        self.album = album
        self.artwork = artwork

    def __str__(self):
        return f"{self.name} by {self.artist} from {self.album} ({len(self.artwork)})"

def get_script(key):
    return f"""
    tell application "Music"
        if player state is not stopped then
            return {key} of current track 
        end if
    end tell
    """

def get_now_playing():
    script = get_script("name")
    name = subprocess.run(["osascript", "-e", script], capture_output=True, text=True).stdout.strip()

    script = get_script("artist")
    artist = subprocess.run(["osascript", "-e", script], capture_output=True, text=True).stdout.strip()

    script = get_script("album")
    album = subprocess.run(["osascript", "-e", script], capture_output=True, text=True).stdout.strip()

    script = """
    tell application "Music"
        try
            if player state is not stopped then
                tell artwork 1 of current track
                    if format is JPEG picture then
                        set imgFormat to ".jpg"
                    else
                        set imgFormat to ".png"
                    end if
                end tell
                set rawData to (get raw data of artwork 1 of current track)
                return rawData & "|" & imgFormat
            else
                return ""
            end if
        end try
    end tell
    """
    artwork_result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True).stdout.strip()

    if artwork_result:
        try:
            raw_data, img_format = artwork_result.split("|")

            # Getting rid of all applescript bs formatting (and converting to binary)
            raw_data = raw_data[10:]
            raw_data = re.sub(r"[^a-zA-Z0-9+/=]", "", raw_data)
            raw_data = bytes.fromhex(raw_data)
            
            img_format = img_format.strip().split()[1]

        except ValueError:
            print("Error parsing artwork data.")

    return Track(name, artist, album, raw_data)

def save_artwork(raw_data, img_format_extension):
    try:

        if not os.path.exists("/tmp/cbApps"):
            os.makedirs("/tmp/cbApps", exist_ok=True)

        tmp_folder = "/tmp/cbApps"
        file_name = f"tmp_artwork{img_format_extension}"
        newPath = os.path.join(tmp_folder, file_name)

        with open(newPath, "wb") as file:
            file.write(raw_data)
        print(f"Album artwork saved as {newPath}")
        return newPath
    except Exception as e:
        print(f"Error saving album artwork: {e}")
        return None


async def push_update(track):
    async with websockets.connect(f"{ENDPOINT}?token={API_TOK}") as websocket:
        # Meh
        track.artwork = base64.b64encode(track.artwork).decode("utf-8")
        track = track.__dict__
        message = {
            "type": "update",
            "payload": track,
            "auth": API_TOK
        }
        message = json.dumps(message)
        await websocket.send(message)


async def main():

    args = get_args()
    if not args.endpoint:
        print("Please provide an endpoint.")
        return
    else:
        global ENDPOINT
        ENDPOINT = args.endpoint
        global API_TOK
        API_TOK = args.token

    while True:
        track = get_now_playing()
        print(track)

        threading.Thread(target=asyncio.run, args=(push_update(track),)).start()

        time.sleep(args.interval)
        


if __name__ == "__main__":
    asyncio.run(main())