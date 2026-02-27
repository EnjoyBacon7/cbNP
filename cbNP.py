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
from urllib.parse import urlparse
from typing import Any

from helper import APP_VERSION, exec_command, get_args, SEPARATOR

try:
    from mediaremote import MediaRemoteClient
except Exception:
    MediaRemoteClient = None

HEARTBEAT = 45
REQUEST_TIMEOUT = 5
APP_NAME = "cbNP"
APP_SUPPORT_DIR = os.path.join(os.path.expanduser("~"), "Library", "Application Support", APP_NAME)

current_track = None

# Runtime files should always be placed in a user-writable location.
os.makedirs(APP_SUPPORT_DIR, exist_ok=True)
PREF_PATH = os.path.join(APP_SUPPORT_DIR, "Pref.json")
LOG_PATH = os.path.join(APP_SUPPORT_DIR, "error.log")

# If running as app bundle, use bundled icon path. Else use local one.
MEIPASS = getattr(sys, "_MEIPASS", None)
if MEIPASS is None:
    ICON_PATH = "assets/logo.png"
else:
    ICON_PATH = os.path.join(MEIPASS, "logo.png")


DEFAULT_CONFIG = {
    "endpoint": "ws://localhost:8000",
    "token": "",
    "interval": 15,
    "media_player": "Music"
}
ALLOWED_MEDIA_PLAYERS = {"Music", "Spotify", "MediaRemote"}
COMMON_MEDIAREMOTE_BUNDLES = {
    "com.apple.Music",
    "com.spotify.client",
    "com.tidal.desktop",
    "com.deezer.DeezerDesktop",
    "com.ciderapp.Cider",
    "com.voxapp.mac",
}

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
        artwork (str): The base64 encoded artwork of the track.
    """
    def __init__(self, name, artist, album, artwork, id=None):
        self.name = name
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.id = id

    def __str__(self):
        return f"{self.name} by {self.artist} from {self.album} ({len(self.artwork)}) - id: {self.id}"

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

        super(cbNPApp, self).__init__(APP_NAME, icon=ICON_PATH, quit_button=None)  # type: ignore[arg-type]

        self.args = get_args()

        self.loop = asyncio.new_event_loop()
        threading.Thread(target=self.loop.run_forever, daemon=True).start()

        # Menu items (recognized by rumps)
        self.menu = [
            rumps.MenuItem('track'), # Seems like the "key" parameter does not work
            rumps.MenuItem('Update manually', callback=self.update_manually),
            None,
            rumps.MenuItem('Preferences', callback=self.open_preferences),
            f"v{APP_VERSION}",
            rumps.MenuItem('Quit', callback=self.exit_application)
        ]

        config = self.load_preferences()
        config = self.override_config_with_args(config)

        self.args.endpoint = config["endpoint"]
        self.args.token = config["token"]
        self.args.interval = config["interval"]
        self.args.media_player = config["media_player"]
        self.default_artwork = self._load_default_artwork()
        self.mediaremote_client = None

        if self.args.media_player == "MediaRemote":
            self.mediaremote_client = self._build_mediaremote_client()

        self.websocket_conn = None

        self.interval_timer = rumps.Timer(self.update, self.args.interval)
        self.heartbeat_timer = rumps.Timer(self.heartbeat, HEARTBEAT)

        self.connection_timer = rumps.Timer(self.connect, 2)
        self.connection_timer.start()

    def _load_default_artwork(self):
        try:
            with open(ICON_PATH, "rb") as f:
                return base64.b64encode(f.read()).decode("utf-8")
        except Exception as e:
            self.log_warning(f"Could not load default artwork logo: {e}")
            return ""

    def _build_mediaremote_client(self):
        if MediaRemoteClient is None:
            self.log_warning("MediaRemote mode unavailable; module import failed")
            return None

        try:
            return MediaRemoteClient()
        except Exception as e:
            self.log_warning(f"MediaRemote init failed: {e}")
            return None

    def _is_allowed_mediaremote_source(self, bundle_identifier, is_music_app):
        if bundle_identifier in COMMON_MEDIAREMOTE_BUNDLES:
            return True
        return False if bundle_identifier else bool(is_music_app)

    def _valid_endpoint(self, endpoint):
        if not isinstance(endpoint, str):
            return False
        parsed = urlparse(endpoint)
        return parsed.scheme in {"ws", "wss"} and bool(parsed.netloc)

    def _valid_interval(self, interval):
        return isinstance(interval, int) and interval >= 1

    def _valid_media_player(self, media_player):
        return media_player in ALLOWED_MEDIA_PLAYERS

    def _validate_config(self, data):
        config = dict(DEFAULT_CONFIG)

        endpoint = data.get("endpoint", config["endpoint"])
        if self._valid_endpoint(endpoint):
            config["endpoint"] = endpoint

        token = data.get("token", config["token"])
        if isinstance(token, str):
            config["token"] = token

        interval = data.get("interval", config["interval"])
        if isinstance(interval, bool):
            interval = config["interval"]
        if self._valid_interval(interval):
            config["interval"] = interval

        media_player = data.get("media_player", config["media_player"])
        if self._valid_media_player(media_player):
            config["media_player"] = media_player

        return config

    def _redact_config(self, config):
        sanitized = dict(config)
        token = sanitized.get("token", "")
        if token:
            sanitized["token"] = f"{token[:4]}..."
        return sanitized

    def save_preferences(self, config):
        with open(PREF_PATH, "w") as f:
            json.dump(config, f, indent=4)

    def load_preferences(self):
        if not os.path.exists(PREF_PATH):
            self.save_preferences(DEFAULT_CONFIG)
            return dict(DEFAULT_CONFIG)

        try:
            with open(PREF_PATH, "r") as f:
                data = json.load(f)
        except Exception as e:
            self.log_warning(f"Invalid preferences file, restoring defaults: {e}")
            self.save_preferences(DEFAULT_CONFIG)
            return dict(DEFAULT_CONFIG)

        validated = self._validate_config(data)
        if validated != data:
            self.save_preferences(validated)
        return validated

    def override_config_with_args(self, config):
        overridden = dict(config)

        if self.args.endpoint and self._valid_endpoint(self.args.endpoint):
            overridden["endpoint"] = self.args.endpoint
        if self.args.token is not None:
            overridden["token"] = self.args.token
        if self.args.interval is not None and self._valid_interval(self.args.interval):
            overridden["interval"] = self.args.interval
        if self.args.media_player and self._valid_media_player(self.args.media_player):
            overridden["media_player"] = self.args.media_player

        self.save_preferences(overridden)
        return overridden

    def _handle_connection_loss(self, context, error):
        self.websocket_conn = None
        self.interval_timer.stop()
        self.heartbeat_timer.stop()
        self.connection_timer.start()
        self.log_warning(f"{context}: {error}")

    def _extract_artwork(self, artwork):
        if not artwork or artwork == "missing value":
            return self.default_artwork

        try:
            if artwork.startswith("http"):
                response = requests.get(artwork, timeout=REQUEST_TIMEOUT)
                response.raise_for_status()
                return base64.b64encode(response.content).decode("utf-8")

            raw_data = artwork.replace("«data ", "").replace("»", "")
            raw_data = re.sub(r"[^0-9A-Fa-f]", "", raw_data)
            if len(raw_data) % 2 != 0:
                raw_data = raw_data[:-1]

            if not raw_data:
                return self.default_artwork

            return base64.b64encode(bytes.fromhex(raw_data)).decode("utf-8")
        except Exception:
            return self.default_artwork

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
                data = self._validate_config(json.loads(response.text))
                self.args.endpoint = data["endpoint"]
                self.args.token = data["token"]
                self.args.interval = data["interval"]
                self.args.media_player = data["media_player"]

                self.interval_timer.interval = self.args.interval

                self.save_preferences(data)
            except Exception as e:
                self.log_error(f"Error saving preferences: {e}")
                return

            self.log_info("New saved preferences: " + str(self._redact_config(data)))

            if self.args.media_player == "MediaRemote":
                self.mediaremote_client = self._build_mediaremote_client()
            else:
                self.mediaremote_client = None
        
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

        if self.websocket_conn is None:
            self.log_warning("Websocket connection is not open. Trying to connect...")
            return

        try:
            if self.args.media_player == "MediaRemote":
                name, artist, album, id, artwork = self._fetch_track_mediaremote()
            else:
                name, artist, album, id, artwork = self._fetch_track_applescript()
        except RuntimeError as e:
            self.log_error(f"Error getting track data: {e}", display=False)
            self.menu["track"].title = "No track playing"
            return

        # Check if the track id is the same as the current track id
        global current_track
        if current_track is None or current_track.id != id:
            try:
                if self.args.media_player != "MediaRemote":
                    artwork = self._extract_artwork(artwork)
            except Exception as e:
                self.log_error(f"Error parsing or encoding artwork data: {e}", display=False)
                artwork = ""
            current_track = Track(name, artist, album, artwork, id)
            self.menu["track"].title = f"{name} by {artist}"

        future = asyncio.run_coroutine_threadsafe(
            self.push_update(Track(current_track.name, current_track.artist, current_track.album, current_track.artwork, current_track.id)),
            self.loop
        )

        try:
            future.result(timeout=REQUEST_TIMEOUT)
        except Exception as e:
            self._handle_connection_loss("Error sending update to websocket", e)

    def _fetch_track_applescript(self):
        try:
            data = exec_command(
                ["track", "artist", "album", "id", "artwork"],
                self.args.media_player,
                self.args.debug,
                timeout=REQUEST_TIMEOUT,
            )
        except RuntimeError as e:
            raise RuntimeError(str(e)) from e

        try:
            name, artist, album, id, artwork = data.split(SEPARATOR + ", ", 4)
        except ValueError as e:
            raise RuntimeError(f"Error parsing track data for {self.args.media_player}: {e}") from e

        return name, artist, album, id, artwork

    def _fetch_track_mediaremote(self):
        if self.mediaremote_client is None:
            self.mediaremote_client = self._build_mediaremote_client()

        if self.mediaremote_client is None:
            raise RuntimeError("MediaRemote client is unavailable")

        client = self.mediaremote_client

        result: dict[str, Any] = {"track": None, "error": None}

        def _runner():
            try:
                result["track"] = client.get_now_playing(timeout=REQUEST_TIMEOUT)
            except Exception as e:
                result["error"] = e

        worker = threading.Thread(target=_runner, daemon=True)
        worker.start()
        worker.join(REQUEST_TIMEOUT)

        if worker.is_alive() or result["error"] is not None:
            error = result["error"] if result["error"] is not None else "request timed out"
            self.log_warning(f"MediaRemote fetch failed, falling back to Music AppleScript: {error}")
            return self._fetch_track_applescript_fallback()

        track = result["track"]
        if track is None or not track.title:
            self.log_warning("MediaRemote returned no active track, falling back to Music AppleScript")
            return self._fetch_track_applescript_fallback()

        if not self._is_allowed_mediaremote_source(track.bundle_identifier, track.is_music_app):
            raise RuntimeError(
                f"Ignoring MediaRemote source from non-music app: {track.bundle_identifier or 'unknown'}"
            )

        artwork = self.default_artwork
        if track.artwork_data:
            artwork = base64.b64encode(track.artwork_data).decode("utf-8")

        track_id = track.identifier or f"{track.title}:{track.artist}:{track.album}"
        return track.title, track.artist, track.album, track_id, artwork

    def _fetch_track_applescript_fallback(self):
        try:
            data = exec_command(
                ["track", "artist", "album", "id", "artwork"],
                "Music",
                self.args.debug,
                timeout=REQUEST_TIMEOUT,
            )
            name, artist, album, track_id, artwork = data.split(SEPARATOR + ", ", 4)
            artwork = self._extract_artwork(artwork)
            return name, artist, album, track_id, artwork
        except Exception as e:
            raise RuntimeError(f"MediaRemote fallback failed: {e}") from e

    def heartbeat(self, _):
        if self.websocket_conn is None:
            self.log_warning("Websocket connection is not open. Trying to connect...")
            return

        future = asyncio.run_coroutine_threadsafe(self.push_heartbeat(), self.loop)
        try:
            future.result(timeout=REQUEST_TIMEOUT)
        except Exception as e:
            self._handle_connection_loss("Error sending heartbeat to websocket", e)

    def exit_application(self, _):
        self.interval_timer.stop()
        self.heartbeat_timer.stop()
        self.connection_timer.stop()

        try:
            if self.loop.is_running():
                asyncio.run_coroutine_threadsafe(self.close_conn(), self.loop)
                self.loop.call_soon_threadsafe(self.loop.stop)
        except Exception as e:
            self.log_error(f"Error shutting down cleanly: {e}", display=False)

        rumps.quit_application()

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
            future.result(timeout=REQUEST_TIMEOUT)
        except Exception as e:
            self.log_error(f"Error opening websocket connection: {e}. Retrying...")
            self.connection_timer.start()
            return

        try:
            # Once a connection has been established. Start the interval timers.
            self.log_info(f"Websocket connection established on {self.args.endpoint}")
            self.interval_timer.start()
            self.heartbeat_timer.start()
            self.connection_timer.stop()
            self.log_info("Timers started.")
        except Exception as e:
            self._handle_connection_loss("Error starting timers", e)
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

        if self.websocket_conn is None:
            raise ConnectionError("Websocket connection is not open")
        await self.websocket_conn.send(message)

    async def open_conn(self, _):
        """
        Opens a websocket connection to the server and starts the interval timers.
        """        
        self.websocket_conn = await websockets.connect(
            f"{self.args.endpoint}",
            max_size=None,
            open_timeout=REQUEST_TIMEOUT,
            ping_interval=None,
        )
        
    async def push_update(self, track):
        """
        Sends an update message to the websocket server.

        Args:
            track (Track): The track object to send.
        """
        if self.websocket_conn is None:
            raise ConnectionError("Websocket connection is not open")

        message = {
            "type": "update",
            "payload": track.__dict__,
            "auth": self.args.token
        }

        message = json.dumps(message)

        self.log_info(f"Sending update to websocket: {track} - Message size: {sys.getsizeof(message) / 1024} KB")
        await self.websocket_conn.send(message)

    async def close_conn(self):
        """
        Closes the class's websocket connection.
        """
        try:
            self.log_info("Closing websocket connection.")
            if self.websocket_conn is not None:
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
