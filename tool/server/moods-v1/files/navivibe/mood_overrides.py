"""
navivibe/mood_overrides.py   (moods-v1)
───────────────────────────
"Not this mood": a listener says a song does not belong under a mood. That
beats the LLM label (catalog/mood_tags.py) for that listener everywhere the
server uses moods for them: Flow mood chips (also the sound-based "gym" chip),
Discover / Weekly mix taste, and the app's Smart Playlists (the app reads the
list from GET /moods/overrides).

One small JSON file per listener in {log dir}/mood_overrides/, like
flow_prefs, so deleting a listener's data deletes this too:
    {song_id: ["sad", ...]}       the moods this listener said the song is not
"""

import json
import os
import re
import threading

from navivibe.feedback import DB_DIR

DIR = os.path.join(DB_DIR, "mood_overrides")
MAX_SONGS = 5000                       # a listener can't grow the file without bound
_ID = re.compile(r"^[A-Za-z0-9_.:-]{1,80}$")
_lock = threading.Lock()


def _path(user: str) -> str:
    return os.path.join(DIR, re.sub(r"[^A-Za-z0-9_.-]", "_", user) + ".json")


def valid_id(song_id: str) -> bool:
    return bool(_ID.match(song_id or ""))


def _moods():
    from navivibe.catalog import mood_tags
    return set(mood_tags.FLOW_MOODS)


def load(user: str) -> dict:
    """{song_id: [moods this listener said it is not]}; {} when none or the file is damaged."""
    try:
        with open(_path(user), encoding="utf-8") as f:
            raw = json.load(f)
    except (OSError, ValueError):
        return {}
    if not isinstance(raw, dict):
        return {}
    ok = _moods()
    out = {}
    for sid, moods in raw.items():
        if valid_id(str(sid)) and isinstance(moods, list):
            clean = [m for m in dict.fromkeys(moods) if m in ok]
            if clean:
                out[str(sid)] = clean
    return out


def _save(user: str, data: dict) -> None:
    os.makedirs(DIR, exist_ok=True)
    p = _path(user)
    with open(p + ".tmp", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(p + ".tmp", p)


def add(user: str, song_id: str, mood: str) -> list:
    """Record "not `mood`" for the song; returns the song's override list."""
    with _lock:
        data = load(user)
        cur = data.get(song_id, [])
        if mood not in cur:
            if song_id not in data and len(data) >= MAX_SONGS:
                data.pop(next(iter(data)))             # the oldest goes first
            cur = cur + [mood]
            data[song_id] = cur
            _save(user, data)
        return cur


def remove(user: str, song_id: str, mood: str) -> list:
    """Take a "not `mood`" back (Undo); returns what is left for the song."""
    with _lock:
        data = load(user)
        cur = [m for m in data.get(song_id, []) if m != mood]
        if cur != data.get(song_id, []):
            if cur:
                data[song_id] = cur
            else:
                data.pop(song_id, None)
            _save(user, data)
        return cur


def disputed(user: str, mood: str) -> set:
    """Song ids this listener said are not `mood`."""
    return {s for s, moods in load(user).items() if mood in moods}


def apply(labels: dict, overrides: dict) -> dict:
    """The labels with each overridden mood taken off its song. `labels` is not changed."""
    if not overrides:
        return labels
    out = dict(labels)
    for sid, nots in overrides.items():
        if sid in out:
            out[sid] = [m for m in out[sid] or [] if m not in nots]
    return out


def for_user(user: str, labels: dict = None) -> dict:
    """The mood labels as this listener sees them."""
    if labels is None:
        from navivibe.catalog import mood_tags
        labels = mood_tags.load()
    return apply(labels, load(user)) if user else labels
