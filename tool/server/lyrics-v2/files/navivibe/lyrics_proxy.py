"""
navivibe/lyrics_proxy.py   (lyrics-v1)
──────────────────────────────────────
Synced lyrics from third-party sources, fetched by the server so the web app (whose CSP only allows
this server) and the phone ask one place. For the signed-in user's own display only.

  GET /lyrics/fetch   (signed in)
      ?title=&artist=&album=&duration=<seconds>&song_id=&sources=lrcred,betterlyrics,paxsenix
      &spotify_id=<22 chars>   (only the "paxsenix" source uses it)
  200 {"source": "lrcred", "sync": "word"|"line"|"plain", "lrc": "<enhanced LRC>", "cached": bool}
  404 {"error": "..."}   nothing found, or no source asked for is switched on
  400 / 429              bad request / too many requests

The answer is enhanced LRC: "[mm:ss.xx]<mm:ss.xx>word <mm:ss.xx>word": the format the app already
parses, so word timing and line timing travel the same way.

Sources, tried in the order asked, first synced answer wins (a plain-text answer is the fallback):
  lrcred        https://lrc.red  search.json -> /s/{isrc}.ttml (word) or .lrc (line). Its terms: a
                User-Agent naming this app with a link and a contact address (NAVIVIBE_LYRICS_CONTACT),
                and the app shows "lrc.red" wherever its data is shown.
  betterlyrics  https://api.betterlyrics.org/getLyrics?s&a&al&d -> {"ttml": "..."} (word timed). Keys are
                not being issued; a song nobody has played in the extension answers 401/429 = no result.
  ytmusic       (lyrics-v2) YouTube Music's lyrics, through ytmusicapi run by a small helper in
                tg-fetcher's venv (navivibe/ytmusic_lyrics_helper.py): search the song, require the same
                title and a duration within 4 s, read the lyrics with timestamps (line sync) or as
                text. Only lyrics text is requested; no audio or video. On unless
                NAVIVIBE_YTMUSIC_LYRICS=0. Unofficial: may break YouTube's terms of service.
  paxsenix      OFF unless NAVIVIBE_PAXSENIX_URL is set to a Paxsenix/Spotify-Lyrics-API instance
                (GET {url}/api/lyrics?url=<spotify track url>&format=lrc). It wraps undocumented Spotify
                endpoints and may violate Spotify's terms. The server only forwards a track id; the
                instance's own Spotify cookie lives on that instance, never in this app or here.

lyrics-v2 fixes the lookup for songs whose artist field holds several artists ("A • B", "A, B"): the
search uses the title and the PRIMARY artist only (then the title alone), an artist written in
another script doesn't have to match when the title and duration do, and a song's ISRC (from
catalog.db) skips the search. Cache entries carry a version: a miss written by an older version is
asked again at once; hits never expire.

Each song is cached on disk, per song, readable only by this server (mode 0600); nothing is served
without a sign-in, nothing is cached by browsers or proxies (Cache-Control: private, no-store).
"""

import hashlib
import json
import os
import re
import threading
import time
import xml.etree.ElementTree as ET

from flask import g, jsonify, request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.getenv("NAVIVIBE_LYRICS_CACHE", os.path.join(os.path.dirname(HERE), "lyrics_cache"))
CONTACT = os.getenv("NAVIVIBE_LYRICS_CONTACT", "").strip()
APP_URL = os.getenv("NAVIVIBE_PUBLIC_APP_URL", "https://subimusic.me").rstrip("/")
PAXSENIX_URL = os.getenv("NAVIVIBE_PAXSENIX_URL", "").strip().rstrip("/")
YTMUSIC_ON = os.getenv("NAVIVIBE_YTMUSIC_LYRICS", "1").strip() != "0"
YTMUSIC_PYTHON = os.getenv("NAVIVIBE_YTMUSIC_PYTHON", "/opt/tg-fetcher/venv/bin/python")
YTMUSIC_HELPER = os.path.join(HERE, "ytmusic_lyrics_helper.py")
CATALOG_DB = os.getenv("NAVIVIBE_CATALOG_DB", os.path.join(os.path.dirname(HERE), "catalog.db"))

SOURCES = ("lrcred", "betterlyrics", "ytmusic", "paxsenix")
DEFAULT_SOURCES = ("lrcred", "betterlyrics", "ytmusic")
CACHE_VERSION = 2                # v1 wrote misses that a fixed lookup should retry
TIMEOUT = 8
NEGATIVE_TTL = 6 * 3600          # a song nobody has: ask again after six hours
RATE_PER_MIN = 40                # per user, on top of the server's own limits
MAX_FIELD = 200
MAX_BODY = 600_000               # a TTML file is far smaller than this


def user_agent() -> str:
    who = f"; {CONTACT}" if CONTACT else ""
    return f"NaviVibe-LyricsProxy/1 (+{APP_URL}{who})"


# ── time and text helpers ───────────────────────────────────────────────────────────────────────

_CLOCK = re.compile(r"^(?:(\d+):)?(?:(\d+):)?(\d+(?:\.\d+)?)$")


def parse_clock(value):
    """TTML time ("1:02.345", "00:01:02.345", "62.3", "62.3s") -> milliseconds, or None."""
    if value is None:
        return None
    s = str(value).strip().rstrip("s")
    m = _CLOCK.match(s)
    if not m:
        return None
    a, b, sec = m.groups()
    parts = [p for p in (a, b) if p is not None]
    hours, minutes = (int(parts[0]), int(parts[1])) if len(parts) == 2 else (0, int(parts[0]) if parts else 0)
    return int(round(((hours * 60 + minutes) * 60 + float(sec)) * 1000))


def clock(ms: int) -> str:
    ms = max(0, int(ms))
    return f"{ms // 60000:02d}:{(ms // 1000) % 60:02d}.{(ms % 1000) // 10:02d}"


def _local(tag) -> str:
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) else ""


def _attr(el, name):
    for k, v in el.attrib.items():
        if k.rsplit("}", 1)[-1] == name:
            return v
    return None


def _norm(s: str) -> str:
    s = re.sub(r"\(.*?\)|\[.*?\]", " ", (s or "").lower())
    s = re.sub(r"\b(feat|ft|from|remaster(ed)?|version|original|motion picture soundtrack)\b.*", " ", s)
    return " ".join(re.findall(r"\w+", s))


_ARTIST_SPLIT = re.compile(r"\s*(?:•|·|;|,|&|/|\bfeat\.?|\bft\.?|\bfeaturing\b|\bwith\b|\bx\b|\band\b)\s*", re.I)


def artist_parts(artist: str):
    """Every artist in a combined field ("A • B", "A, B & C", "A feat. B"), in order."""
    return [p.strip() for p in _ARTIST_SPLIT.split(artist or "") if p and p.strip()]


def primary_artist(artist: str) -> str:
    parts = artist_parts(artist)
    return parts[0] if parts else (artist or "").strip()


def clean_title(title: str) -> str:
    """The title without a "(From "Film")" / "[Remastered]" tail, for the search query."""
    t = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", title or "").strip(" -–")
    return t or (title or "").strip()


def _is_latin(s: str) -> bool:
    letters = [c for c in s if c.isalpha()]
    return not letters or all(ord(c) < 0x250 for c in letters)


_ISRC = re.compile(r"[A-Za-z0-9]{12}")


def catalog_details(song_id: str, db_path: str = None):
    """{"isrc", "spotify_id"} for a library song, read-only from catalog.db (isrc) and, when it
    exists, its spotify_details table. {} when unknown or the file can't be read."""
    out = {}
    if not song_id:
        return out
    import sqlite3
    try:
        con = sqlite3.connect(f"file:{db_path or CATALOG_DB}?mode=ro", uri=True, timeout=2)
    except sqlite3.Error:
        return out
    try:
        row = con.execute("SELECT isrc FROM songs WHERE id = ?", (song_id,)).fetchone()
        if row and row[0] and _ISRC.fullmatch(str(row[0]).strip()):
            out["isrc"] = str(row[0]).strip().upper()
        try:
            cols = {r[1] for r in con.execute("PRAGMA table_info(spotify_details)")}
            key = "song_id" if "song_id" in cols else ("id" if "id" in cols else None)
            if key:
                want = [c for c in ("isrc", "spotify_id", "track_id") if c in cols]
                if want:
                    r = con.execute(f"SELECT {', '.join(want)} FROM spotify_details WHERE {key} = ?", (song_id,)).fetchone()
                    for c, v in zip(want, r or ()):
                        v = str(v or "").strip()
                        if c == "isrc" and "isrc" not in out and _ISRC.fullmatch(v):
                            out["isrc"] = v.upper()
                        elif c in ("spotify_id", "track_id") and re.fullmatch(r"[A-Za-z0-9]{22}", v):
                            out["spotify_id"] = v
        except sqlite3.Error:
            pass
    except sqlite3.Error:
        pass
    finally:
        con.close()
    return out


# ── converters ─────────────────────────────────────────────────────────────────────────────────

def ttml_to_lrc(ttml: str):
    """TTML -> (enhanced LRC, word_timed). Word spans become <mm:ss.xx> tags; syllables inside one
    word are merged, so every tag is a whole word. Background vocals and translations are left out.
    Returns ("", False) when there is nothing usable."""
    if not ttml or "<!DOCTYPE" in ttml.upper() or "<!ENTITY" in ttml.upper():
        return "", False
    try:
        root = ET.fromstring(ttml)
    except ET.ParseError:
        return "", False
    lines = []
    any_words = False
    for p in root.iter():
        if _local(p.tag) != "p":
            continue
        begin = parse_clock(p.get("begin"))
        spans = []                       # [start_ms, raw text, a space follows the span]

        def walk(el):
            for child in el:
                if _local(child.tag) != "span":
                    continue
                role = (_attr(child, "role") or "").lower()
                tail_space = bool(child.tail) and child.tail[:1].isspace()
                if role in ("x-bg", "x-translation", "x-roman"):
                    if spans:
                        spans[-1][2] = True      # what was dropped splits the words around it
                elif child.get("begin") is not None:
                    spans.append([parse_clock(child.get("begin")), "".join(child.itertext()), tail_space])
                else:
                    walk(child)

        walk(p)
        words, space_before = [], True           # [start_ms, text]
        for start, raw, tail_space in spans:
            text = raw.strip()
            if not text or start is None:
                space_before = space_before or raw[:1].isspace() or tail_space
                continue
            if space_before or raw[:1].isspace() or not words:
                words.append([start, text])
            else:
                words[-1][1] += text             # a syllable of the same word
            space_before = raw[-1:].isspace() or tail_space
        if words:
            any_words = True
            start = words[0][0] if begin is None else begin
            body = " ".join(f"<{clock(w[0])}>{w[1]}" for w in words)
            lines.append((start, f"[{clock(start)}]{body}"))
            continue
        text = " ".join("".join(p.itertext()).split())
        if text and begin is not None:
            lines.append((begin, f"[{clock(begin)}]{text}"))
    lines.sort(key=lambda x: x[0])
    return "\n".join(l for _, l in lines), any_words


def paxsenix_to_lrc(payload):
    """Paxsenix JSON ({"syncType", "lines": [{"timeTag", "words"}]}) or a ready LRC text
    -> (lrc, sync) with sync "line" | "plain", or ("", None)."""
    if isinstance(payload, str):
        text = payload.strip()
        return (text, "line") if re.search(r"\[\d{1,2}:\d{2}[.:]\d{2,3}\]", text) else ("", None)
    if not isinstance(payload, dict) or not isinstance(payload.get("lines"), list):
        return "", None
    synced = str(payload.get("syncType", "")).upper() != "UNSYNCED"
    out = []
    for item in payload["lines"]:
        if not isinstance(item, dict):
            continue
        words = str(item.get("words") or "").strip()
        tag = str(item.get("timeTag") or "").strip()
        if not words:
            continue
        ms = parse_clock(tag)
        if synced and ms is not None:
            out.append(f"[{clock(ms)}]{words}")
        else:
            out.append(words)
    if not out:
        return "", None
    return "\n".join(out), ("line" if synced and out[0].startswith("[") else "plain")


# ── sources ─────────────────────────────────────────────────────────────────────────────────────

def http_get(url, params=None, headers=None, timeout=TIMEOUT):
    """(status, text). Tests replace this; nothing else in this file touches the network."""
    import requests
    r = requests.get(url, params=params, headers=headers, timeout=timeout)
    return r.status_code, r.text[:MAX_BODY]


def _json(text):
    try:
        return json.loads(text)
    except ValueError:
        return None


def _pick_hit(hits, title, artist, duration):
    """The search hit that is the same song, or None. Title must match; the artist must overlap;
    a known duration must be within 4 s."""
    want_t = _norm(title)
    parts = [set(_norm(p).split()) for p in artist_parts(artist)] or [set(_norm(artist).split())]
    parts = [p for p in parts if p]
    best, best_score = None, 0.0
    for h in hits or []:
        if not isinstance(h, dict) or not h.get("isrc"):
            continue
        if _norm(h.get("title", "")) != want_t:
            continue
        hit_artist = str(h.get("artist", ""))
        have_a = set(_norm(hit_artist).split())
        # The best-matching one of the song's artists (any of them may be the one listed).
        overlap = max((len(p & have_a) / len(p) for p in parts), default=0.5)
        d = h.get("duration")
        known = bool(duration) and isinstance(d, (int, float))
        diff = abs(float(d) - float(duration)) if known else None
        if known and diff > 4:
            continue
        if parts and overlap == 0:
            # The listing may spell the artist in another script ("维瓦克"): then the title and a
            # duration that agrees are the proof. Without a duration there is no proof.
            if not (known and not _is_latin(hit_artist)):
                continue
            overlap = 0.25
        score = overlap + (1 - diff / 4 if known else 0)
        if score > best_score:
            best, best_score = h, score
    return best


def _search_queries(song):
    """What to ask lrc.red, best first: title + primary artist, then the title alone."""
    title, first = clean_title(song["title"]), primary_artist(song["artist"])
    queries = [f"{title} {first}".strip()]
    if first and title:
        queries.append(title)
    return list(dict.fromkeys(q for q in queries if q))


def fetch_lrcred(song, get):
    headers = {"User-Agent": user_agent(), "X-Client-ID": user_agent()}
    info = None
    isrc = song.get("isrc") or ""
    if _ISRC.fullmatch(isrc):                    # the catalog knows it: no search needed
        status, text = get(f"https://lrc.red/s/{isrc}.json", None, headers)
        info = _json(text) if status == 200 else None
    if not isinstance(info, dict):
        isrc = ""
        for q in _search_queries(song):
            status, text = get("https://lrc.red/search.json", {"q": q}, headers)
            data = _json(text) if status == 200 else None
            hit = _pick_hit((data or {}).get("hits"), song["title"], song["artist"], song["duration"])
            if hit and _ISRC.fullmatch(str(hit["isrc"])):
                isrc = hit["isrc"]
                break
        if not isrc:
            return None
        status, text = get(f"https://lrc.red/s/{isrc}.json", None, headers)
        info = _json(text) if status == 200 else None
    sync = (info or {}).get("sync")
    if sync == "word":
        status, text = get(f"https://lrc.red/s/{isrc}.ttml", None, headers)
        if status == 200:
            lrc, words = ttml_to_lrc(text)
            if lrc:
                return {"sync": "word" if words else "line", "lrc": lrc}
    if sync in ("word", "line"):
        status, text = get(f"https://lrc.red/s/{isrc}.lrc", None, headers)
        if status == 200 and re.search(r"\[\d{1,2}:\d{2}[.:]\d{2,3}\]", text):
            return {"sync": "line", "lrc": text.strip()}
    return None


def fetch_betterlyrics(song, get):
    params = {"s": song["title"], "a": primary_artist(song["artist"])}
    if song["album"]:
        params["al"] = song["album"]
    if song["duration"]:
        params["d"] = int(song["duration"])
    status, text = get("https://api.betterlyrics.org/getLyrics", params, {"User-Agent": user_agent()})
    if status != 200:                    # 401 (no key, nothing cached) / 429 / 5xx: no result
        return None
    data = _json(text)
    lrc, words = ttml_to_lrc((data or {}).get("ttml", "")) if isinstance(data, dict) else ("", False)
    return {"sync": "word" if words else "line", "lrc": lrc} if lrc else None


def fetch_paxsenix(song, get):
    sid = song.get("spotify_id") or ""
    if not PAXSENIX_URL or not re.fullmatch(r"[A-Za-z0-9]{22}", sid):
        return None
    status, text = get(f"{PAXSENIX_URL}/api/lyrics",
                       {"url": f"https://open.spotify.com/track/{sid}", "format": "lrc"},
                       {"User-Agent": user_agent()})
    if status != 200:
        return None
    lrc, sync = paxsenix_to_lrc(_json(text) if text.lstrip().startswith(("{", "[")) else text)
    return {"sync": sync, "lrc": lrc} if lrc else None


def run_ytmusic(query: dict):
    """Asks the helper (run by tg-fetcher's Python, which has ytmusicapi) for one song's lyrics.
    -> {"sync": "line", "lines": [[ms, text], ...]} | {"sync": "plain", "text": "..."} | None.
    Tests replace this; the helper only ever reads lyrics text."""
    import subprocess
    if not (os.path.isfile(YTMUSIC_PYTHON) and os.path.isfile(YTMUSIC_HELPER)):
        return None
    try:
        r = subprocess.run([YTMUSIC_PYTHON, "-I", YTMUSIC_HELPER], input=json.dumps(query), capture_output=True,
                           text=True, timeout=40, env={"PATH": "/usr/bin:/bin", "HOME": os.getenv("HOME", "/tmp")})
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return _json(r.stdout.strip().splitlines()[-1]) if r.stdout.strip() else None


def lines_to_lrc(lines) -> str:
    out = []
    for item in sorted((i for i in lines if isinstance(i, (list, tuple)) and len(i) == 2),
                       key=lambda i: i[0] if isinstance(i[0], (int, float)) else 0):
        ms, text = item
        text = " ".join(str(text or "").split())
        if text and isinstance(ms, (int, float)):
            out.append(f"[{clock(ms)}]{text}")
    return "\n".join(out)


def fetch_ytmusic(song, get):
    got = run_ytmusic({"title": clean_title(song["title"]), "artist": primary_artist(song["artist"]),
                       "duration": song["duration"]})
    if not isinstance(got, dict):
        return None
    if got.get("sync") == "line":
        lrc = lines_to_lrc(got.get("lines") or [])
        return {"sync": "line", "lrc": lrc} if lrc else None
    text = "\n".join(l.strip() for l in str(got.get("text") or "").splitlines() if l.strip())
    return {"sync": "plain", "lrc": text} if text else None


FETCHERS = {"lrcred": fetch_lrcred, "betterlyrics": fetch_betterlyrics, "ytmusic": fetch_ytmusic,
            "paxsenix": fetch_paxsenix}


def enabled_sources() -> tuple:
    return tuple(s for s in SOURCES
                 if (s != "paxsenix" or PAXSENIX_URL) and (s != "ytmusic" or YTMUSIC_ON))


def enrich_song(song) -> dict:
    """The song with what the catalog knows about it (ISRC, Spotify id) when the caller sent none."""
    song = dict(song)
    if song.get("song_id") and not (song.get("isrc") and song.get("spotify_id")):
        known = catalog_details(song["song_id"])
        song.setdefault("isrc", "")
        for k, v in known.items():
            if not song.get(k):
                song[k] = v
    return song


def resolve(song, sources, get=None):
    """(source, {"sync", "lrc"}) for the first synced answer, else the first plain one, else None."""
    get = get or http_get
    fallback = None
    for name in sources:
        try:
            got = FETCHERS[name](song, get)
        except Exception:                # a source's trouble is never the user's error
            got = None
        if not got:
            continue
        if got["sync"] in ("word", "line"):
            return name, got
        fallback = fallback or (name, got)
    return fallback


# ── per-song cache, on disk ────────────────────────────────────────────────────────────────────

class SongCache:
    def __init__(self, directory, now=time.time):
        self.dir, self.now = directory, now
        self._lock = threading.Lock()

    def _path(self, key):
        return os.path.join(self.dir, hashlib.sha256(key.encode("utf-8")).hexdigest()[:40] + ".json")

    def get(self, key):
        try:
            with open(self._path(key), encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def put(self, key, entry):
        entry = {**entry, "at": int(self.now())}
        try:
            with self._lock:
                os.makedirs(self.dir, mode=0o700, exist_ok=True)
                tmp = self._path(key) + ".tmp"
                fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    json.dump(entry, f)
                os.replace(tmp, self._path(key))
        except OSError:
            pass                         # a cache that can't write just misses next time


def song_key(song) -> str:
    return song["song_id"] or f"{_norm(song['artist'])}|{_norm(song['title'])}|{int(song['duration'] or 0)}"


# ── the route ──────────────────────────────────────────────────────────────────────────────────

def register_lyrics_proxy_routes(app, require_auth, get=None, cache=None, now=time.time):
    cache = cache or SongCache(CACHE_DIR, now)
    hits = {}                            # user -> [timestamps in the last minute]
    lock = threading.Lock()

    def too_many(user):
        t = now()
        with lock:
            recent = [x for x in hits.get(user, []) if t - x < 60]
            recent.append(t)
            hits[user] = recent
            return len(recent) > RATE_PER_MIN

    def reply(body, status=200):
        resp = jsonify(body)
        resp.status_code = status
        resp.headers["Cache-Control"] = "private, no-store"
        resp.headers["X-Robots-Tag"] = "noindex, nofollow"
        return resp

    @app.route("/lyrics/fetch", methods=["GET"])
    @require_auth
    def lyrics_fetch():
        a = request.args
        song = {k: (a.get(k) or "").strip()[:MAX_FIELD] for k in ("title", "artist", "album", "song_id", "spotify_id")}
        try:
            song["duration"] = max(0, min(int(float(a.get("duration") or 0)), 3 * 3600))
        except ValueError:
            return reply({"error": "Send the duration in seconds."}, 400)
        if not song["title"]:
            return reply({"error": "Send the song's title."}, 400)
        asked = [s for s in (a.get("sources") or ",".join(DEFAULT_SOURCES)).split(",") if s in SOURCES]
        sources = tuple(dict.fromkeys(s for s in asked if s in enabled_sources()))
        if not sources:
            return reply({"error": "No lyrics source is switched on."}, 404)
        if too_many(getattr(g, "username", "")):
            return reply({"error": "Too many lyrics requests. Try again in a minute."}, 429)

        result = lookup(song, sources, cache, get, now)
        if not result:
            return reply({"error": "No lyrics found for this song."}, 404)
        return reply(result)


def lookup(song, sources, cache, get=None, now=time.time, miss_ttl=NEGATIVE_TTL, fetch=True):
    """The one place that reads and writes the per-song cache (the route and the prefetch share it).

    -> {"source", "sync", "lrc", "cached"} or None (nothing found, or - with fetch=False - nothing
    cached). A hit is kept for good. A miss is kept for [miss_ttl] and only counts when it was
    written by this cache version for at least these sources: a miss from an older version, or
    from a shorter source list, is asked again."""
    key = song_key(song)
    entry = cache.get(key)
    if entry:
        if entry.get("lrc") and entry.get("source") in sources:
            return {"source": entry["source"], "sync": entry["sync"], "lrc": entry["lrc"], "cached": True}
        if not entry.get("lrc") and entry.get("v") == CACHE_VERSION and set(sources) <= set(entry.get("tried", [])) \
                and now() - entry.get("at", 0) < miss_ttl:
            return None
    if not fetch:
        return None
    found = resolve(enrich_song(song), sources, get)
    if not found:
        cache.put(key, {"v": CACHE_VERSION, "tried": list(sources)})
        return None
    name, got = found
    cache.put(key, {"v": CACHE_VERSION, "source": name, "sync": got["sync"], "lrc": got["lrc"]})
    return {"source": name, "sync": got["sync"], "lrc": got["lrc"], "cached": False}
