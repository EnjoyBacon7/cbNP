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
import rumps

from helper import Command, exec_command

ENDPOINT = ""
API_TOK = ""

class Track:
    def __init__(self, name, artist, album, artwork):
        self.name = name
        self.artist = artist
        self.album = album
        self.artwork = artwork

    def __str__(self):
        return f"{self.name} by {self.artist} from {self.album} ({len(self.artwork)})"

class cbNPApp(rumps.App):

    def __init__(self):
        super(cbNPApp, self).__init__("cbNP")
        parser = argparse.ArgumentParser()
        parser.add_argument("-e", "--endpoint", help="The endpoint to connect to.")
        parser.add_argument("-t", "--token", help="The API token to use.")
        parser.add_argument("-i", "--interval", help="The interval in seconds to check for updates.", default=30, type=int)
        parser.add_argument("-d", "--debug", help="Enable debug mode.", action="store_true")
        self.args = parser.parse_args()

        self.timer = rumps.Timer(self.update, self.args.interval)
        self.timer.start()

    @rumps.clicked("Update manually")
    def update_manually(self):
        self.update(None)

    def update(self, _):
        track = exec_command(Command.GET_CURRENT_TRACK)
        artist = exec_command(Command.GET_CURRENT_ARTIST)
        album = exec_command(Command.GET_CURRENT_ALBUM)
        artwork = exec_command(Command.GET_CURRENT_ARTWORK)

        if artwork != "":
            try:
                # Getting rid of all applescript bs formatting (and converting to binary)
                raw_data = artwork[10:]
                raw_data = re.sub(r"[^a-zA-Z0-9+/=]", "", raw_data)
                raw_data = bytes.fromhex(raw_data)
                artwork = raw_data
            except ValueError:
                print("Error parsing artwork data.")

            print(Track(track, artist, album, artwork))
        
        threading.Thread(target=asyncio.run, args=(self.push_update(Track(track, artist, album, artwork)),)).start()

    async def push_update(self, track):
        async with websockets.connect(f"{self.args.endpoint}") as websocket:
            # Meh
            track.artwork = base64.b64encode(track.artwork).decode("utf-8")
            track = track.__dict__
            message = {
                "type": "update",
                "payload": track,
                "auth": self.args.token
            }
            message = json.dumps(message)

            await websocket.send(message)


if __name__ == "__main__":
    cbNPApp().run()