from enum import Enum
import subprocess
import argparse

SEPARATOR = "++£"

class Command(Enum):
    GET_CURRENT_TRACK = "return name of current track"
    GET_CURRENT_ARTIST = "return artist of current track"
    GET_CURRENT_ALBUM = "return album of current track"
    GET_CURRENT_ARTWORK = "return get raw data of artwork 1 of current track"
    # AppleScript is slow, so a batch command is the only way to ensure that the data is consistent
    GET_CURRENT_TRACK_BATCH = f"""
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set artworkData to get raw data of artwork 1 of current track
            set trackName to trackName & "{SEPARATOR}"
            set trackArtist to trackArtist & "{SEPARATOR}"
            set trackAlbum to trackAlbum & "{SEPARATOR}"
            return {{trackName, trackArtist, trackAlbum, artworkData}}
    """


def exec_command(command, debug=False):

    script = f"""
        if application "Music" is running then
            tell application "Music"
                {command.value}
            end tell
        end if
    """

    ARGS = ["osascript", "-e", script]

    output = subprocess.run(ARGS, capture_output=True, text=True)

    if output.stderr:
        print(output.stderr)

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
    return parser.parse_args()