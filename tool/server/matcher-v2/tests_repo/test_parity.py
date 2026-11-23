"""matcher-v2, repo only (NOT installed on the server): ONE matcher, no drifting copies.

    python -m pytest tool/server/matcher-v2/tests_repo -q

song_match.py in this package is the source. The offline tools use byte-identical copies
(tool/exportify/song_match.py, and the data queue's tool folder), and the offline `spotify_match.py` is only a thin
wrapper over it, so the server (library_sweep.Index) and the tools answer the same for the same song.
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(HERE, "..", "files")
TOOL = os.path.join(HERE, "..", "..", "..")          # tool/
SRC = os.path.join(PKG, "tgfetch", "song_match.py")
COPIES = (os.path.join(TOOL, "exportify", "song_match.py"),
          os.path.join(TOOL, "server", "data-queue-v1", "files", "navivibe", "data_queue_tools", "song_match.py"))
WRAPPERS = (os.path.join(TOOL, "exportify", "spotify_match.py"),
            os.path.join(TOOL, "server", "data-queue-v1", "files", "navivibe", "data_queue_tools", "spotify_match.py"))


def _read(path):
    with open(path, "rb") as f:
        return f.read().replace(b"\r\n", b"\n")        # a Windows checkout may differ from the repo's LF


def test_copies_are_byte_identical():
    for c in COPIES:
        assert _read(c) == _read(SRC), c


def test_the_two_wrappers_are_identical():
    assert _read(WRAPPERS[0]) == _read(WRAPPERS[1])


def test_the_offline_tool_gives_the_same_answers_as_the_server_index():
    sys.path.insert(0, os.path.join(TOOL, "exportify"))
    try:
        spec = importlib.util.spec_from_file_location("spotify_match_offline", os.path.join(TOOL, "exportify", "spotify_match.py"))
        sp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sp)
        spec2 = importlib.util.spec_from_file_location("song_match_src", SRC)
        sm = importlib.util.module_from_spec(spec2)
        sys.modules["song_match_src"] = sm
        spec2.loader.exec_module(sm)
    finally:
        sys.path.remove(os.path.join(TOOL, "exportify"))
    gold = json.load(open(os.path.join(PKG, "tests", "fixtures", "matcher_gold.json"), encoding="utf-8"))["pairs"]
    for p in gold:
        lib = {"id": "x", "isrc": "", "composer": "", "lyricist": "", "album_artist": "", "film": "", "album": "", **p["lib"]}
        q = p["q"]
        server = sm.Index([lib]).match(q["title"], q.get("artist") or "", q.get("duration"), 5, album=q.get("album"))
        row = {"isrc": "", "title": q["title"], "artist": q.get("artist") or "", "album": q.get("album") or "",
               "duration_s": q.get("duration")}
        offline = sp.Index([lib]).find_match(row)
        assert (server and (server.confidence, server.rule)) == (offline and (offline.confidence, offline.rule)), p["id"]
        song, how = sp.Index([lib]).find(row)
        assert (song is not None) == bool(server and server.confidence in ("isrc", "strong")), p["id"]
