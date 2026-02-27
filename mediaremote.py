import json
import os
import subprocess
import sys
from dataclasses import dataclass


ADAPTER_DIRNAME = "mediaremote_adapter"
ADAPTER_SCRIPT = "mediaremote-adapter.pl"
ADAPTER_FRAMEWORK = "MediaRemoteAdapter.framework"
ADAPTER_TEST_CLIENT = "MediaRemoteAdapterTestClient"


@dataclass
class NowPlayingTrack:
    title: str
    artist: str
    album: str
    identifier: str
    artwork_data: bytes | None


class MediaRemoteClient:
    def __init__(self):
        adapter_root = self._resolve_adapter_root()
        self._script_path = os.path.join(adapter_root, ADAPTER_SCRIPT)
        self._framework_path = os.path.join(adapter_root, ADAPTER_FRAMEWORK)
        self._test_client_path = os.path.join(adapter_root, ADAPTER_TEST_CLIENT)

    def _resolve_adapter_root(self):
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass:
            return os.path.join(meipass, ADAPTER_DIRNAME)
        return os.path.join(os.path.dirname(__file__), ADAPTER_DIRNAME)

    def _ensure_adapter_files(self):
        missing = []
        for path in [self._script_path, self._framework_path, self._test_client_path]:
            if not os.path.exists(path):
                missing.append(path)
        if missing:
            raise FileNotFoundError(f"Missing MediaRemote adapter assets: {', '.join(missing)}")

    def _dict_to_track(self, payload):
        title = str(payload.get("title") or "")
        artist = str(payload.get("artist") or "")
        album = str(payload.get("album") or "")
        identifier = str(payload.get("uniqueIdentifier") or "")

        artwork_data = payload.get("artworkData")
        if isinstance(artwork_data, str):
            try:
                import base64
                artwork_data = base64.b64decode(artwork_data, validate=False)
            except Exception:
                artwork_data = None
        else:
            artwork_data = None

        return NowPlayingTrack(
            title=title,
            artist=artist,
            album=album,
            identifier=identifier,
            artwork_data=artwork_data,
        )

    def get_now_playing(self, timeout=1.0):
        self._ensure_adapter_files()

        cmd = [
            "perl",
            self._script_path,
            self._framework_path,
            self._test_client_path,
            "get",
        ]

        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=True,
            )
        except subprocess.TimeoutExpired as exc:
            raise TimeoutError(f"Timed out waiting for MediaRemote after {timeout}s") from exc
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(exc.stderr.strip() or "MediaRemote adapter failed") from exc

        out = proc.stdout.strip()
        if not out:
            return None

        payload = json.loads(out)
        if not payload:
            return None
        return self._dict_to_track(payload)


if __name__ == "__main__":
    client = MediaRemoteClient()
    track = client.get_now_playing(timeout=2)
    if track is None:
        print("No active now playing data")
    else:
        print(
            {
                "title": track.title,
                "artist": track.artist,
                "album": track.album,
                "identifier": track.identifier,
                "artwork_bytes": len(track.artwork_data) if track.artwork_data else 0,
            }
        )
