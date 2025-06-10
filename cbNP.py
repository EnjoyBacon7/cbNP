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
import requests

from helper import exec_command, get_args, SEPARATOR

HEARTBEAT = 45

# If running as app bundle, use the bundled paths. Else use local one.
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
        loop (asyncio.AbstractEventLoop): The asyncio event loop.
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

        self.loop = asyncio.new_event_loop()
        threading.Thread(target=self.loop.run_forever, daemon=True).start()

        # Menu items (recognized by rumps)
        self.menu = [
            rumps.MenuItem('track'), # Seems like the "key" parameter does not work
            rumps.MenuItem('Update manually', callback=self.update_manually),
            None,
            rumps.MenuItem('Preferences', callback=self.open_preferences),
            "v2.1.0",
            rumps.MenuItem('Quit', callback=self.exit_application)
        ]

        # Creating a default preferences file if it doesn't exist
        if not os.path.exists(PREF_PATH):
            with open(PREF_PATH, "w") as f:
                f.write(
                    json.dumps(
                        {
                            "endpoint": self.args.endpoint,
                            "token": self.args.token,
                            "interval": self.args.interval,
                            "media_player": self.args.media_player
                        }, indent=4
                    )
                )
        else:
            with open(PREF_PATH, "r") as f:
                data = json.loads(f.read())
                self.args.endpoint = data["endpoint"]
                self.args.token = data["token"]
                self.args.interval = data["interval"]
                self.args.media_player = data["media_player"]

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
            cur_conf = f.read()

        pref = rumps.Window(
            message="Preferences",
            title="cbNP",
            ok="Save",
            cancel="Cancel",
            default_text=cur_conf,
        )

        # Open the window
        response = pref.run()

        # If saved
        if response.clicked:

            try:
                data = json.loads(response.text)
                self.args.endpoint = data["endpoint"]
                self.args.token = data["token"]
                self.args.interval = data["interval"]
                self.args.media_player = data["media_player"]
                
                self.interval_timer.interval = self.args.interval

                with open(PREF_PATH, "w") as f:
                    f.write(json.dumps(data, indent=4))
            except Exception as e:
                self.log_error(f"Error saving preferences: {e}")
                return
            
            self.log_info("New saved preferences: " + str(data))
        
        self.log_info("Preferences window closed.")
        
    def update_manually(self, _):
        """
        Forces an update of the track to the server.
        """
        self.update(None)

    def update(self, _):
        """
        Updates the track and sends it to the server.
        """

        # Arbitrary check TODO
        if self.websocket_conn is None:
            self.log_warning("Websocket connection is not open. Trying to connect...")
            return

        data = exec_command(["track", "artist", "album", "artwork"], self.args.media_player, self.args.debug)
        name = artist = album = artwork = ""

        try:
            name, artist, album, artwork = data.split(SEPARATOR + ", ")
        except ValueError:
            self.log_error(f"Error parsing track data. Is {self.args.media_player} running?")
            self.menu["track"].title = "No track playing"
            return

        # TODO: Consolidate artwork handling. Spotify returns a URL, Music returns raw data.
        if artwork.startswith("http"):
            artwork = requests.get(artwork).content
        else:
            try:
                # Getting rid of all applescript bs formatting (and converting to binary)
                raw_data = artwork[10:]
                raw_data = re.sub(r"[^a-zA-Z0-9+/=]", "", raw_data)
                raw_data = bytes.fromhex(raw_data)
                artwork = raw_data
            except ValueError:
                self.log_error(f"Error parsing artwork data")


        self.menu["track"].title = f"{name} by {artist}"

        future = asyncio.run_coroutine_threadsafe(
            self.push_update(Track(name, artist, album, artwork)),
            self.loop
        )

        try:
            result = future.result()
        except TypeError as e:
            self.log_error(f"Error encoding artwork: {e}")
        except websockets.exceptions.ConnectionClosed as e:
            self.websocket_conn = None
            self.connection_timer.start()
            self.interval_timer.stop()
            self.heartbeat_timer.stop()
            self.log_error(f"Error sending update to websocket: {e}")

    def heartbeat(self, _):
        if self.websocket_conn is None:
            self.log_warning("Websocket connection is not open. Trying to connect...")
            return

        future = asyncio.run_coroutine_threadsafe(self.push_heartbeat(), self.loop)
        try:
            result = future.result()
        except TypeError as e:
            self.log_error(f"Error encoding artwork: {e}")
        except websockets.exceptions.ConnectionClosed as e:
            self.websocket_conn = None
            self.connection_timer.start()
            self.interval_timer.stop()
            self.heartbeat_timer.stop()
            self.log_error(f"Error sending heartbeat to websocket: {e}")

    def exit_application(self, _): # This fails but I can't be bothered to fix it (TODO)
        asyncio.run_coroutine_threadsafe(self.close_conn_quit(), self.loop)

    """ ----------------------------------------------------- """
    """ -------------- Websocket methods -------------------- """
    """ ----------------------------------------------------- """

    def connect(self, _):
        """
        Tries to open a websocket connection.
        """
        if self.websocket_conn is not None:
            self.log_info("Websocket connection already open.")
            self.connection_timer.stop()
            return

        future = asyncio.run_coroutine_threadsafe(self.open_conn(None), self.loop)
        try:
            future.result()
        except Exception as e:
            self.log_error(f"Error opening websocket connection: {e}. Retrying...")
            return

        try:
            # Once a connection has been established. Start the interval timers.
            self.log_info(f"Websocket connection established on {self.args.endpoint}")
            self.interval_timer.start()
            self.heartbeat_timer.start()
            self.connection_timer.stop()
            self.log_info("Timers started.")
        except Exception as e:
            self.log_error(f"Error starting timers: {e}. Retrying...")
            self.connection_timer.start()
            self.interval_timer.stop()
            self.heartbeat_timer.stop()
            self.websocket_conn = None
            return

    async def push_heartbeat(self):
        """
        Sends a heartbeat message to the websocket server.
        """
        message = {
            "type": "heartbeat"
        }
        message = json.dumps(message)

        self.log_info(f"Sending heartbeat to websocket")

        try:
            if self.websocket_conn is None:
                raise websockets.exceptions.ConnectionClosed
            await self.websocket_conn.send(message)
            
        except Exception as e:
            raise e

    async def open_conn(self, _):
        """
        Opens a websocket connection to the server and starts the interval timers.
        """        
        try:
            self.websocket_conn = await websockets.connect(f"{self.args.endpoint}", max_size=None)
        except Exception as e:
            raise e
        
    async def push_update(self, track):
        """
        Sends an update message to the websocket server.

        Args:
            track (Track): The track object to send.
        """
        try:
            # Meh
            track.artwork = base64.b64encode(track.artwork).decode("utf-8")
        except Exception as e:
            raise e

        try:
            self.log_info(f"Sending update to websocket: {track}")

            track = track.__dict__
            message = {
                "type": "update",
                "payload": track,
                "auth": self.args.token
            }


            # TODO: Both for heartbeat and update This is a mess of exceptions
            message = json.dumps(message)

            self.log_info(f"Message size: {sys.getsizeof(message) / 1024} KB")
            await self.websocket_conn.send(message)

        except Exception as e:
            raise e

    async def close_conn(self):
        """
        Closes the class's websocket connection.
        """
        try:
            self.log_info("Closing websocket connection.")
            await self.websocket_conn.close()
        except Exception as e:
            self.log_error(f"Error closing websocket: {e}")

    async def close_conn_quit(self):
        self.interval_timer.stop()
        self.heartbeat_timer.stop()
        await self.close_conn()
        rumps.quit_application()

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
            time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"{time} - INFO: {i}\n")

    def log_warning(self, w):
        """
        Logs a warning message to the error.log file.
        
        Args:
            w (str): The warning message to log.
        """
        print(w)
        with open(LOG_PATH, "a") as f:
            time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"{time} - WARNING: {w}\n")

    def log_error(self, e, display=True):
        """
        Logs an error message to the error.log file.

        Args:
            e (str): The error message to log.
            display (bool): Whether to display the error message in the app.
        """
        print(e)
        with open(LOG_PATH, "a") as f:
            time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"{time} - ERROR: {e}\n")
        if display:
            err_menuitem = rumps.MenuItem('err')
            err_menuitem.title = f'Error: {e}'
            self.menu["err"] = err_menuitem

            threading.Timer(5, lambda: self.menu.pop("err", None)).start()
        
    

if __name__ == "__main__":
    cbNPApp().run()