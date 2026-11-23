"""Builds a local stand-in for the live V3 engine from READ-ONLY copies (catalog.db, listening logs,
mood files, spotify_details.db) so Flow can be replayed offline.  Used by the Flow evaluation only."""
import json, os, sqlite3, sys, types
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# FLOW_DATA: folder with READ-ONLY copies: catalog.db, spotify_details.db, mood_tags.json, mood_admin.json,
#            mood_meta.json, mood_overrides/, logs/<user>_listening_log.db      (see README.md)
# FLOW_TREE: a copy of the server's navivibe folder's PARENT (the folder that contains navivibe/), patched or not
# FLOW_OUT:  where replay_<label>.json files go (default: the current folder)
DATA = os.environ["FLOW_DATA"]
TREE = os.environ["FLOW_TREE"]
SCR = os.environ.get("FLOW_OUT", os.getcwd())
os.environ["NAVIVIBE_LOG_DIR"] = os.path.join(DATA, "logs")
sys.path.insert(0, TREE)

from navivibe import discover, explore, mood_overrides, taste_exclusions   # noqa: E402
from navivibe.catalog import mood_tags, mood_quality                       # noqa: E402
from navivibe.recsys.data import Catalog, load_all                         # noqa: E402

NOTE_PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7,
           "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def real_overlay():
    """{id: {energy, valence, danceability, tempo, loudness, acousticness, key, mode}} for songs with REAL Spotify numbers."""
    c = sqlite3.connect(os.path.join(DATA, "spotify_details.db"))
    out = {}
    for sid, en, va, da, te, lo, ac, ke, mo in c.execute(
            "select song_id, energy, valence, danceability, tempo, loudness, acousticness, key, mode from spotify_details where energy is not null"):
        out[sid] = dict(energy=en, valence=va, danceability=da, tempo=te, loudness=lo, acousticness=ac, key=ke, mode=mo)
    return out


def build(users=None, now=None, dim=32, with_events=True):
    cdb = sqlite3.connect(os.path.join(DATA, "catalog.db"))
    cdb.row_factory = sqlite3.Row
    rows = {r["id"]: dict(r) for r in cdb.execute("select * from songs where missing=0")}
    cat = Catalog.from_rows(rows)
    # audio embedding: effnet 1280-d -> `dim` by SVD (the live engine uses a PCA of the same vectors)
    vec = np.zeros((len(cat.ids), 1280), np.float32)
    for sid, blob in cdb.execute("select song_id, vec from embeddings where model='effnet_discogs'"):
        if sid in cat.index:
            vec[cat.index[sid]] = np.frombuffer(blob, np.float32)[:1280]
    vec -= vec.mean(0)
    u, s, vt = np.linalg.svd(vec, full_matrices=False)
    au = u[:, :dim] * s[:dim]
    au /= np.linalg.norm(au, axis=1, keepdims=True) + 1e-9
    eng = types.SimpleNamespace(cat=cat, fb=types.SimpleNamespace(au=au.astype(np.float32),
                                tx=np.zeros_like(au, dtype=np.float32)))
    # moods: the effective labels the server uses (admin > labeller minus ruled out)
    mood_tags.PATH = os.path.join(DATA, "mood_tags.json")
    mood_overrides.DIR = os.path.join(DATA, "mood_overrides")
    from navivibe import spotify_details
    spotify_details.PATH = os.path.join(DATA, "spotify_details.db")
    if with_events:
        events, _ = load_all(cat, users)
        discover._events.update(at=now or 1e12, events=events)
        eng.events = events
    return eng


def listeners(eng, min_plays=200):
    from collections import Counter
    c = Counter(e.user for e in eng.events if e.ratio >= 0)
    return [u for u, n in c.most_common() if n >= min_plays]
