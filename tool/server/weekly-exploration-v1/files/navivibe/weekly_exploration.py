"""
navivibe/weekly_exploration.py   (weekly-exploration-v1)
───────────────────────────────────────────────────────
Weekly Exploration for the app. The picking lives in tg-fetcher (tgfetch/weekly_exploration.py: it has the
library matcher, fetch.db and the download scheduler). This file does the two things only this server can:

  seeds_from()   what the listener actually plays: their top artists of the last 4 weeks by completed
                 plays (partly heard songs count a little, skipped songs not at all), with each artist's
                 language, plus what they marked "never recommend". Names only: no song ids, no times.
  lb_hints()     optional: a few suggestions from the listener's own ListenBrainz account, when Navidrome
                 holds their ListenBrainz key (Settings > ListenBrainz). Read-only on Navidrome's database;
                 the key goes to api.listenbrainz.org only, is never logged, stored or sent anywhere else.

  GET  /weekly/exploration                  the page; the first open of a week also sends the seeds, so the
                                            list is made then (about a minute: `building` is true meanwhile)
  POST /weekly/exploration/<id>/keep|skip|restore
  PUT  /weekly/exploration/prefs            {"enabled"?: bool, "cap"?: 0..25}

Same rules as /fetch and /exportify: signed in, download access (403 otherwise, tg-fetcher not called), the
call to tg-fetcher is signed.
"""

import logging
import sqlite3
import time
from collections import defaultdict

from flask import g, jsonify, request

from navivibe import fetch_proxy, taste_exclusions

log = logging.getLogger("navivibe.weekly")

WINDOW_DAYS = 28
WIDE_DAYS = 120                  # a quiet listener: look further back before giving up
MIN_ARTISTS = 3
MIN_PLAYS = 2.0                  # an artist needs this much listening to be a seed
MAX_ARTISTS = 8
HALF_PLAY = 0.2                  # a song heard past the skip line but not to the end
FULL_RATIO = 0.5                 # "completed": not skipped before half (the auto-download rule)
SKIP_RATIO = 0.3                 # recsys.data.SKIP_RATIO: below this a play is a skip
LB_TTL_S = 24 * 3600
LB_MAX = 20
NAVIDROME_DB_URI = "file:/DATA/AppData/navidrome/data/navidrome.db?mode=ro"


# ── seeds ────────────────────────────────────────────────────────────────────

def _first_artist(name: str) -> str:
    return taste_exclusions.first_name(name)


def seeds_from(events, meta: dict, user: str, now: float, blocked_artists=()) -> dict:
    """{"artists": [{"name", "language", "plays"}], "blocked_artists": [...], "extra": []} for `user`.
    `events` have .user .song .ts .ratio; `meta[song]` has "artist" and "language"."""
    mine = [e for e in events if e.user == user]
    for days in (WINDOW_DAYS, WIDE_DAYS):
        since = now - days * 86400
        plays: dict[str, float] = defaultdict(float)
        names: dict[str, str] = {}
        langs: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
        for e in mine:
            if e.ts < since or e.ratio < SKIP_RATIO:
                continue
            row = meta.get(e.song) or {}
            name = _first_artist(row.get("artist") or "")
            if not name:
                continue
            k = taste_exclusions.key_of("artist", name)
            w = 1.0 if e.ratio >= FULL_RATIO else HALF_PLAY
            plays[k] += w
            names.setdefault(k, name)
            langs[k][row.get("language") or ""] += w
        top = [k for k in sorted(plays, key=lambda k: (-plays[k], k)) if plays[k] >= MIN_PLAYS - 1e-9][:MAX_ARTISTS]
        if len(top) >= MIN_ARTISTS or days == WIDE_DAYS:
            break
    artists = [{"name": names[k], "language": max(langs[k], key=langs[k].get), "plays": round(plays[k], 1)} for k in top]
    return {"artists": artists, "blocked_artists": [b for b in blocked_artists if b][:500], "extra": []}


def blocked_artist_names(user: str) -> list:
    return [r.get("value") or r.get("label") or "" for r in taste_exclusions.list_for(user) if r["kind"] == "artist"]


# ── ListenBrainz (optional) ──────────────────────────────────────────────────

_lb_cache: dict[str, tuple[float, list]] = {}


def _lb_key(user: str) -> str | None:
    try:
        c = sqlite3.connect(NAVIDROME_DB_URI, uri=True, timeout=5)
        try:
            r = c.execute("SELECT p.value FROM user_props p JOIN user u ON u.id=p.user_id "
                          "WHERE p.key='ListenBrainzSessionKey' AND lower(u.user_name)=lower(?)", (user,)).fetchone()
        finally:
            c.close()
    except sqlite3.Error:
        return None
    return (r[0] or None) if r else None


def _lb_http(method: str, url: str, token: str, body=None):
    import requests
    r = requests.request(method, url, json=body, timeout=6, headers={"Authorization": f"Token {token}"})
    r.raise_for_status()
    return r.json()


def lb_hints(user: str, now: float | None = None, key=_lb_key, http=_lb_http) -> list:
    """Up to LB_MAX {"artist", "title", "source"} from the listener's ListenBrainz recommendations.
    Any failure (no account, no data, network) is an empty list. Cached for a day."""
    now = time.time() if now is None else now
    hit = _lb_cache.get(user)
    if hit and now - hit[0] < LB_TTL_S:
        return hit[1]
    out: list = []
    try:
        token = key(user)
        if token:
            who = http("GET", "https://api.listenbrainz.org/1/validate-token", token)
            name = who.get("user_name") if who.get("valid") else None
            if name:
                rec = http("GET", f"https://api.listenbrainz.org/1/cf/recommendation/user/{name}/recording?count={LB_MAX}", token)
                mbids = [m["recording_mbid"] for m in ((rec.get("payload") or {}).get("mbids") or []) if m.get("recording_mbid")][:LB_MAX]
                if mbids:
                    meta = http("POST", "https://api.listenbrainz.org/1/metadata/recording/", token,
                                {"recording_mbids": mbids, "inc": "artist"})
                    for m in mbids:
                        d = meta.get(m) or {}
                        t, a = (d.get("recording") or {}).get("name"), (d.get("artist") or {}).get("name")
                        if t and a:
                            out.append({"artist": a[:120], "title": t[:160], "source": "ListenBrainz"})
    except Exception as e:                       # the account is a bonus: never an error for the listener
        log.info("weekly: listenbrainz hints unavailable (%s)", type(e).__name__)
        out = []
    _lb_cache[user] = (now, out)
    return out


# ── routes ───────────────────────────────────────────────────────────────────

_ACTIONS = {"keep", "skip", "restore"}


def _json(resp):
    """(payload dict or None, status) from a proxy answer."""
    body, code = resp
    return body.get_json(silent=True), code


def register_weekly_routes(app, require_auth, get_engine):
    """`get_engine()` is server.py's `_v3_engine` (None while the recommender starts)."""

    def seeds_for(user: str) -> dict | None:
        eng = get_engine()
        if eng is None:
            return None
        from navivibe import discover
        now = time.time()
        s = seeds_from(discover._all_events(eng, now), eng.cat.meta, user, now, blocked_artist_names(user))
        s["extra"] = lb_hints(user, now)
        return s

    @app.route("/weekly/exploration", methods=["GET"])
    @require_auth
    def weekly_get():
        resp = fetch_proxy._forward("GET", "/weekly/current")
        data, code = _json(resp)
        if code != 200 or not isinstance(data, dict) or not data.get("needs_build"):
            return resp
        seeds = seeds_for(g.username)
        if seeds is None:                         # the recommender is still starting: the list is made on the next open
            data["needs_build"] = False
            data["building"] = True
            return jsonify(data), 200
        started, scode = _json(fetch_proxy._forward("POST", "/weekly/build", seeds))
        data["needs_build"] = False
        data["building"] = bool(scode == 202 and (started or {}).get("started")) or (started or {}).get("reason") == "running"
        return jsonify(data), 200

    @app.route("/weekly/exploration/<int:pick_id>/<action>", methods=["POST"])
    @require_auth
    def weekly_act(pick_id, action):
        if action not in _ACTIONS:
            return jsonify({"error": "no such action"}), 404
        return fetch_proxy._forward("POST", f"/weekly/picks/{pick_id}/{action}", {})

    @app.route("/weekly/exploration/prefs", methods=["PUT"])
    @require_auth
    def weekly_prefs():
        body = request.get_json(silent=True) or {}
        out = {}
        if "enabled" in body:
            if not isinstance(body["enabled"], bool):
                return jsonify({"error": "enabled must be true or false."}), 400
            out["enabled"] = body["enabled"]
        if "cap" in body:
            c = body["cap"]
            if isinstance(c, bool) or not isinstance(c, int) or not 0 <= c <= 25:
                return jsonify({"error": "cap must be a whole number from 0 to 25."}), 400
            out["cap"] = c
        return fetch_proxy._forward("PUT", "/weekly/prefs", out)
