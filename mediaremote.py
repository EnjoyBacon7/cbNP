import ctypes
import threading
from dataclasses import dataclass
from typing import Any

import objc


MEDIA_REMOTE_FRAMEWORK = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
LIBDISPATCH = "/usr/lib/system/libdispatch.dylib"
LIBSYSTEM = "/usr/lib/libSystem.B.dylib"

BLOCK_HAS_SIGNATURE = 1 << 30


class _BlockDescriptor(ctypes.Structure):
    _fields_ = [
        ("reserved", ctypes.c_ulong),
        ("size", ctypes.c_ulong),
        ("copy_helper", ctypes.c_void_p),
        ("dispose_helper", ctypes.c_void_p),
        ("signature", ctypes.c_char_p),
    ]


class _BlockLiteral(ctypes.Structure):
    _fields_ = [
        ("isa", ctypes.c_void_p),
        ("flags", ctypes.c_int),
        ("reserved", ctypes.c_int),
        ("invoke", ctypes.c_void_p),
        ("descriptor", ctypes.POINTER(_BlockDescriptor)),
    ]


@dataclass
class NowPlayingTrack:
    title: str
    artist: str
    album: str
    identifier: str
    artwork_data: bytes | None


class MediaRemoteClient:
    def __init__(self):
        self._mr = ctypes.CDLL(MEDIA_REMOTE_FRAMEWORK)
        self._dispatch = ctypes.CDLL(LIBDISPATCH)
        libsystem = ctypes.CDLL(LIBSYSTEM)

        self._dispatch.dispatch_get_global_queue.argtypes = [ctypes.c_long, ctypes.c_ulong]
        self._dispatch.dispatch_get_global_queue.restype = ctypes.c_void_p
        self._mr.MRMediaRemoteGetNowPlayingInfo.argtypes = [ctypes.c_void_p, ctypes.c_void_p]

        self._ns_concrete_stack_block = ctypes.c_void_p.in_dll(libsystem, "_NSConcreteStackBlock")

    def _dict_to_track(self, payload):
        title = str(payload.get("title") or payload.get("kMRMediaRemoteNowPlayingInfoTitle") or "")
        artist = str(payload.get("artist") or payload.get("kMRMediaRemoteNowPlayingInfoArtist") or "")
        album = str(payload.get("album") or payload.get("kMRMediaRemoteNowPlayingInfoAlbum") or "")

        raw_identifier = payload.get("uniqueIdentifier")
        if raw_identifier is None:
            raw_identifier = payload.get("kMRMediaRemoteNowPlayingInfoUniqueIdentifier")
        identifier = str(raw_identifier or "")

        artwork_data = payload.get("artworkData")
        if artwork_data is None:
            artwork_data = payload.get("kMRMediaRemoteNowPlayingInfoArtworkData")

        if artwork_data is not None:
            artwork_data = bytes(artwork_data)

        return NowPlayingTrack(
            title=title,
            artist=artist,
            album=album,
            identifier=identifier,
            artwork_data=artwork_data,
        )

    def get_now_playing(self, timeout=1.0):
        callback_done = threading.Event()
        callback_result: dict[str, Any] = {"payload": None, "error": None}

        @_NOW_PLAYING_CALLBACK
        def _callback(_block, payload_ptr):
            try:
                if payload_ptr:
                    payload = objc.objc_object(c_void_p=payload_ptr)  # type: ignore[attr-defined]
                    callback_result["payload"] = dict(payload)
            except Exception as exc:
                callback_result["error"] = exc
            finally:
                callback_done.set()

        descriptor = _BlockDescriptor()
        descriptor.reserved = 0
        descriptor.size = ctypes.sizeof(_BlockLiteral)
        descriptor.copy_helper = 0
        descriptor.dispose_helper = 0
        descriptor.signature = b"v@?@"

        block = _BlockLiteral()
        block.isa = self._ns_concrete_stack_block
        block.flags = BLOCK_HAS_SIGNATURE
        block.reserved = 0
        block.invoke = ctypes.cast(_callback, ctypes.c_void_p).value
        block.descriptor = ctypes.pointer(descriptor)

        queue = self._dispatch.dispatch_get_global_queue(0, 0)
        self._mr.MRMediaRemoteGetNowPlayingInfo(queue, ctypes.byref(block))

        if not callback_done.wait(timeout):
            raise TimeoutError(f"Timed out waiting for MediaRemote after {timeout}s")

        if callback_result["error"] is not None:
            raise RuntimeError("MediaRemote callback failed") from callback_result["error"]

        payload = callback_result["payload"]
        if not payload:
            return None

        return self._dict_to_track(payload)


_NOW_PLAYING_CALLBACK = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_void_p)


if __name__ == "__main__":
    client = MediaRemoteClient()
    track = client.get_now_playing(timeout=1.5)
    if track is None:
        print("No active now playing data")
    else:
        print(track)
