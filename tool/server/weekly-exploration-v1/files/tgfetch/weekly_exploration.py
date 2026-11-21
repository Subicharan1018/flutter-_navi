"""
tgfetch/weekly_exploration.py  (weekly-exploration-v1)
─────────────────────────────────────────────────────
Weekly Exploration: about 20 songs a week the listener does not own, picked from their own
taste, heard as a 30 s preview first. Keep a song and it is fetched; do nothing and it
expires after 2 weeks; "Not for me" and it never comes back.

The picking is here (not on the shuffle server) because this is where the library matcher
(`library_sweep`, the same one the Exportify import uses), fetch.db and the download scheduler
already live. The shuffle server only sends the listener's taste ("seeds": top artists of the
last weeks, their languages, what they never want) through the signed bridge.

  Sources      Deezer `related` artists (names only: from this server Deezer hides tracks and
               previews) + the iTunes Search API (30 s `previewUrl`, cover, length), both
               public, no key, called from the server only, throttled and cached.
  build()      seeds -> candidates -> filters -> 20 picks, 2/3 "near", 1/3 "far", at most 2
               songs an artist, the listener's language mix, nothing owned / tombstoned /
               already on a wishlist / a remix, karaoke or live cut.
  keep()       the pick joins ONE per-listener Exportify import named "Weekly Exploration".
               Fetching it is `exportify.tick()`: the same night window, per-night cap, disk
               floor and one-batch-at-a-time rule as the Spotify wishlist. There is no second
               scheduler. The only addition is the weekly cap (`weekly_prefs.cap`): a Keep
               over the cap waits, still "kept", and is released by `release_waiting()`.
  expire()     untouched picks go after 14 days and are not suggested again for 6 months.

A pick's state: pending · kept · skipped · expired.
"""

import json
import logging
import random
import re
import time
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

from tgfetch import exportify as ex
from tgfetch.library_sweep import Index, split_names, share_artist, versions

log = logging.getLogger("tgfetch.weekly")

IMPORT_NAME = "Weekly Exploration"
PICKS = 20                       # a week's list (the research doc says 20-25)
FAR_SHARE = 3                    # one pick in three is "far" (two steps from what you play)
MAX_PER_ARTIST = 2
EXPIRE_S = 14 * 86400            # an untouched pick goes after two weeks
SHOW_KEPT_S = 30 * 86400         # a kept pick stays on the page this long (with its download state)
TOMBSTONE_S = 183 * 86400        # not suggested again for six months
ARTIST_SNOOZE_S = 90 * 86400     # two "Not for me" on one artist in 90 days: the artist rests 90 days
ARTIST_SNOOZE_AFTER = 2
WEEK_S = 7 * 86400               # the weekly cap counts Keeps handed to the download queue in this window
DEFAULT_CAP, MAX_CAP = 10, 25
MIN_S, MAX_S = 60.0, 600.0       # a "song": not a skit, not a mix
OWNED_SLACK_S = ex.NEAR_SLACK_S  # same title + artist within 25 s counts as owned: not worth suggesting
MAX_CALLS = 70                   # outside calls one build may make
BUILD_STALE_S = 20 * 60          # a build still "running" after this has died
RETRY_FAILED_S = 3600
IST = timezone(timedelta(hours=5, minutes=30))
_STATES = ("pending", "kept", "skipped", "expired")
_HOSTS = (".mzstatic.com", ".apple.com")   # where a preview or a cover may come from

SCHEMA = """
CREATE TABLE IF NOT EXISTS weekly_picks (
    id          INTEGER PRIMARY KEY,
    user        TEXT NOT NULL,
    week        TEXT NOT NULL,
    key         TEXT NOT NULL,
    title       TEXT NOT NULL,
    artist      TEXT NOT NULL,
    album       TEXT NOT NULL DEFAULT '',
    year        INTEGER,
    duration_s  REAL,
    source_id   TEXT,
    preview_url TEXT,
    cover_url   TEXT,
    reason      TEXT NOT NULL DEFAULT '',
    kind        TEXT NOT NULL DEFAULT 'near',
    language    TEXT NOT NULL DEFAULT '',
    state       TEXT NOT NULL DEFAULT 'pending',
    created_at  REAL NOT NULL,
    acted_at    REAL,
    queued_at   REAL,
    song_row    INTEGER,
    UNIQUE (user, key, week)
);
CREATE INDEX IF NOT EXISTS weekly_picks_user ON weekly_picks(user, state);
CREATE TABLE IF NOT EXISTS weekly_tombstones (
    user  TEXT NOT NULL,
    key   TEXT NOT NULL,
    kind  TEXT NOT NULL,
    until REAL NOT NULL,
    PRIMARY KEY (user, key, kind)
);
CREATE TABLE IF NOT EXISTS weekly_prefs (
    user       TEXT PRIMARY KEY,
    enabled    INTEGER NOT NULL DEFAULT 1,
    cap        INTEGER NOT NULL DEFAULT 10,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS weekly_builds (
    user        TEXT PRIMARY KEY,
    week        TEXT NOT NULL,
    status      TEXT NOT NULL,          -- running | done | empty | failed
    started_at  REAL NOT NULL,
    finished_at REAL,
    picks       INTEGER NOT NULL DEFAULT 0,
    note        TEXT
);
"""


def ensure_schema(conn) -> None:
    ex.ensure_schema(conn)
    conn.executescript(SCHEMA)


def week_of(now: float) -> str:
    """The week a pick belongs to: the date of that week's Monday in India."""
    d = datetime.fromtimestamp(now, IST).date()
    return (d - timedelta(days=d.weekday())).isoformat()


def artist_key(artist: str) -> str:
    return (split_names(artist) or [""])[0]


def pick_key(title: str, artist: str) -> str:
    return ex.song_key("", title, artist)


# ── the outside world ────────────────────────────────────────────────────────

def _http_json(url: str, timeout: float = 8.0):
    req = urllib.request.Request(url, headers={"User-Agent": "NaviVibe-server/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:      # noqa: S310 (fixed https hosts)
        return json.loads(r.read(2_000_000).decode("utf-8", "replace"))


def _ok_url(url) -> str | None:
    """An https link on Apple's CDN, nothing else: a preview or cover the app will open."""
    try:
        p = urllib.parse.urlparse(str(url or ""))
    except ValueError:
        return None
    host = (p.hostname or "").lower()
    if p.scheme != "https" or not any(host.endswith(h) for h in _HOSTS):
        return None
    return p.geturl()


class Sources:
    """Candidate songs for a build. Public APIs only, no keys, no user data in any request: an artist's
    name is the only thing sent. `get(url)` returns parsed JSON (or raises); tests pass a fake."""

    DEEZER_GAP, ITUNES_GAP = 0.25, 3.2       # iTunes allows about 20 calls a minute

    def __init__(self, get=None, sleep=time.sleep, itunes_gap: float | None = None, country: str = "IN"):
        self.get, self.sleep, self.country = get or _http_json, sleep, country
        self.gap = {"deezer": self.DEEZER_GAP, "itunes": self.ITUNES_GAP if itunes_gap is None else itunes_gap}
        self.last: dict[str, float] = {}
        self.calls = 0
        self.cache: dict[str, object] = {}

    def _call(self, host: str, url: str):
        if url in self.cache:
            return self.cache[url]
        if self.calls >= MAX_CALLS:
            return None
        wait = self.gap[host] - (time.monotonic() - self.last.get(host, -1e9))
        if wait > 0:
            self.sleep(wait)
        self.last[host] = time.monotonic()
        self.calls += 1
        try:
            body = self.get(url)
        except Exception as e:                    # a source being down is normal: never log what was asked
            log.info("weekly: %s call failed (%s)", host, type(e).__name__)
            body = None
        self.cache[url] = body
        return body

    def related(self, name: str, limit: int = 6) -> list[str]:
        """Names of artists Deezer says are related to `name` (empty when it doesn't know them)."""
        q = urllib.parse.quote(name)
        found = self._call("deezer", f"https://api.deezer.com/search/artist?q={q}&limit=3") or {}
        hit = next((a for a in found.get("data") or [] if share_artist(a.get("name", ""), name)), None)
        if not hit:
            return []
        rel = self._call("deezer", f"https://api.deezer.com/artist/{int(hit['id'])}/related?limit={int(limit) + 2}") or {}
        return [a["name"] for a in (rel.get("data") or []) if a.get("name") and not share_artist(a["name"], name)][:limit]

    def songs(self, artist: str, limit: int = 25) -> list[dict]:
        """The artist's songs on iTunes, in its own relevance order. Only real songs by that artist."""
        q = urllib.parse.quote(artist)
        body = self._call("itunes", f"https://itunes.apple.com/search?term={q}&entity=song&attribute=artistTerm"
                                    f"&country={self.country}&limit={int(limit)}") or {}
        return [c for c in (self._candidate(r) for r in body.get("results") or []) if c and share_artist(c["artist"], artist)]

    def find(self, artist: str, title: str) -> dict | None:
        """One named song (for hints from ListenBrainz)."""
        q = urllib.parse.quote(f"{artist} {title}")
        body = self._call("itunes", f"https://itunes.apple.com/search?term={q}&entity=song&country={self.country}&limit=5") or {}
        for r in body.get("results") or []:
            c = self._candidate(r)
            if c and share_artist(c["artist"], artist) and ex.clean_title(c["title"]) == ex.clean_title(title):
                return c
        return None

    @staticmethod
    def _candidate(r: dict) -> dict | None:
        if not isinstance(r, dict) or r.get("kind") != "song" or not r.get("trackName") or not r.get("artistName"):
            return None
        ms = r.get("trackTimeMillis")
        cover = _ok_url((r.get("artworkUrl100") or "").replace("100x100bb", "600x600bb"))
        year = re.match(r"(\d{4})", str(r.get("releaseDate") or ""))
        return {"source_id": str(r.get("trackId") or ""), "title": str(r["trackName"])[:200],
                "artist": str(r["artistName"])[:300], "album": str(r.get("collectionName") or "")[:200],
                "year": int(year.group(1)) if year else None,
                "duration_s": round(ms / 1000.0, 1) if isinstance(ms, (int, float)) and ms > 0 else None,
                "preview_url": _ok_url(r.get("previewUrl")), "cover_url": cover}


# ── picking ──────────────────────────────────────────────────────────────────

def _quotas(n: int, weights: dict) -> dict:
    """Split n places by weight (largest remainder). Every language present gets its share."""
    total = sum(weights.values()) or 1.0
    raw = {k: n * v / total for k, v in weights.items()}
    out = {k: int(v) for k, v in raw.items()}
    for k in sorted(raw, key=lambda k: (raw[k] - out[k], weights[k]), reverse=True)[: n - sum(out.values())]:
        out[k] += 1
    return out


def _round_robin(pool: list[dict], n: int, per_artist: Counter, seen: set) -> list[dict]:
    """Up to n from `pool` (already in priority order), one artist at a time, so no artist
    runs the list and nobody gets more than MAX_PER_ARTIST (counted across the whole list)."""
    by_artist: dict[str, list[dict]] = {}
    for c in pool:
        by_artist.setdefault(artist_key(c["artist"]), []).append(c)
    out = []
    while len(out) < n:
        moved = False
        for a, items in by_artist.items():
            if len(out) >= n:
                break
            while items and (items[0]["key"] in seen):
                items.pop(0)
            if items and per_artist[a] < MAX_PER_ARTIST:
                c = items.pop(0)
                out.append(c)
                seen.add(c["key"])
                per_artist[a] += 1
                moved = True
        if not moved:
            break
    return out


def _take(pool: list[dict], n: int, weights: dict, per_artist: Counter, seen: set) -> list[dict]:
    """n picks from `pool`, shared out across languages like the listener's own mix."""
    if n <= 0 or not pool:
        return []
    langs = {c["language"] for c in pool}
    floor = min([w for w in weights.values() if w > 0] or [1.0]) * 0.5
    quota = _quotas(n, {lang: weights.get(lang, 0.0) or floor for lang in langs})
    out = []
    for lang, q in sorted(quota.items(), key=lambda kv: -kv[1]):
        out += _round_robin([c for c in pool if c["language"] == lang], q, per_artist, seen)
    if len(out) < n:                              # a language ran short: the rest of the list fills in
        out += _round_robin(pool, n - len(out), per_artist, seen)
    return out


def select(cands: list[dict], size: int, weights: dict) -> list[dict]:
    """The list: two thirds near, one third far, language shares like the listener's, at most
    2 songs an artist. Far picks are spread through the list (every third place), not saved for the end."""
    near = [c for c in cands if c["kind"] != "far"]
    far = [c for c in cands if c["kind"] == "far"]
    per_artist: Counter = Counter()
    seen: set = set()
    far_n = size // FAR_SHARE
    got_far = _take(far, far_n, weights, per_artist, seen)
    got_near = _take(near, size - len(got_far), weights, per_artist, seen)
    if len(got_near) + len(got_far) < size:       # not enough near songs: far ones may take their places
        got_far += _take([c for c in far if c["key"] not in seen], size - len(got_near) - len(got_far),
                         weights, per_artist, seen)
    out, f = [], iter(got_far)
    for i, c in enumerate(got_near):
        out.append(c)
        if i % 2 == 1:
            nxt = next(f, None)
            if nxt:
                out.append(nxt)
    out += list(f)
    return out


def gather(seeds: dict, sources: Sources) -> list[dict]:
    """Candidates in priority order, each with its kind (near | far), language, seed and reason."""
    artists = sorted(seeds.get("artists") or [], key=lambda a: -float(a.get("plays") or 0))[:8]
    mine = {ex.clean_title(a["name"]) for a in artists}
    out, used = [], set(mine)

    def add(songs, kind, language, reason, seed):
        for rank, s in enumerate(songs):
            out.append({**s, "kind": kind, "language": language, "reason": reason, "seed": seed, "rank": rank,
                        "key": pick_key(s["title"], s["artist"])})

    for a in artists[:3]:                          # more from the artists played most
        add(sources.songs(a["name"], 12), "near", a.get("language") or "",
            f"More from {a['name']}, one of your most played", a["name"])
    seconds: list[tuple[str, dict]] = []
    for a in artists:                              # near: artists Deezer relates to a seed
        rel = [r for r in sources.related(a["name"], 5) if ex.clean_title(r) not in used]
        for r in rel[:3]:
            used.add(ex.clean_title(r))
            add(sources.songs(r, 8), "near", a.get("language") or "", f"Like {a['name']}", a["name"])
        seconds += [(r, a) for r in rel[3:5]]
    for e in seeds.get("extra") or []:             # near: a hint from a service the listener already uses
        c = sources.find(e["artist"], e["title"])
        if c:
            add([c], "near", "", f"Suggested by {e.get('source') or 'ListenBrainz'}", e["artist"])
    for r, a in seconds[:6]:                       # far: one step further out
        for r2 in [x for x in sources.related(r, 4) if ex.clean_title(x) not in used][:2]:
            used.add(ex.clean_title(r2))
            add(sources.songs(r2, 6), "far", a.get("language") or "", f"Two steps out from {a['name']}", a["name"])
    return out


def _blocked_artist(name: str, blocked: list[str]) -> bool:
    return any(share_artist(name, b) for b in blocked if b)


def filter_candidates(conn, user: str, cands: list[dict], library: list[dict] | None, blocked_artists: list[str],
                      now: float) -> list[dict]:
    """Drop what must not be suggested. The order of the list is kept."""
    ensure_schema(conn)
    tomb = {(r["key"], r["kind"]) for r in conn.execute(
        "SELECT key, kind FROM weekly_tombstones WHERE user=? AND until>?", (user, now))}
    on_lists = {r[0] for r in conn.execute("SELECT key FROM exportify_songs WHERE user=?", (user,))}
    live = {r[0] for r in conn.execute(
        "SELECT key FROM weekly_picks WHERE user=? AND state IN ('pending','kept')", (user,))}
    idx = Index(library) if library else None
    out, seen = [], set()
    for c in cands:
        k = c["key"]
        if k in seen or k in on_lists or k in live or (k, "song") in tomb or (artist_key(c["artist"]), "artist") in tomb:
            continue
        if versions(c["title"]):                   # remix, karaoke, live, sped up: not "a new song"
            continue
        if c["duration_s"] and not MIN_S <= c["duration_s"] <= MAX_S:
            continue
        if _blocked_artist(c["artist"], blocked_artists):
            continue
        if idx is not None and idx.find(c["title"], c["artist"], c["duration_s"], OWNED_SLACK_S):
            continue
        seen.add(k)
        out.append(c)
    return out


def build(conn, user: str, seeds: dict, sources: Sources, library: list[dict] | None, now: float | None = None,
          size: int = PICKS) -> int:
    """Make this week's list for `user` and store it. Returns how many picks. Safe to run twice in a
    week: songs already picked this week are kept, and the list is only topped up to `size`."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    week = week_of(now)
    expire(conn, user, now)
    have = conn.execute("SELECT COUNT(*) FROM weekly_picks WHERE user=? AND week=? AND state IN ('pending','kept')",
                        (user, week)).fetchone()[0]
    weights: dict = defaultdict(float)
    for a in seeds.get("artists") or []:
        weights[a.get("language") or ""] += float(a.get("plays") or 0)
    cands = gather(seeds, sources) if seeds.get("artists") or seeds.get("extra") else []
    cands = filter_candidates(conn, user, cands, library, list(seeds.get("blocked_artists") or []), now)
    picks = select(cands, max(0, size - have), dict(weights))
    conn.execute("BEGIN")
    try:
        for c in picks:
            conn.execute(
                "INSERT OR IGNORE INTO weekly_picks (user, week, key, title, artist, album, year, duration_s, source_id, "
                "preview_url, cover_url, reason, kind, language, state, created_at) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'pending', ?)",
                (user, week, c["key"], c["title"], c["artist"], c["album"], c["year"], c["duration_s"],
                 c["source_id"], c["preview_url"], c["cover_url"], c["reason"], c["kind"], c["language"], now))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    log.info("weekly: %d picks for one listener (%d candidates, %d outside calls)", len(picks), len(cands), sources.calls)
    return len(picks)


# ── prefs, reading ───────────────────────────────────────────────────────────

def get_prefs(conn, user: str) -> dict:
    r = conn.execute("SELECT enabled, cap FROM weekly_prefs WHERE user=?", (user,)).fetchone()
    return {"enabled": bool(r["enabled"]) if r else True, "cap": int(r["cap"]) if r else DEFAULT_CAP}


def set_prefs(conn, user: str, enabled: bool | None = None, cap: int | None = None, now: float | None = None) -> dict:
    ensure_schema(conn)
    cur = get_prefs(conn, user)
    if enabled is not None:
        cur["enabled"] = bool(enabled)
    if cap is not None:
        cur["cap"] = max(0, min(MAX_CAP, int(cap)))
    conn.execute("INSERT INTO weekly_prefs (user, enabled, cap, updated_at) VALUES (?,?,?,?) "
                 "ON CONFLICT(user) DO UPDATE SET enabled=excluded.enabled, cap=excluded.cap, updated_at=excluded.updated_at",
                 (user, int(cur["enabled"]), cur["cap"], time.time() if now is None else now))
    if cur["enabled"] is not False:
        release_waiting(conn, now, user=user)         # a bigger cap lets waiting Keeps go
    return cur


def kept_this_week(conn, user: str, now: float) -> int:
    return conn.execute("SELECT COUNT(*) FROM weekly_picks WHERE user=? AND queued_at>?",
                        (user, now - WEEK_S)).fetchone()[0]


_DL = {"wishlist": "waiting", "skipped_disk": "waiting", "queued": "queued", "downloaded": "ready",
       "owned": "ready", "failed": "failed"}


def _download(conn, p: dict) -> dict:
    """The download state of a kept pick: none | waiting | queued | ready | failed."""
    if p["state"] != "kept":
        return {"state": "none", "song_id": None}
    if not p["song_row"]:
        return {"state": "waiting", "song_id": None}          # kept, but over this week's cap
    r = conn.execute("SELECT state, nd_song_id, error FROM exportify_songs WHERE id=?", (p["song_row"],)).fetchone()
    if r is None:
        return {"state": "waiting", "song_id": None}
    return {"state": _DL.get(r["state"], "waiting"), "song_id": r["nd_song_id"] if r["state"] in ("downloaded", "owned") else None}


def expire(conn, user: str | None = None, now: float | None = None) -> int:
    """Untouched picks older than two weeks go, and are not suggested again for six months."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    where, args = "state='pending' AND created_at<?", [now - EXPIRE_S]
    if user:
        where += " AND user=?"
        args.append(user)
    rows = conn.execute(f"SELECT id, user, key FROM weekly_picks WHERE {where}", args).fetchall()
    for r in rows:
        conn.execute("UPDATE weekly_picks SET state='expired', acted_at=? WHERE id=?", (now, r["id"]))
        _tombstone(conn, r["user"], r["key"], "song", now + TOMBSTONE_S)
    return len(rows)


def current(conn, user: str, now: float | None = None) -> dict:
    """What the Weekly Exploration page shows."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    expire(conn, user, now)
    prefs = get_prefs(conn, user)
    week = week_of(now)
    b = conn.execute("SELECT * FROM weekly_builds WHERE user=?", (user,)).fetchone()
    b = dict(b) if b else None
    running = bool(b and b["status"] == "running" and now - b["started_at"] < BUILD_STALE_S)
    done_now = bool(b and b["week"] == week and b["status"] in ("done", "empty"))
    failed_recently = bool(b and b["week"] == week and b["status"] == "failed" and now - (b["finished_at"] or 0) < RETRY_FAILED_S)
    if prefs["enabled"]:
        imp = _import_id(conn, user)
        if imp:
            ex.settle(conn, imp, now)
    rows = [dict(r) for r in conn.execute(
        "SELECT * FROM weekly_picks WHERE user=? AND (state='pending' OR (state='kept' AND acted_at>?)) "
        "ORDER BY week DESC, id", (user, now - SHOW_KEPT_S))]
    picks = [{
        "id": p["id"], "title": p["title"], "artist": p["artist"], "album": p["album"], "year": p["year"],
        "duration_s": p["duration_s"], "cover_url": p["cover_url"], "preview_url": p["preview_url"],
        "reason": p["reason"], "kind": p["kind"], "state": p["state"], "week": p["week"],
        "expires_at": (p["created_at"] + EXPIRE_S) if p["state"] == "pending" else None,
        "download": _download(conn, p)} for p in rows]
    note = None
    imp = _import_id(conn, user)
    if imp:
        r = conn.execute("SELECT status, note FROM exportify_plans WHERE import_id=?", (imp,)).fetchone()
        note = r["note"] if r and r["status"] in ("active", "paused_disk") else None
    return {"enabled": prefs["enabled"], "cap": prefs["cap"], "max_cap": MAX_CAP, "week": week,
            "kept_this_week": kept_this_week(conn, user, now),
            "building": running,
            "needs_build": bool(prefs["enabled"] and not running and not done_now and not failed_recently),
            "build_note": (b or {}).get("note") if b and b["week"] == week else None,
            "download_note": note,
            "night": {"from": ex.NIGHT_START_H, "to": ex.NIGHT_END_H},
            "picks": picks}


# ── builds (the API runs build() in a thread and records it here) ────────────

def begin_build(conn, user: str, now: float | None = None) -> bool:
    """Claim the build for this listener (one at a time). False when one is running."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    conn.execute("BEGIN IMMEDIATE")
    try:
        b = conn.execute("SELECT status, started_at FROM weekly_builds WHERE user=?", (user,)).fetchone()
        ok = not (b and b["status"] == "running" and now - b["started_at"] < BUILD_STALE_S)
        if ok:
            conn.execute("INSERT INTO weekly_builds (user, week, status, started_at) VALUES (?,?, 'running', ?) "
                         "ON CONFLICT(user) DO UPDATE SET week=excluded.week, status='running', started_at=excluded.started_at, "
                         "finished_at=NULL, picks=0, note=NULL", (user, week_of(now), now))
        conn.execute("COMMIT")
        return ok
    except Exception:
        conn.execute("ROLLBACK")
        raise


def finish_build(conn, user: str, picks: int | None, error: str | None = None, now: float | None = None) -> None:
    now = time.time() if now is None else now
    if error:
        status, note = "failed", error[:200]
    elif not picks:
        status, note = "empty", "Nothing new to suggest yet. Play a few more songs and check back."
    else:
        status, note = "done", None
    conn.execute("UPDATE weekly_builds SET status=?, finished_at=?, picks=?, note=? WHERE user=?",
                 (status, now, picks or 0, note, user))


# ── acting on a pick ─────────────────────────────────────────────────────────

class PickError(ValueError):
    pass


def _pick(conn, user: str, pick_id: int) -> dict:
    r = conn.execute("SELECT * FROM weekly_picks WHERE id=? AND user=?", (pick_id, user)).fetchone()
    if r is None:
        raise PickError("no such pick")
    return dict(r)


def _tombstone(conn, user: str, key: str, kind: str, until: float) -> None:
    conn.execute("INSERT INTO weekly_tombstones (user, key, kind, until) VALUES (?,?,?,?) "
                 "ON CONFLICT(user, key, kind) DO UPDATE SET until=MAX(until, excluded.until)", (user, key, kind, until))


def _import_id(conn, user: str) -> int | None:
    r = conn.execute("SELECT id FROM exportify_imports WHERE user=? AND name=? ORDER BY id LIMIT 1",
                     (user, IMPORT_NAME)).fetchone()
    return r[0] if r else None


def _ensure_import(conn, user: str, now: float) -> int:
    iid = _import_id(conn, user)
    if iid:
        return iid
    iid = conn.execute("INSERT INTO exportify_imports (user, name, created_at, total_rows) VALUES (?,?,?,0)",
                       (user, IMPORT_NAME, now)).lastrowid
    conn.execute("INSERT INTO exportify_plans (import_id, user, status, updated_at) VALUES (?,?, 'idle', ?)",
                 (iid, user, now))
    return iid


def _enqueue(conn, user: str, p: dict, now: float) -> bool:
    """Hand a kept pick to the Exportify queue (it fetches it at night, under the cap and the disk floor).
    False when this week's cap is used up."""
    if kept_this_week(conn, user, now) >= get_prefs(conn, user)["cap"]:
        return False
    iid = _ensure_import(conn, user, now)
    same = conn.execute("SELECT id FROM exportify_songs WHERE user=? AND key=? ORDER BY id LIMIT 1",
                        (user, p["key"])).fetchone()
    if same:                                       # on a wishlist already (or owned): it is not fetched twice
        row_id = same[0]
    else:
        pos = conn.execute("SELECT COALESCE(MAX(pos), -1) + 1 FROM exportify_songs WHERE import_id=?", (iid,)).fetchone()[0]
        row_id = conn.execute(
            "INSERT INTO exportify_songs (import_id, user, pos, key, isrc, uri, title, artist, album, year, popularity, "
            "duration_s, state, details, updated_at) VALUES (?,?,?,?,NULL,NULL,?,?,?,?,50,?, 'wishlist', '{}', ?)",
            (iid, user, pos, p["key"], p["title"], p["artist"], p["album"], p["year"], p["duration_s"], now)).lastrowid
        conn.execute("UPDATE exportify_imports SET total_rows=total_rows+1 WHERE id=?", (iid,))
    conn.execute("UPDATE weekly_picks SET queued_at=?, song_row=? WHERE id=?", (now, row_id, p["id"]))
    plan = ex.get_plan(conn, iid)
    if plan["status"] not in ("active", "paused_disk"):
        ex.set_plan(conn, iid, {}, status="active", note=f"Downloads tonight, {ex.NIGHT_START_H}–{ex.NIGHT_END_H} am.", now=now)
    return True


def keep(conn, user: str, pick_id: int, now: float | None = None) -> dict:
    """Keep: the pick is yours. It is fetched under the weekly cap (else it waits, still kept)."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    p = _pick(conn, user, pick_id)
    if p["state"] == "kept":
        return {"state": "kept", "download": _download(conn, p)}
    if p["state"] not in ("pending", "skipped"):
        raise PickError("this pick has expired")
    conn.execute("UPDATE weekly_picks SET state='kept', acted_at=? WHERE id=?", (now, pick_id))
    conn.execute("DELETE FROM weekly_tombstones WHERE user=? AND key=? AND kind='song'", (user, p["key"]))
    p = _pick(conn, user, pick_id)
    _enqueue(conn, user, p, now)
    return {"state": "kept", "download": _download(conn, _pick(conn, user, pick_id))}


def skip(conn, user: str, pick_id: int, now: float | None = None) -> dict:
    """Not for me: gone now, not suggested again for six months. Two on one artist rest the artist."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    p = _pick(conn, user, pick_id)
    if p["state"] == "kept" and p["queued_at"]:
        raise PickError("this song is already on its way")
    conn.execute("UPDATE weekly_picks SET state='skipped', acted_at=?, queued_at=NULL, song_row=NULL WHERE id=?", (now, pick_id))
    _tombstone(conn, user, p["key"], "song", now + TOMBSTONE_S)
    a = artist_key(p["artist"])
    n = sum(1 for r in conn.execute("SELECT artist FROM weekly_picks WHERE user=? AND state='skipped' AND acted_at>?",
                                    (user, now - ARTIST_SNOOZE_S)) if artist_key(r["artist"]) == a)
    if a and n >= ARTIST_SNOOZE_AFTER:
        _tombstone(conn, user, a, "artist", now + ARTIST_SNOOZE_S)
    return {"state": "skipped"}


def restore(conn, user: str, pick_id: int, now: float | None = None) -> dict:
    """Undo a "Not for me" (the snackbar's Undo)."""
    now = time.time() if now is None else now
    p = _pick(conn, user, pick_id)
    if p["state"] != "skipped":
        raise PickError("nothing to undo")
    conn.execute("UPDATE weekly_picks SET state='pending', acted_at=NULL WHERE id=?", (pick_id,))
    conn.execute("DELETE FROM weekly_tombstones WHERE user=? AND key=? AND kind='song'", (user, p["key"]))
    n = conn.execute("SELECT COUNT(*) FROM weekly_picks WHERE user=? AND state='skipped' AND acted_at>?",
                     (user, now - ARTIST_SNOOZE_S)).fetchone()[0]
    if n < ARTIST_SNOOZE_AFTER:
        conn.execute("DELETE FROM weekly_tombstones WHERE user=? AND key=? AND kind='artist'", (user, artist_key(p["artist"])))
    return {"state": "pending"}


def release_waiting(conn, now: float | None = None, user: str | None = None) -> int:
    """Kept picks that were over the weekly cap go to the queue as room appears (oldest Keep first).
    Called from the timer's pass and after a Keep or a change of the cap. Returns how many were released."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    where, args = "state='kept' AND queued_at IS NULL", []
    if user:
        where += " AND user=?"
        args.append(user)
    n = 0
    for r in [dict(x) for x in conn.execute(f"SELECT * FROM weekly_picks WHERE {where} ORDER BY acted_at, id", args)]:
        if _enqueue(conn, r["user"], r, now):
            n += 1
    return n
