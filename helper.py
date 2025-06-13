from enum import Enum
import subprocess
import argparse

SEPARATOR = "␟" # BS separator to enable simple regex splitting applescript result (Meh...)
class MusicField:
    def __init__(self, key, var, script, append_sep=True):
        self.key = key
        self.var = var
        self.script = script
        self.append_sep = append_sep

    def declare(self):
        return f"set {self.var} to {self.script}"

    def append_separator(self):
        if self.append_sep:
            return f"set {self.var} to {self.var} & \"{SEPARATOR}\""
        return ""

    def return_var(self):
        return self.var

# Define available fields
MUSIC_FIELDS = {
    "track": MusicField("track", "trackName", "name of current track"),
    "artist": MusicField("artist", "trackArtist", "artist of current track"),
    "album": MusicField("album", "trackAlbum", "album of current track"),
    "id": MusicField("id", "trackId", "id of current track as string"),
    "artwork": MusicField("artwork", "artworkData", "get raw data of artwork 1 of current track", append_sep=False),
}
SPOTIFY_FIELDS = {
    "track": MusicField("track", "trackName", "name of current track"),
    "artist": MusicField("artist", "trackArtist", "artist of current track"),
    "album": MusicField("album", "trackAlbum", "album of current track"),
    "id": MusicField("id", "trackId", "id of current track as string"),
    "artwork": MusicField("artwork", "artworkData", "get artwork url of current track", append_sep=False),
}
fields_map = {
    "Music": MUSIC_FIELDS,
    "Spotify": SPOTIFY_FIELDS
}

def make_script_command(fields, media_player):

    fields_cmds = fields_map.get(media_player, {})

    commands = []
    for key in fields:
        field = fields_cmds.get(key)
        commands.append(field.declare())
    for key in fields:
        sep = fields_cmds.get(key).append_separator()
        if sep:
            commands.append(sep)
    return_vars = [fields_cmds.get(key).return_var() for key in fields]
    commands.append(f"return {{{', '.join(return_vars)}}}")
    return "\n".join(commands)

def exec_command(fields, media_player, debug=False):

    script = f"""
        if application "{media_player}" is running then
            tell application "{media_player}"
                {make_script_command(fields, media_player)}
            end tell
        end if
    """

    ARGS = ["osascript", "-e", script]

    output = subprocess.run(ARGS, capture_output=True, text=True)

    if output.stderr:
        raise RuntimeError(f"Error executing AppleScript: {output.stderr.strip()}")
    if debug:
        print(script)
        print(output.stdout)
        print(output.stderr)
    return output.stdout.strip()

def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-e", 
        "--endpoint", 
        help="The endpoint to connect to.",
        default="ws://localhost:8000"
    )
    parser.add_argument(
        "-t", 
        "--token", 
        help="The API token to use.",
        default="your_token"
    )
    parser.add_argument(
        "-i", 
        "--interval", 
        help="The interval in seconds to check for updates.", 
        default=15, 
        type=int
    )
    parser.add_argument(
        "-d", "--debug", 
        help="Enable debug mode.", 
        action="store_true"
    )
    parser.add_argument(
        "-m", 
        "--media-player", 
        help="The media player to use (default: 'Music').", 
        default="Music"
    )
    return parser.parse_args()