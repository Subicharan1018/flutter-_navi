"""data-queue-v1, repo only (NOT installed on the server: install.sh copies only files/): the copies and ports in
this package agree with their sources in tool/.

    python -m pytest tool/server/data-queue-v1/tests_repo -q
"""
import importlib.util
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(HERE, "..", "files")
TOOL = os.path.join(HERE, "..", "..", "..")          # tool/
sys.path.insert(0, PKG)

from navivibe import data_queue_model as model  # noqa: E402
from navivibe import data_queue_store as store  # noqa: E402


def _load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_file_format_matches_library_export_py():
    mod = _load(os.path.join(TOOL, "exportify", "library_export.py"), "library_export")
    rows = [{"title": "Té, \"x\"", "artist": "A;B", "album": "", "album_artist": "A", "duration": 99.6, "isrc": "usabc1234567"},
            {"title": "Plain", "artist": "", "album": "Z", "album_artist": "", "duration": None, "isrc": "bad"}]
    theirs = [mod.make_song(r["title"], r["artist"], r["album"], r["album_artist"], r["duration"], r["isrc"]) for r in rows]
    assert store.csv_text(rows) == mod.csv_text(theirs)
    assert store.txt_text(rows) == mod.txt_text(theirs)


def test_tool_copies_are_identical():
    for name in ("library_sample.py", "embedding_gap.py", "spotify_match.py"):
        with open(os.path.join(TOOL, "exportify", name), "rb") as a, \
                open(os.path.join(PKG, "navivibe", "data_queue_tools", name), "rb") as b:
            # compare ignoring line endings (a Windows checkout may differ from the repo's LF)
            assert a.read().replace(b"\r\n", b"\n") == b.read().replace(b"\r\n", b"\n"), name


def test_ridge_matches_the_calibration_script():
    sys.path.insert(0, os.path.join(TOOL, "exportify"))
    try:
        cal = _load(os.path.join(TOOL, "shuffle_eval", "calibrate_audio_features.py"), "calibrate_audio_features")
    finally:
        sys.path.remove(os.path.join(TOOL, "exportify"))
    rng = np.random.default_rng(5)
    X, y = rng.normal(size=(90, 6)), rng.uniform(size=90)
    assert model.pick_alpha(X, y, 1, 0.0, 1.0) == cal.pick_alpha(X, y, 1, 0.0, 1.0)
    assert np.allclose(model.fit_predict(X[:70], y[:70], X[70:], 10.0), cal.fit_predict(X[:70], y[:70], X[70:], 10.0))
