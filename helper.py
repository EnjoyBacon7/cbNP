from enum import Enum
import subprocess

class Command(Enum):
    GET_CURRENT_TRACK = "return name of current track"
    GET_CURRENT_ARTIST = "return artist of current track"
    GET_CURRENT_ALBUM = "return album of current track"
    GET_CURRENT_ARTWORK = "return get raw data of artwork 1 of current track"


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

    if debug:
        print(script)
        print(output.stdout)
        print(output.stderr)
    return output.stdout.strip()