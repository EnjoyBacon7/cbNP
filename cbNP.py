import re
import websockets
import asyncio
import json
import base64
import os
import threading
import rumps

from helper import Command, exec_command, get_args, SEPARATOR

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
        
        self.args = get_args()
        
        # Menu items (recognized by rumps)
        self.menu = [
            rumps.MenuItem('Update manually', callback=self.update_manually),
            None,
            rumps.MenuItem('Preferences', callback=self.open_preferences),
        ]

        self.timer = rumps.Timer(self.update, self.args.interval)
        self.timer.start()

    def open_preferences(self, _):
        
        endpoint = self.args.endpoint
        token = self.args.token
        interval = self.args.interval

        def_text = f"""{{
    "endpoint": "{endpoint}",
    "token": "{token}",
    "interval": {interval}
}}"""

        pref = rumps.Window(
            message="Preferences",
            title="cbNP",
            ok="Save",
            cancel="Cancel",
            default_text=def_text,
        )

        response = pref.run()
        if response.clicked:
            data = json.loads(response.text)
            self.args.endpoint = data["endpoint"]
            self.args.token = data["token"]
            self.args.interval = data["interval"]
            
            
    
    def update_manually(self):
        self.update(None)

    def update(self, _):
        data = exec_command(Command.GET_CURRENT_TRACK_BATCH, self.args.debug)

        track, artist, album, artwork = data.split(SEPARATOR + ", ")

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