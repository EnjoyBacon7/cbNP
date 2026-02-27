import subprocess
import argparse
import os


def _load_app_version():
    pyproject_path = os.path.join(os.path.dirname(__file__), "pyproject.toml")
    try:
        import tomllib
        with open(pyproject_path, "rb") as f:
            data = tomllib.load(f)
        return data.get("project", {}).get("version", "2.1.0")
    except Exception:
        return "2.1.0"

APP_VERSION = _load_app_version()

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
    if not fields_cmds:
        raise ValueError(f"Unsupported media player: {media_player}")

    commands = []
    selected_fields = []
    for key in fields:
        field = fields_cmds.get(key)
        if field is None:
            raise ValueError(f"Unsupported field '{key}' for player '{media_player}'")
        selected_fields.append(field)
        commands.append(field.declare())
    for field in selected_fields:
        sep = field.append_separator()
        if sep:
            commands.append(sep)
    return_vars = [field.return_var() for field in selected_fields]
    commands.append(f"return {{{', '.join(return_vars)}}}")
    return "\n".join(commands)

def exec_command(fields, media_player, debug=False, timeout=5):

    script = f"""
        if application "{media_player}" is running then
            tell application "{media_player}"
                {make_script_command(fields, media_player)}
            end tell
        end if
    """

    ARGS = ["osascript", "-e", script]

    try:
        output = subprocess.run(ARGS, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"AppleScript command timed out after {timeout}s") from exc

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
    )
    parser.add_argument(
        "-t", 
        "--token", 
        help="The API token to use.",
    )
    parser.add_argument(
        "-i", 
        "--interval", 
        help="The interval in seconds to check for updates.", 
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
    )
    return parser.parse_args()
