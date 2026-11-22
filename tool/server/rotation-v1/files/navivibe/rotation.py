"""
navivibe/rotation.py
────────────────────
What is in and out of a listener's rotation (rotation-v1):

  Rest        a song the listener snoozed for N days, or one the server rests by itself because
              it is being worn out (many plays in two weeks, and the last plays were skipped).
  Seasons     songs that belong to a festival (Deepavali, Pongal, Christmas ...) are left out of
              every recommender and Smart Shuffle outside that season and come back in it.
              A song is seasonal by the listener's own tag, by its title, or because nearly all
              its plays fall in one season.
  Back in     songs the listener loved long ago and has not played for two months: a Home shelf.
  rotation

"Left out" works through taste_exclusions.blocked_ids, the one place every recommender (Discover,
Weekly mix, Flow, Smart Shuffle) already asks, so nothing here touches their code. Playing a
song yourself is never blocked.

Stored per listener in {log dir}/rotation/<user>.json, so erasing a listener's data erases it.
"""

import json
import logging
import math
import os
import random
import re
import threading
import time
from datetime import date, datetime, timedelta, timezone

from navivibe.feedback import DB_DIR
from navivibe.recsys.data import SKIP_RATIO

log = logging.getLogger("navivibe.rotation")

DIR = os.path.join(DB_DIR, "rotation")
IST = timezone(timedelta(hours=5, minutes=30))
DAY = 86400

MIN_REST_DAYS, MAX_REST_DAYS = 1, 365
MAX_RESTING = 500

# Wearing out: this many plays in two weeks, and two of the last three were skipped.
WEAR_WINDOW_DAYS = 14
WEAR_PLAYS = 10
WEAR_LAST, WEAR_SKIPS = 3, 2
AUTO_REST_DAYS = 14
GRACE_DAYS = 30                      # after "Bring back", the same song is not rested again for this long
REFRESH_S = 6 * 3600                 # how often a listener's plays are looked at again

# Back in rotation: loved long ago, quiet for two months.
BACK_FULL_PLAYS = 4                  # completed plays older than BACK_OLD_DAYS
BACK_OLD_DAYS = 90
BACK_QUIET_DAYS = 60
BACK_MAX_SKIP_RATE = 0.3
FULL_RATIO = 0.8
BACK_LIMIT = 20

# Seasons from plays: enough plays, nearly all of them inside one season.
SEASON_MIN_PLAYS = 5
SEASON_SHARE = 0.85

# key: (label, (month, day) it starts, (month, day) it ends). Festival dates move every year, so each
# window is wide: the weeks before it (people start early) and the days after. A window may wrap the year.
SEASONS = {
    "deepavali": ("Deepavali", (10, 5), (11, 18)),
    "navaratri": ("Navaratri", (9, 15), (10, 25)),
    "vinayagar": ("Vinayagar Chaturthi", (8, 15), (9, 20)),
    "ayyappa": ("Ayyappa season", (11, 10), (1, 20)),
    "christmas": ("Christmas", (12, 1), (1, 2)),
    "pongal": ("Pongal", (1, 5), (1, 20)),
}
NO_SEASON = "none"                   # the listener said: this song is not seasonal

# Words in a title that make a song seasonal without any plays to go by.
KEYWORDS = {
    "christmas": ("christmas", "xmas", "jingle bells", "silent night"),
    "deepavali": ("deepavali", "diwali", "dipavali", "deepawali"),
    "pongal": ("pongal",),
    "ayyappa": ("ayyappa", "ayyappan", "ayyapan", "sabarimala"),
    "navaratri": ("navaratri", "navarathri", "navratri"),
    "vinayagar": ("vinayagar", "vinayaka chaturthi"),
}

DEFAULT_PREFS = {"auto_rest": True, "seasons": True, "back": True}     # back: the shelf and the shuffle bias

_lock = threading.Lock()


# ── storage ──────────────────────────────────────────────────────────────────

def _path(user: str) -> str:
    return os.path.join(DIR, re.sub(r"[^A-Za-z0-9_.-]", "_", user) + ".json")


def load(user: str) -> dict:
    try:
        with open(_path(user), encoding="utf-8") as f:
            raw = json.load(f)
    except (OSError, ValueError):
        raw = {}
    if not isinstance(raw, dict):
        raw = {}
    out = {
        "rest": {k: v for k, v in (raw.get("rest") or {}).items() if isinstance(v, dict)},
        "grace": {k: float(v) for k, v in (raw.get("grace") or {}).items() if isinstance(v, (int, float))},
        "season": {k: v for k, v in (raw.get("season") or {}).items() if v == NO_SEASON or v in SEASONS},
        "auto_season": {k: v for k, v in (raw.get("auto_season") or {}).items() if v in SEASONS},
        "checked_at": float(raw.get("checked_at") or 0),
        "prefs": {**DEFAULT_PREFS, **{k: bool(v) for k, v in (raw.get("prefs") or {}).items() if k in DEFAULT_PREFS}},
    }
    return out


def _save(user: str, state: dict) -> None:
    os.makedirs(DIR, exist_ok=True)
    p = _path(user)
    with open(p + ".tmp", "w", encoding="utf-8") as f:
        json.dump({"user": user, **state}, f, ensure_ascii=False)
    os.replace(p + ".tmp", p)


def _change(user: str, fn) -> dict:
    with _lock:
        state = load(user)
        fn(state)
        _save(user, state)
    return state


# ── seasons ──────────────────────────────────────────────────────────────────

def in_window(key: str, day: date) -> bool:
    """Whether `day` is inside the season's window (a window may run over New Year)."""
    _, (m1, d1), (m2, d2) = SEASONS[key]
    here, start, end = (day.month, day.day), (m1, d1), (m2, d2)
    return start <= here <= end if start <= end else (here >= start or here <= end)


def today_ist(now: float) -> date:
    return datetime.fromtimestamp(now, IST).date()


def seasons_now(now: float) -> list:
    """Every season with whether it is on today, for the app's settings."""
    day = today_ist(now)
    return [{"key": k, "label": v[0], "in_season": in_window(k, day),
             "from": f"{v[1][1]} {_MONTHS[v[1][0] - 1]}", "to": f"{v[2][1]} {_MONTHS[v[2][0] - 1]}"}
            for k, v in SEASONS.items()]


_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def season_from_title(title: str) -> str | None:
    t = (title or "").lower()
    for key, words in KEYWORDS.items():
        if any(w in t for w in words):
            return key
    return None


def window_days(key: str) -> int:
    """How many days a season's window spans (2026 is not a leap year; only the order matters)."""
    _, (m1, d1), (m2, d2) = SEASONS[key]
    a, b = date(2026, m1, d1), date(2026 if (m2, d2) >= (m1, d1) else 2027, m2, d2)
    return (b - a).days + 1


def season_from_plays(timestamps: list) -> str | None:
    """The season nearly all of a song's plays fall in; None when it is played all year round.
    Windows overlap (Christmas sits inside Ayyappa season): the narrowest one that holds the plays wins."""
    if len(timestamps) < SEASON_MIN_PLAYS:
        return None
    days = [today_ist(t) for t in timestamps]
    fits = [k for k in SEASONS if sum(1 for d in days if in_window(k, d)) / len(days) >= SEASON_SHARE]
    return min(fits, key=window_days) if fits else None


def effective_season(state: dict, sid: str) -> str | None:
    manual = state["season"].get(sid)
    if manual == NO_SEASON:
        return None
    return manual or state["auto_season"].get(sid)


# ── what is left out ─────────────────────────────────────────────────────────

def resting_ids(state: dict, now: float) -> set:
    return {s for s, r in state["rest"].items() if float(r.get("until") or 0) > now}


def out_of_season_ids(state: dict, now: float) -> set:
    if not state["prefs"]["seasons"]:
        return set()
    day = today_ist(now)
    out = set()
    for sid in set(state["season"]) | set(state["auto_season"]):
        key = effective_season(state, sid)
        if key and not in_window(key, day):
            out.add(sid)
    return out


def hidden_ids(user: str, meta: dict, now: float = None) -> set:
    """Catalog song ids that are resting or out of season for `user` right now."""
    now = time.time() if now is None else now
    state = load(user)
    return (resting_ids(state, now) | out_of_season_ids(state, now)) & set(meta)


# ── rest ─────────────────────────────────────────────────────────────────────

def clean_days(days) -> int | None:
    if isinstance(days, bool) or not isinstance(days, (int, float)):
        return None
    days = int(days)
    return days if MIN_REST_DAYS <= days <= MAX_REST_DAYS else None


def rest(user: str, song_id: str, days: int, label: str = "", now: float = None, auto: bool = False) -> dict:
    now = time.time() if now is None else now
    entry = {"since": int(now), "until": int(now + days * DAY), "auto": auto, "label": (label or "").strip()[:120]}

    def fn(state):
        state["rest"][song_id] = entry
        if len(state["rest"]) > MAX_RESTING:
            live = sorted(state["rest"].items(), key=lambda kv: kv[1].get("until", 0), reverse=True)
            state["rest"] = dict(live[:MAX_RESTING])
    _change(user, fn)
    return entry


def unrest(user: str, song_id: str, now: float = None) -> bool:
    """Bring a song back. One the server rested stays safe from it for GRACE_DAYS."""
    now = time.time() if now is None else now
    found = []

    def fn(state):
        r = state["rest"].pop(song_id, None)
        if r is not None:
            found.append(True)
            if r.get("auto"):
                state["grace"][song_id] = now + GRACE_DAYS * DAY
    _change(user, fn)
    return bool(found)


def set_season(user: str, song_id: str, key: str | None) -> bool:
    """Tag a song with a season, `none` (never seasonal), or None to forget the tag."""
    if key is not None and key != NO_SEASON and key not in SEASONS:
        return False

    def fn(state):
        if key is None:
            state["season"].pop(song_id, None)
        else:
            state["season"][song_id] = key
    _change(user, fn)
    return True


def set_prefs(user: str, **prefs) -> dict:
    def fn(state):
        for k, v in prefs.items():
            if k in DEFAULT_PREFS and isinstance(v, bool):
                state["prefs"][k] = v
    return _change(user, fn)["prefs"]


# ── looking at the plays ─────────────────────────────────────────────────────

def _by_song(events: list, user: str) -> dict:
    out = {}
    for e in events:
        if e.user == user:
            out.setdefault(e.song, []).append(e)
    for plays in out.values():
        plays.sort(key=lambda e: e.ts)
    return out


def worn_out(plays: list, now: float) -> bool:
    """Many plays lately and the latest ones skipped: the listener has had enough of it."""
    recent = [e for e in plays if now - WEAR_WINDOW_DAYS * DAY <= e.ts <= now]
    if len(recent) < WEAR_PLAYS:
        return False
    last = recent[-WEAR_LAST:]
    return sum(1 for e in last if e.ratio < SKIP_RATIO) >= WEAR_SKIPS


def refresh(user: str, events: list, meta: dict, now: float = None, force: bool = False) -> dict:
    """Look at the listener's plays (at most every REFRESH_S): rest worn-out songs and find seasonal ones.
    `events` may hold other listeners' plays too."""
    now = time.time() if now is None else now
    state = load(user)
    if not force and now - state["checked_at"] < REFRESH_S:
        return state
    songs = _by_song(events, user)
    rested = resting_ids(state, now)
    new_rest = {}
    if state["prefs"]["auto_rest"]:
        for sid, plays in songs.items():
            if sid in rested or sid not in meta or state["grace"].get(sid, 0) > now:
                continue
            if worn_out(plays, now):
                new_rest[sid] = {"since": int(now), "until": int(now + AUTO_REST_DAYS * DAY), "auto": True,
                                 "label": (meta[sid].get("title") or "")[:120]}
    auto = {}
    for sid, row in meta.items():
        key = season_from_title(row.get("title"))
        if key is None and sid in songs:
            key = season_from_plays([e.ts for e in songs[sid]])
        if key:
            auto[sid] = key

    def fn(s):
        s["rest"].update(new_rest)
        s["auto_season"] = auto
        s["checked_at"] = now
        s["rest"] = {k: v for k, v in s["rest"].items() if float(v.get("until") or 0) > now - 7 * DAY}
        s["grace"] = {k: v for k, v in s["grace"].items() if v > now}
    return _change(user, fn)


# ── back in rotation ─────────────────────────────────────────────────────────

def _ago(now: float, ts: float) -> str:
    return datetime.fromtimestamp(ts, IST).strftime("%b %Y")


def back_in_rotation(user: str, events: list, meta: dict, now: float = None, limit: int = BACK_LIMIT,
                     blocked: set = None) -> list:
    """Songs loved long ago and quiet for two months, as discovery-shaped items. The pick changes
    each day (a seeded draw from the best), so the shelf is not the same list every time."""
    now = time.time() if now is None else now
    state = load(user)
    if not state["prefs"]["back"]:
        return []
    off = set(blocked or ()) | resting_ids(state, now) | out_of_season_ids(state, now)
    cands = []
    for sid, plays in _by_song(events, user).items():
        if sid not in meta or sid in off:
            continue
        last = plays[-1].ts
        old_full = sum(1 for e in plays if e.ratio >= FULL_RATIO and e.ts < now - BACK_OLD_DAYS * DAY)
        skips = sum(1 for e in plays if e.ratio < SKIP_RATIO)
        if old_full < BACK_FULL_PLAYS or last > now - BACK_QUIET_DAYS * DAY or skips / len(plays) >= BACK_MAX_SKIP_RATE:
            continue
        cands.append((sid, old_full, last, len(plays)))
    cands.sort(key=lambda c: (-c[1], c[2]))
    pool = cands[:max(limit * 3, limit)]
    rng = random.Random(f"{user}:{today_ist(now).isoformat()}")
    # weighted draw without replacement (Efraimidis-Spirakis): more plays, more likely, never certain
    keyed = sorted(pool, key=lambda c: rng.random() ** (1.0 / math.sqrt(c[1])), reverse=True)
    items = []
    for rank, (sid, full, last, n) in enumerate(keyed[:limit], 1):
        row = meta[sid]
        items.append({"rank": rank, "navidrome_id": sid, "title": row.get("title", ""),
                      "artist": row.get("artist") or "Unknown", "album": row.get("album") or "",
                      "kind": "back", "plays": n, "full_plays": full,
                      "last_played": datetime.fromtimestamp(last, IST).date().isoformat(),
                      "why": f"You played it {full} times, last in {_ago(now, last)}"})
    return items


# ── what the app shows ───────────────────────────────────────────────────────

def snapshot(user: str, meta: dict, now: float = None) -> dict:
    now = time.time() if now is None else now
    state = load(user)
    resting = []
    for sid in sorted(resting_ids(state, now), key=lambda s: state["rest"][s]["until"]):
        r = state["rest"][sid]
        row = meta.get(sid) or {}
        resting.append({"song_id": sid, "title": row.get("title") or r.get("label") or sid,
                        "artist": row.get("artist") or "", "until": int(r["until"]), "since": int(r.get("since") or 0),
                        "auto": bool(r.get("auto"))})
    seasonal = []
    day = today_ist(now)
    for sid in sorted(set(state["season"]) | set(state["auto_season"])):
        key = effective_season(state, sid)
        if not key or sid not in meta:
            continue
        row = meta[sid]
        seasonal.append({"song_id": sid, "title": row.get("title", ""), "artist": row.get("artist") or "",
                         "season": key, "label": SEASONS[key][0], "in_season": in_window(key, day),
                         "manual": sid in state["season"]})
    return {"resting": resting, "seasonal": seasonal, "seasons": seasons_now(now), "prefs": state["prefs"]}


# ── routes ───────────────────────────────────────────────────────────────────

def register_rotation_routes(app, require_auth, get_engine):
    """`get_engine()` is server.py's `_v3_engine` (None while the recommender starts)."""
    from flask import g, jsonify, request

    def engine_or_503():
        eng = get_engine()
        if eng is None:
            return None, (jsonify({"error": "The recommender is starting up. Try again in a minute."}), 503)
        return eng, None

    def body():
        b = request.get_json(silent=True)
        return b if isinstance(b, dict) else {}

    def song_id(b):
        sid = str(b.get("song_id") or "").strip()
        return sid if sid else None

    @app.route("/rotation", methods=["GET"])
    @require_auth
    def rotation_get():
        eng, err = engine_or_503()
        if err:
            return err
        from navivibe import discover
        now = time.time()
        try:
            refresh(g.username, discover._all_events(eng, now), eng.cat.meta, now)
        except Exception:
            log.exception("rotation refresh failed for %s", g.username)
        return jsonify(snapshot(g.username, eng.cat.meta, now))

    @app.route("/rotation/rest", methods=["POST"])
    @require_auth
    def rotation_rest():
        b = body()
        sid, days = song_id(b), clean_days(b.get("days"))
        if sid is None:
            return jsonify({"error": "song_id is required."}), 400
        if days is None:
            return jsonify({"error": f"days must be a whole number from {MIN_REST_DAYS} to {MAX_REST_DAYS}."}), 400
        entry = rest(g.username, sid, days, str(b.get("label") or ""))
        return jsonify({"song_id": sid, "until": entry["until"], "days": days})

    @app.route("/rotation/rest", methods=["DELETE"])
    @require_auth
    def rotation_unrest():
        sid = song_id(body())
        if sid is None:
            return jsonify({"error": "song_id is required."}), 400
        return jsonify({"song_id": sid, "removed": unrest(g.username, sid)})

    @app.route("/rotation/season", methods=["PUT"])
    @require_auth
    def rotation_season():
        b = body()
        sid = song_id(b)
        if sid is None:
            return jsonify({"error": "song_id is required."}), 400
        key = b.get("season")
        if key is not None and not isinstance(key, str):
            return jsonify({"error": "season must be a season key, \"none\" or null."}), 400
        if not set_season(g.username, sid, key):
            return jsonify({"error": f"season must be one of {', '.join(SEASONS)}, \"none\" or null."}), 400
        return jsonify({"song_id": sid, "season": key})

    @app.route("/rotation/prefs", methods=["PUT"])
    @require_auth
    def rotation_prefs():
        b = body()
        bad = [k for k in b if k not in DEFAULT_PREFS or not isinstance(b[k], bool)]
        if bad:
            return jsonify({"error": "Only auto_rest, seasons and back are settings, each true or false."}), 400
        return jsonify({"prefs": set_prefs(g.username, **b)})

    @app.route("/rotation/back", methods=["GET"])
    @require_auth
    def rotation_back():
        eng, err = engine_or_503()
        if err:
            return err
        try:
            limit = max(1, min(60, int(request.args.get("limit", BACK_LIMIT))))
        except ValueError:
            return jsonify({"error": "limit must be a whole number."}), 400
        from navivibe import discover, taste_exclusions
        now = time.time()
        meta = eng.cat.meta
        blocked = taste_exclusions._excluded_ids(g.username, meta)      # the "never" list; rest and season are added below
        items = back_in_rotation(g.username, discover._all_events(eng, now), meta, now, limit, blocked)
        return jsonify({"count": len(items), "items": items})
