import re
import websockets
import asyncio
import json
import base64
import os
import threading
import rumps
import sys
import datetime

from helper import Command, exec_command, get_args, SEPARATOR

DEFAULT_PREF = {
    "endpoint": "ws://localhost:8000",
    "token": "your_token",
    "interval": 15
}

HEARTBEAT = 45

# If running as app bundle, use the bundled Pref.json path. Else use the local one.
if not hasattr(sys, '_MEIPASS'):
    PREF_PATH = "./Pref.json"
    ICON_PATH = "assets/logo.png"
    LOG_PATH = "./error.log"
else:
    PREF_PATH = sys._MEIPASS + "/Pref.json"
    ICON_PATH = sys._MEIPASS + "/logo.png"
    LOG_PATH = sys._MEIPASS + "/error.log"

""" ------------------------------------------------- """
""" --------------- Track Class --------------------- """
""" ------------------------------------------------- """

class Track:
    """
    A class to represent a track.

    Attributes:
        name (str): The name of the track.
        artist (str): The artist of the track.
        album (str): The album of the track.
        artwork (bytes): The artwork
    """
    def __init__(self, name, artist, album, artwork):
        self.name = name
        self.artist = artist
        self.album = album
        self.artwork = artwork

    def __str__(self):
        return f"{self.name} by {self.artist} from {self.album} ({len(self.artwork)})"

""" ----------------------------------------------- """
""" --------------- App Class --------------------- """
""" ----------------------------------------------- """

class cbNPApp(rumps.App):
    """
    A class to represent the cbNP app.

    Attributes:
        args (argparse.Namespace): The command line arguments.
        menu (list): The rumps menu items.
        websocket_conn (websockets.WebSocketClientProtocol): The websocket connection.
        interval_timer (rumps.Timer): The interval timer for updating the track.
        heartbeat_timer (rumps.Timer): The interval timer for sending heartbeats.
        connection_timer (rumps.Timer): The timer for opening the websocket connection.

    Methods:
        open_preferences: Opens the preferences window.
        update_manually: Updates the track manually.
        connect: Opens a websocket connection.
        update: Updates the track.
        heartbeat: Sends a heartbeat message.
        exit_application: Exits the application.

        open_conn: Opens a websocket connection.
        push_update: Sends an update message to the websocket server.
        push_heartbeat: Sends a heartbeat message to the websocket server.
        close_conn: Closes the websocket connection.

        log_info: Logs an info message.
        log_warning: Logs a warning message.
        log_error: Logs an error message.
    """

    def __init__(self):
        """
        Initializes the cbNP app.
        Parses arguments, creates the menu items, and opens the websocket connection.
        """

        self.log_info("Starting cbNP")

        super(cbNPApp, self).__init__("cbNP", icon=ICON_PATH, quit_button=None)

        self.args = get_args()
        
        # Menu items (recognized by rumps)
        self.menu = [
            rumps.MenuItem('track'), # Seems like the "key" parameter does not work
            rumps.MenuItem('Update manually', callback=self.update_manually),
            None,
            rumps.MenuItem('Preferences', callback=self.open_preferences),
            "v1.2.0",
            rumps.MenuItem('Quit', callback=self.exit_application)
        ]

        # Creating a default preferences file if it doesn't exist
        if not os.path.exists(PREF_PATH):
            with open(PREF_PATH, "w") as f:
                f.write(json.dumps(DEFAULT_PREF, indent=4))

        self.websocket_conn = None

        self.interval_timer = rumps.Timer(self.update, self.args.interval)
        self.heartbeat_timer = rumps.Timer(self.heartbeat, HEARTBEAT)

        self.connection_timer = rumps.Timer(self.connect, 2)
        self.connection_timer.start()

    def open_preferences(self, _):
        """
        Handles the preferences window.
        """

        with open(PREF_PATH, "r") as f:
            def_text = f.read()

        pref = rumps.Window(
            message="Preferences",
            title="cbNP",
            ok="Save",
            cancel="Cancel",
            default_text=def_text,
        )

        # Open the window
        response = pref.run()

        # If saved
        if response.clicked:

            data = json.loads(response.text)
            self.args.endpoint = data["endpoint"]
            self.args.token = data["token"]

            # Reset interval timer if interval has changed and restart it only if it was running
            if data["interval"] != self.args.interval:
                self.args.interval = data["interval"]
                timer_state = self.interval_timer.is_running
                self.interval_timer.stop()
                self.interval_timer = rumps.Timer(self.update, self.args.interval)
                if timer_state:
                    self.interval_timer.start()

            with open(PREF_PATH, "w") as f:
                data = {"endpoint": self.args.endpoint, "token": self.args.token, "interval": self.args.interval}
                f.write(json.dumps(data, indent=4))
            
            self.log_info("New saved preferences: " + str(data))
        
    def update_manually(self, _):
        """
        Forces an update of the track to the server.
        """
        self.update(None)

    def connect(self, _):
        """
        Tries to open a websocket connection.
        """
        asyncio.run(self.open_conn(None))

    def update(self, _):
        """
        Updates the track and sends it to the server.
        """

        # Arbitrary check TODO
        if self.websocket_conn is None:
            return

        data = exec_command(Command.GET_CURRENT_TRACK_BATCH, self.args.debug)

        name = artist = album = artwork = ""

        try:
            name, artist, album, artwork = data.split(SEPARATOR + ", ")
        except ValueError:
            self.log_error(f"Error parsing track data. Is Apple Music running?")
            self.menu["track"].title = "No track playing"
            return

        if artwork != "":
            try:
                # Getting rid of all applescript bs formatting (and converting to binary)
                raw_data = artwork[10:]
                raw_data = re.sub(r"[^a-zA-Z0-9+/=]", "", raw_data)
                raw_data = bytes.fromhex(raw_data)
                artwork = raw_data
            except ValueError:
                self.log_error(f"Error parsing artwork data")


        self.menu["track"].title = f"{name} by {artist}"

        asyncio.run(self.push_update(Track(name, artist, album, artwork)))

    def heartbeat(self, _):
        if self.websocket_conn is not None:
            asyncio.run(self.push_heartbeat())

    def exit_application(self, _): # This fails but I can't be bothered to fix it (TODO)
        asyncio.run(self.close_conn_quit())

    async def close_conn_quit(self):
        self.interval_timer.stop()
        self.heartbeat_timer.stop()
        await self.close_conn()
        rumps.quit_application()

    """ ----------------------------------------------------- """
    """ -------------- Websocket methods -------------------- """
    """ ----------------------------------------------------- """

    async def open_conn(self, _):
        """
        Opens a websocket connection to the server and starts the interval timers.
        """
        if self.websocket_conn is not None:
            self.log_info("Websocket connection already open.")
            self.connection_timer.stop()
            return
        
        try:
            self.websocket_conn = await websockets.connect(f"{self.args.endpoint}")
            # Once a connection has been established. Start the interval timers.
            self.log_info(f"Websocket connection established on {self.args.endpoint}")
            self.interval_timer.start()
            self.heartbeat_timer.start()
        except Exception as e:
            self.log_error(f"Error opening websocket connection: {e}")

    async def push_update(self, track):
        """
        Sends an update message to the websocket server.

        Args:
            track (Track): The track object to send.
        """
        try:
            # Meh
            track.artwork = base64.b64encode(track.artwork).decode("utf-8")

            self.log_info(f"Sending update to websocket: {track}")

            track = track.__dict__
            message = {
                "type": "update",
                "payload": track,
                "auth": self.args.token
            }


            # TODO: Both for heartbeat and update This is a mess of exceptions
            message = json.dumps(message)
            try:
                if self.websocket_conn is None:
                    raise websockets.exceptions.ConnectionClosed
                await self.websocket_conn.send(message)
                
            except websockets.exceptions.ConnectionClosed:
                print(123)
                self.log_error("Websocket connection is closed. Trying to reconnect.")
                self.websocket_conn = None
                self.connection_timer.start()
                return

        except Exception as e:
            self.log_error(f"Error sending update to websocket: {e}. Naïvely assuming the connection is closed.")
            self.websocket_conn = None
            self.connection_timer.start()

    async def push_heartbeat(self):
        """
        Sends a heartbeat message to the websocket server.
        """
        try:
            message = {
                "type": "heartbeat"
            }
            message = json.dumps(message)

            self.log_info(f"Sending heartbeat to websocket")

            try:
                if self.websocket_conn is None:
                    raise websockets.exceptions.ConnectionClosed
                await self.websocket_conn.send(message)
                
            except websockets.exceptions.ConnectionClosed:
                self.log_error("Websocket connection is closed. Trying to reconnect.")
                self.websocket_conn = None
                self.connection_timer.start()
                return

        except Exception as e:
            self.log_error(f"Error sending heartbeat to websocket: {e}")

    async def close_conn(self):
        """
        Closes the class's websocket connection.
        """
        try:
            self.log_info("Closing websocket connection.")
            await self.websocket_conn.close()
        except Exception as e:
            self.log_error(f"Error closing websocket: {e}")

    """ ----------------------------------------------------- """
    """ --------------- Logging methods --------------------- """
    """ ----------------------------------------------------- """

    def log_info(self, i):
        """
        Logs an info message to the error.log file.
        
        Args:
            i (str): The info message to log.
        """
        print(i)
        with open(LOG_PATH, "a") as f:
            f.write(f"{datetime.datetime.now()} - INFO: {i}\n")

    def log_warning(self, w):
        """
        Logs a warning message to the error.log file.
        
        Args:
            w (str): The warning message to log.
        """
        print(w)
        with open(LOG_PATH, "a") as f:
            f.write(f"{datetime.datetime.now()} - WARNING: {w}\n")

    def log_error(self, e, display=True):
        """
        Logs an error message to the error.log file.

        Args:
            e (str): The error message to log.
            display (bool): Whether to display the error message in the app.
        """
        print(e)
        with open(LOG_PATH, "a") as f:
            f.write(f"{datetime.datetime.now()} - ERROR: {e}\n")
        if display:
            err_menuitem = rumps.MenuItem('err')
            err_menuitem.title = f'Error: {e}'
            self.menu["err"] = err_menuitem

            threading.Timer(5, lambda: self.menu.pop("err", None)).start()
        
    

if __name__ == "__main__":
    cbNPApp().run()