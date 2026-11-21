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
  paxsenix      OFF unless NAVIVIBE_PAXSENIX_URL is set to a Paxsenix/Spotify-Lyrics-API instance
                (GET {url}/api/lyrics?url=<spotify track url>&format=lrc). It wraps undocumented Spotify
                endpoints and may violate Spotify's terms. The server only forwards a track id; the
                instance's own Spotify cookie lives on that instance, never in this app or here.

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

SOURCES = ("lrcred", "betterlyrics", "paxsenix")
DEFAULT_SOURCES = ("lrcred", "betterlyrics")
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
    want_t, want_a = _norm(title), set(_norm(artist).split())
    best, best_score = None, 0.0
    for h in hits or []:
        if not isinstance(h, dict) or not h.get("isrc"):
            continue
        if _norm(h.get("title", "")) != want_t:
            continue
        have_a = set(_norm(h.get("artist", "")).split())
        overlap = len(want_a & have_a) / max(len(want_a), 1) if want_a else 0.5
        if want_a and overlap == 0:
            continue
        score = overlap
        d = h.get("duration")
        if duration and isinstance(d, (int, float)):
            diff = abs(float(d) - float(duration))
            if diff > 4:
                continue
            score += 1 - diff / 4
        if score > best_score:
            best, best_score = h, score
    return best


def fetch_lrcred(song, get):
    headers = {"User-Agent": user_agent(), "X-Client-ID": user_agent()}
    status, text = get("https://lrc.red/search.json", {"q": f"{song['title']} {song['artist']}".strip()}, headers)
    data = _json(text) if status == 200 else None
    hit = _pick_hit((data or {}).get("hits"), song["title"], song["artist"], song["duration"])
    if not hit or not re.fullmatch(r"[A-Za-z0-9]{12}", str(hit["isrc"])):
        return None
    isrc = hit["isrc"]
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
    params = {"s": song["title"], "a": song["artist"]}
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


FETCHERS = {"lrcred": fetch_lrcred, "betterlyrics": fetch_betterlyrics, "paxsenix": fetch_paxsenix}


def enabled_sources() -> tuple:
    return tuple(s for s in SOURCES if s != "paxsenix" or PAXSENIX_URL)


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

        key = song_key(song)
        entry = cache.get(key)
        if entry:
            if entry.get("lrc") and entry.get("source") in sources:
                return reply({"source": entry["source"], "sync": entry["sync"], "lrc": entry["lrc"], "cached": True})
            if not entry.get("lrc") and set(sources) <= set(entry.get("tried", [])) \
                    and now() - entry.get("at", 0) < NEGATIVE_TTL:
                return reply({"error": "No lyrics found for this song."}, 404)

        found = resolve(song, sources, get)
        if not found:
            cache.put(key, {"tried": list(sources)})
            return reply({"error": "No lyrics found for this song."}, 404)
        name, got = found
        cache.put(key, {"source": name, "sync": got["sync"], "lrc": got["lrc"]})
        return reply({"source": name, "sync": got["sync"], "lrc": got["lrc"], "cached": False})
