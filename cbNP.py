import re
import websockets
import asyncio
import json
import base64
import os
import threading
import rumps
import sys

from helper import Command, exec_command, get_args, SEPARATOR

DEFAULT_PREF = {
    "endpoint": "ws://localhost:8000",
    "token": "your_token",
    "interval": 15
}

# If running as app bundle, use the bundled Pref.json path. Else use the local one.
if not hasattr(sys, '_MEIPASS'):
    PREF_PATH = "./Pref.json"
else:
    PREF_PATH = sys._MEIPASS + "Pref.json"

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

        self.track = None
        self.args = get_args()
        
        # Menu items (recognized by rumps)
        self.menu = [
            rumps.MenuItem('No track playing', key='track'),
            rumps.MenuItem('Update manually', callback=self.update_manually),
            None,
            rumps.MenuItem('Preferences', callback=self.open_preferences),
            "v1.1.0"
        ]

        if not os.path.exists(PREF_PATH):
            with open(PREF_PATH, "w") as f:
                f.write(json.dumps(DEFAULT_PREF, indent=4))

        self.timer = rumps.Timer(self.update, self.args.interval)
        self.timer.start()

    def open_preferences(self, _):

        with open(PREF_PATH, "r") as f:
            def_text = f.read()

        print(def_text)

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

            with open(PREF_PATH, "w") as f:
                data = {"endpoint": self.args.endpoint, "token": self.args.token, "interval": self.args.interval}
                f.write(json.dumps(data, indent=4))

            self.timer.stop()
            self.timer = rumps.Timer(self.update, self.args.interval)
            self.timer.start()
            
    def update_manually(self, _):
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

        self.track = Track(track, artist, album, artwork)
        self.menu['track'] = rumps.MenuItem(f"{track} by {artist}" if self.track else "No track playing", key='track')

        threading.Thread(target=asyncio.run, args=(self.push_update(Track(track, artist, album, artwork)),)).start()

    async def push_update(self, track):
        try:
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
        except Exception as e:
            print(e)


if __name__ == "__main__":
    cbNPApp().run()