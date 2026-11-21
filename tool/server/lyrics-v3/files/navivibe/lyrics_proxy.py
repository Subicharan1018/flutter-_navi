"""
navivibe/lyrics_proxy.py   (lyrics-v3)
──────────────────────────────────────
Synced lyrics from third-party sources, fetched by the server so the web app (whose CSP only allows
this server) and the phone ask one place. For the signed-in user's own display only.

  GET /lyrics/fetch   (signed in)
      ?title=&artist=&album=&duration=<seconds>&song_id=&sources=lrcred,betterlyrics,ytmusic,paxsenix
      &spotify_id=<22 chars>   (only the "paxsenix" source uses it)
      &refresh=1               ask the sources again: ignores a remembered "nobody has it" (10 an hour)
  200 {"source": "lrcred", "sync": "word"|"line"|"plain", "lrc": "<enhanced LRC>", "cached": bool}
  404 {"error": "..."}                  nobody has it (every source answered)
  404 {"error": "...", "retry": true}   a source did not answer (timeout, 429, 5xx, bad data): try again
  400 / 429                             bad request / too many requests

The answer is enhanced LRC: "[mm:ss.xx]<mm:ss.xx>word <mm:ss.xx>word": the format the app already
parses, so word timing and line timing travel the same way.

Sources, tried in the order asked, first synced answer wins (a plain-text answer is the fallback):
  lrcred        https://lrc.red  search.json -> /s/{isrc}.ttml (word) or .lrc (line). Its terms: a
                User-Agent naming this app with a link and a contact address (NAVIVIBE_LYRICS_CONTACT),
                and the app shows "lrc.red" wherever its data is shown.
  betterlyrics  https://api.betterlyrics.org/getLyrics?s&a&al&d -> {"ttml": "..."} (word timed). Keys are
                not being issued; a song nobody has played in the extension answers 401 = no result.
  ytmusic       YouTube Music's lyrics, through ytmusicapi run by a small helper in tg-fetcher's venv
                (navivibe/ytmusic_lyrics_helper.py). On unless NAVIVIBE_YTMUSIC_LYRICS=0. Unofficial:
                may go against YouTube's terms of service.
  paxsenix      OFF unless NAVIVIBE_PAXSENIX_URL is set to a Paxsenix/Spotify-Lyrics-API instance.

lyrics-v3 (on top of v2's multi-artist lookup and ISRC):
  * every source says FOUND, NOT FOUND or FAILED. A timeout, a 429, a 5xx, a connection error or bad
    JSON is FAILED and is never remembered as "nobody has it": the answer is 404 + "retry": true and
    the next request asks again (after a short 5-minute pause for the same song).
  * a looser, data-driven matcher: title variants, several artists in any order or script, near
    spellings of Indian names, duration within 12 s (a wider gap needs the title, artist and album to
    agree), more result pages, more queries - with a guard that a remix / sped-up / live / revival /
    reprise never stands in for the original.
  * "refresh=1", a per-song lock (two requests for one song ask the sources once), a 12-second budget
    per request, and a plain-text answer is looked at again so it cannot hide synced lyrics.

Each song is cached on disk, per song, readable only by this server (mode 0600); nothing is served
without a sign-in, nothing is cached by browsers or proxies (Cache-Control: private, no-store).
"""

import contextlib
import difflib
import hashlib
import json
import logging
import os
import re
import threading
import time
import unicodedata
import xml.etree.ElementTree as ET
from collections import namedtuple

from flask import g, jsonify, request

log = logging.getLogger("lyrics_proxy")

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
CACHE_VERSION = 3                # v3 matches more songs: a miss written by an older version is asked again
TIMEOUT = 5                      # one request to one source
ROUTE_BUDGET = 12                # the whole /lyrics/fetch request, all sources
NEGATIVE_TTL = 6 * 3600          # a song nobody has: ask again after six hours
TRANSIENT_TTL = 5 * 60           # a source did not answer: don't ask it again for this song for 5 minutes
PLAIN_RECHECK = 24 * 3600        # plain text is looked at again after a day: a source may have it synced now
PARTIAL_RECHECK = 10 * 60        # an answer given while another source failed is looked at again soon
RATE_PER_MIN = 40                # per user, on top of the server's own limits
REFRESH_PER_HOUR = 10            # "Search again", per user
MAX_FIELD = 200
MAX_BODY = 600_000               # a TTML file is far smaller than this
MAX_DURATION_GAP = 12            # seconds: a hit whose length differs more is another recording
SEARCH_PAGES = 3                 # result pages followed per query
SEARCH_REQUESTS = 10             # search requests at most for one song


class SourceFailed(Exception):
    """A source could not answer (timeout, 429, 5xx, a connection error, bad JSON). Never a "not found"."""


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
    """The cache key's normalisation (kept as v1 wrote it so existing cache files keep their names)."""
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


_NOISE_TAIL = re.compile(
    r"\s[-–—]\s*(?:from|remaster(?:ed)?|re-?master(?:ed)?|original|feat\.?|ft\.?|with|\d{4}|bonus|mono|stereo"
    r"|single|album|deluxe)\b.*$", re.I)


def clean_title(title: str) -> str:
    """The title without a "(From "Film")" / "[Remastered]" / "- From Film" tail, for the search query."""
    t = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", title or "")
    t = _NOISE_TAIL.sub("", t).strip(" -–—")
    return t or (title or "").strip()


def film_of(title: str) -> str:
    """"Film" from `Song (From "Film")` or `Song - From Film`, else ""."""
    m = re.search(r"[\(\[]\s*(?:from|music from|theme from)\s+[\"“”']?([^\"“”\)\]]+)", title or "", re.I) \
        or re.search(r"\s[-–—]\s*from\s+[\"“”']?(.+?)[\"“”']?\s*$", title or "", re.I)
    return m.group(1).strip() if m else ""


def _is_latin(s: str) -> bool:
    letters = [c for c in s if c.isalpha()]
    return not letters or all(ord(c) < 0x250 for c in letters)


def _fold_accents(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", s or "") if not unicodedata.combining(c))


# ── matching: is this search hit the same recording? ───────────────────────────────────────────

_VARIANTS = re.compile(
    r"\b(remix(?:ed)?|mix|mashup|rework|refix|bootleg|sped\s?up|speed(?:ed)?\s?up|slowed|reverb|live|acoustic"
    r"|unplugged|instrumental|karaoke|revival|reprise|cover|lo-?fi|8d|nightcore|extended|stripped|demo"
    r"|orchestral|unwind(?:ed)?|reloaded|recreated|remake|duet|male|female|bgm|flute|violin|piano|guitar"
    r"|radio\s+edit|edit|dub|club"
    r"|(?:tamil|telugu|hindi|malayalam|kannada|english)\s+(?:version|ver\.?|dubbed))\b", re.I)
_CANON = {"remixed": "remix", "mix": "remix", "speedup": "spedup", "speedeup": "spedup", "speededup": "spedup",
          "lo-fi": "lofi", "unwinded": "unwind", "radio edit": "edit"}


def variant_tags(title: str) -> frozenset:
    """What kind of version a title says it is, from its bracket / dash tail: remix, sped up, live,
    acoustic, instrumental, reprise, revival, karaoke, a language version ... A song and a hit must
    carry the same tags: a remix never stands in for the original. "Remastered" is not a version."""
    t = _fold_accents(title or "").lower()
    segs = re.findall(r"[\(\[]([^\)\]]*)[\)\]]", t) + re.findall(r"\s[-–—]\s(.+)$", t)
    tags = set()
    for seg in segs:
        if re.match(r"\s*[\"“']?(from|music from|theme from|original motion|original score)\b", seg):
            continue                                # (From "Live Aid") names a film, not a version
        for m in _VARIANTS.finditer(seg):
            w = re.sub(r"\s+", " ", m.group(1)).replace(" ", "")
            w = re.sub(r"(tamil|telugu|hindi|malayalam|kannada|english).*", r"\1-version", w)
            tags.add(_CANON.get(w, w))
    return frozenset(tags)


def _title_key(x: str) -> str:
    x = x.replace("'", "").replace("’", "").replace("&", " and ")
    x = re.sub(r"\bpt\b\.?", "part", x)
    x = re.sub(r"\bvol\b\.?", "volume", x)
    return " ".join(re.findall(r"\w+", x))


def title_keys(title: str):
    """(full, head): the title as a plain word string, without its bracket / "- From ..." tails and
    "feat." part; `head` is also cut at a colon / dash subtitle."""
    t0 = _fold_accents(title or "").lower()
    t = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", " ", t0)
    t = _NOISE_TAIL.sub("", t)
    t = re.sub(r"\b(?:feat|ft|featuring)\b\.?.*$", "", t)
    head = re.split(r"\s[-–—|]\s|:|\s/\s", t, maxsplit=1)[0]
    full = _title_key(t)
    if not full:                                    # a title that is only a bracket: "(Intro)"
        full = _title_key(re.sub(r"[\(\)\[\]]", " ", t0))
    return full, (_title_key(head) or full)


_FOLDS = (("aa", "a"), ("ee", "i"), ("oo", "u"), ("ii", "i"), ("uu", "u"), ("th", "t"), ("dh", "d"), ("bh", "b"),
          ("kh", "k"), ("gh", "g"), ("zh", "l"), ("sh", "s"), ("ph", "p"), ("w", "v"), ("y", "i"), ("ck", "k"),
          ("c", "k"))


def _fold(s: str) -> str:
    """A spelling-insensitive key for transliterated names: Yuvan/Yuvaan, Kadhal/Kaadhal, Thanjavur/Tanjavur."""
    s = _fold_accents(s).lower()
    for a, b in _FOLDS:
        s = s.replace(a, b)
    return re.sub(r"(.)\1+", r"\1", s)


def _ratio(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a, b).ratio()


def title_match(lib_title: str, hit_title: str) -> float:
    """1.0 same title; 0.8 the same up to a subtitle; 0.75 / 0.6 the same up to spelling; 0 different."""
    lf, lh = title_keys(lib_title)
    hf, hh = title_keys(hit_title)
    if not lf or not hf:
        return 0.0
    if lf == hf:
        return 1.0
    if (lf == hh or lh == hf or lh == hh) and min(len(lh), len(hh)) >= 4:
        return 0.8
    ff, fh = _fold(lf), _fold(hf)
    if re.findall(r"\d+", lf) != re.findall(r"\d+", hf):
        return 0.0                                   # "Part 1" is not "Part 2"
    if ff == fh:
        return 0.75
    if min(len(ff), len(fh)) >= 6 and _ratio(ff, fh) >= 0.9:
        return 0.6
    return 0.0


def _tokens(s: str):
    return re.findall(r"\w+", _fold_accents(s or "").lower().replace("'", ""))


def _token_sim(a: str, b: str) -> bool:
    if a == b:
        return True
    fa, fb = _fold(a), _fold(b)
    return fa == fb or (min(len(fa), len(fb)) >= 5 and _ratio(fa, fb) >= 0.86)


def _coverage(lib_tokens, hit_tokens) -> float:
    """How much of one artist name is in another: "A. R. Rahman" / "AR Rahman" 1.0, Ravichander /
    Ravichandran 1.0, "Kumar" / "Kumar Sanu" 1.0 (a one-name listing), unrelated 0."""
    if not lib_tokens or not hit_tokens:
        return 0.0
    if "".join(lib_tokens) == "".join(hit_tokens):
        return 1.0
    got = sum(1 for t in lib_tokens if any(_token_sim(t, h) for h in hit_tokens))
    return got / len(lib_tokens)


def artist_match(lib_artist: str, hit_artist: str):
    """(score 0..1, hit_has_other_script). The best pairing of any artist listed on the library side
    with any Latin-script artist on the hit side; an artist written in another script can't be compared
    and is reported instead."""
    lib = [_tokens(p) for p in artist_parts(lib_artist)] or [_tokens(lib_artist)]
    parts = artist_parts(hit_artist) or [hit_artist or ""]
    hit = [_tokens(p) for p in parts if _is_latin(p)]
    other_script = any(not _is_latin(p) for p in parts)
    best = max((_coverage(lp, hp) for lp in lib if lp for hp in hit if hp), default=0.0)
    return best, other_script


_ALBUM_NOISE = re.compile(r"\b(original motion picture soundtrack|original soundtrack|motion picture|ost"
                          r"|soundtrack|deluxe|edition|remastered)\b")


def album_match(lib_album: str, hit_album: str) -> bool:
    def key(a):
        a = _fold_accents(a or "").lower()
        outside = re.sub(r"[\(\[][^\)\]]*[\)\]]", " ", a)
        a = _ALBUM_NOISE.sub(" ", outside if outside.strip() else a)
        return " ".join(re.findall(r"\w+", a.replace("'", "")))
    a, b = key(lib_album), key(hit_album)
    if not a or not b:
        return False
    if a == b or _fold(a) == _fold(b):
        return True
    return min(len(a), len(b)) >= 5 and _ratio(_fold(a), _fold(b)) >= 0.85      # "Orginal" for "Original", "Rdx"


def score_hit(song, hit):
    """A score for "this search hit is the same recording as the song", or None when it is not.

    Rules (a wrong song is worse than none):
      * the same kind of version: a remix, sped-up, live, acoustic, reprise, revival ... must match
      * the title matches (a subtitle or a spelling difference needs the rest to be near certain)
      * someone listed on the song is on the hit (any order, any of several, a near spelling), or
        the hit's artist is in another script and the title and duration agree, or the album agrees
      * a known duration within 4 s; 4-12 s only for an exact title with a strong artist (or album)
        match; more than 12 s never. An unknown duration needs an exact title and a strong match."""
    if not isinstance(hit, dict) or not hit.get("isrc"):
        return None
    if variant_tags(song["title"]) != variant_tags(hit.get("title", "")):
        return None
    t = title_match(song["title"], hit.get("title", ""))
    if t == 0:
        return None
    a, other_script = artist_match(song["artist"], str(hit.get("artist", "")))
    alb = album_match(song.get("album", ""), hit.get("album", ""))
    d, want = hit.get("duration"), song.get("duration") or 0
    known = bool(want) and isinstance(d, (int, float)) and not isinstance(d, bool)
    diff = abs(float(d) - float(want)) if known else None
    exact, strong, artist_ok = t >= 0.99, a >= 0.99, a >= 0.5

    if known:
        if diff > MAX_DURATION_GAP:
            return None
        if diff > 4 and not (exact and (strong or (alb and artist_ok))):
            return None
    elif not (exact and (strong or (alb and artist_ok))):
        return None
    if not exact:
        near = 4 if t >= 0.79 else 3
        if not ((a >= 0.5 if t >= 0.79 else strong) and known and diff <= near):
            return None
    # Who is credited differs a lot between catalogues (the composer here, the singer there), so with no
    # artist in common the proof is the exact title plus a length that agrees to 2 s and the same album
    # (or 4 s when the hit's artist is in another script).
    if not (artist_ok or (exact and known and ((other_script and diff <= 4) or (alb and diff <= 2)))):
        return None
    return 3 * t + 2 * (a if artist_ok else 0.5) + (1 if alb else 0) + (1 - diff / MAX_DURATION_GAP if known else 0)


def _pick_hit(hits, song):
    """The best hit that is the same recording, or None."""
    best, best_score = None, 0.0
    for h in hits or []:
        s = score_hit(song, h)
        if s is not None and s > best_score:
            best, best_score = h, s
    return best


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
# A fetcher returns {"sync", "lrc"} (FOUND), None (NOT FOUND: the source answered and hasn't got it)
# or raises SourceFailed (FAILED: it did not answer). Only the first two may become a remembered miss.

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


def _status(status, missing=(404,)):
    """"ok" (200) or "missing" (a clean "no"); anything else - 429, 5xx, a timeout (0) - is a failure."""
    if status == 200:
        return "ok"
    if status in missing:
        return "missing"
    raise SourceFailed(f"HTTP {status}")


def _json_or_fail(text):
    data = _json(text)
    if data is None:
        raise SourceFailed("bad JSON")
    return data


def _search_queries(song):
    """What to ask lrc.red, best first: title + primary artist, then the title alone, then the other
    artists, the film / album, the subtitle-less title, and the title without punctuation."""
    title, parts = clean_title(song["title"]), artist_parts(song["artist"])
    first = parts[0] if parts else (song["artist"] or "").strip()
    film = film_of(song["title"]) or re.sub(r"\s*[\(\[].*$", "", song.get("album") or "").strip()
    head = re.split(r"\s[-–—|]\s|:|\s/\s", title, maxsplit=1)[0].strip()
    # lrc.red's search is picky about punctuation: "Somebody's Watching Me" finds nothing, "Somebodys
    # Watching Me" finds it. Apostrophes are dropped, any other punctuation becomes a space.
    bare = " ".join(re.sub(r"[^\w\s]", " ", re.sub(r"['’`´′]", "", title)).split())
    plain = " ".join(re.sub(r"[^\w\s]", " ", title).split())
    queries = [f"{title} {first}".strip(), title]
    for variant in (bare, plain):                # punctuation is the commonest reason for a miss
        if variant and variant != title:
            queries.append(variant)
    queries += [f"{title} {p}" for p in parts[1:3]]
    if film and film.lower() != title.lower():
        queries.append(f"{title} {film}")
    if head and head != title:
        queries += [f"{head} {first}".strip(), head]
    return list(dict.fromkeys(q for q in queries if q))[:9]


def _isrc_ok(song, info) -> bool:
    """A catalog ISRC is trusted only while the record it names looks like the same recording."""
    d = info.get("duration")
    if song.get("duration") and isinstance(d, (int, float)) and abs(float(d) - song["duration"]) > MAX_DURATION_GAP:
        return False
    return not info.get("title") or title_match(song["title"], str(info["title"])) > 0 or \
        (isinstance(d, (int, float)) and abs(float(d) - song.get("duration", 0)) <= 4)


def _lrcred_info(isrc, get, headers):
    status, text = get(f"https://lrc.red/s/{isrc}.json", None, headers)
    if _status(status) == "missing":
        return None
    data = _json_or_fail(text)
    return data if isinstance(data, dict) else None


def _lrcred_find(song, get, headers):
    """The ISRC of the lrc.red record that is this song, or None. Raises SourceFailed only when
    nothing matched AND some request failed (a clean search that finds nobody is a clean "no")."""
    failures, requests_left = [], SEARCH_REQUESTS
    for q in _search_queries(song):
        after = None
        for _ in range(SEARCH_PAGES):
            if requests_left <= 0:
                break
            requests_left -= 1
            params = {"q": q, **({"after": after} if after else {})}
            try:
                status, text = get("https://lrc.red/search.json", params, headers)
                if _status(status) == "missing":
                    break
                data = _json_or_fail(text)
            except SourceFailed as e:
                failures.append(e)
                break
            hits = data.get("hits") if isinstance(data, dict) else None
            hit = _pick_hit(hits, song)
            if hit and _ISRC.fullmatch(str(hit["isrc"])):
                return str(hit["isrc"])
            after = data.get("next") if isinstance(data, dict) else None
            if not (hits and isinstance(after, str) and after):
                break
    if failures:
        raise failures[0]
    return None


def fetch_lrcred(song, get):
    headers = {"User-Agent": user_agent(), "X-Client-ID": user_agent()}
    info, isrc = None, song.get("isrc") or ""
    if _ISRC.fullmatch(isrc):                    # the catalog knows it: no search needed
        info = _lrcred_info(isrc, get, headers)
        if info is not None and not _isrc_ok(song, info):
            info = None                          # the ISRC names something else: search instead
    if info is None:
        isrc = _lrcred_find(song, get, headers)
        if not isrc:
            return None
        info = _lrcred_info(isrc, get, headers)
    sync = (info or {}).get("sync")
    if sync not in ("word", "line"):
        return None                              # a record without synced lyrics: a clean "none"
    trouble = None
    if sync == "word":
        try:
            status, text = get(f"https://lrc.red/s/{isrc}.ttml", None, headers)
            if _status(status) == "ok":
                lrc, words = ttml_to_lrc(text)
                if lrc:
                    return {"sync": "word" if words else "line", "lrc": lrc}
        except SourceFailed as e:
            trouble = e
    try:
        status, text = get(f"https://lrc.red/s/{isrc}.lrc", None, headers)
        if _status(status) == "ok" and re.search(r"\[\d{1,2}:\d{2}[.:]\d{2,3}\]", text):
            # Line timing is the answer; when the word-timed file failed, look again soon.
            return {"sync": "line", "lrc": text.strip(), **({"partial": True} if trouble else {})}
    except SourceFailed as e:
        trouble = trouble or e
    if trouble:
        raise trouble
    return None


def fetch_betterlyrics(song, get):
    params = {"s": song["title"], "a": primary_artist(song["artist"])}
    if song["album"]:
        params["al"] = song["album"]
    if song["duration"]:
        params["d"] = int(song["duration"])
    status, text = get("https://api.betterlyrics.org/getLyrics", params, {"User-Agent": user_agent()})
    if _status(status, missing=(401, 404)) == "missing":     # 401: no key and nothing cached = no result
        return None
    data = _json_or_fail(text)
    lrc, words = ttml_to_lrc((data or {}).get("ttml", "")) if isinstance(data, dict) else ("", False)
    return {"sync": "word" if words else "line", "lrc": lrc} if lrc else None


def fetch_paxsenix(song, get):
    sid = song.get("spotify_id") or ""
    if not PAXSENIX_URL or not re.fullmatch(r"[A-Za-z0-9]{22}", sid):
        return None
    status, text = get(f"{PAXSENIX_URL}/api/lyrics",
                       {"url": f"https://open.spotify.com/track/{sid}", "format": "lrc"},
                       {"User-Agent": user_agent()})
    if _status(status) == "missing":
        return None
    lrc, sync = paxsenix_to_lrc(_json(text) if text.lstrip().startswith(("{", "[")) else text)
    return {"sync": sync, "lrc": lrc} if lrc else None


def run_ytmusic(query: dict, timeout: float = 25):
    """Asks the helper (run by tg-fetcher's Python, which has ytmusicapi) for one song's lyrics.
    -> {"sync": "line", "lines": [[ms, text], ...]} | {"sync": "plain", "text": "..."} | {} (it has
    none) | None (the helper isn't installed here). Raises SourceFailed when the helper itself fails.
    Tests replace this; the helper only ever reads lyrics text."""
    import subprocess
    if not (os.path.isfile(YTMUSIC_PYTHON) and os.path.isfile(YTMUSIC_HELPER)):
        return None
    try:
        r = subprocess.run([YTMUSIC_PYTHON, "-I", YTMUSIC_HELPER], input=json.dumps(query), capture_output=True,
                           text=True, timeout=timeout, env={"PATH": "/usr/bin:/bin", "HOME": os.getenv("HOME", "/tmp")})
    except (OSError, subprocess.SubprocessError) as e:
        raise SourceFailed(type(e).__name__)
    if r.returncode != 0:
        raise SourceFailed(f"helper exit {r.returncode}")
    out = _json(r.stdout.strip().splitlines()[-1]) if r.stdout.strip() else None
    if not isinstance(out, dict):
        raise SourceFailed("helper printed nothing")
    return out


def lines_to_lrc(lines) -> str:
    out = []
    for item in sorted((i for i in lines if isinstance(i, (list, tuple)) and len(i) == 2),
                       key=lambda i: i[0] if isinstance(i[0], (int, float)) else 0):
        ms, text = item
        text = " ".join(str(text or "").split())
        if text and isinstance(ms, (int, float)):
            out.append(f"[{clock(ms)}]{text}")
    return "\n".join(out)


def _yt_timeout(get) -> float:
    left = getattr(get, "remaining", lambda: None)()
    return 25.0 if left is None else max(1.0, min(10.0, left))


def fetch_ytmusic(song, get):
    got = run_ytmusic({"title": clean_title(song["title"]), "artist": primary_artist(song["artist"]),
                       "full_title": song["title"], "duration": song["duration"]}, timeout=_yt_timeout(get))
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
    if song.get("song_id") and not song.get("isrc"):
        try:                                 # the Exportify package fills ISRCs the catalog lacks
            import importlib
            spotify_details = importlib.import_module("navivibe.spotify_details")
            isrc = str(spotify_details.isrc_of(song["song_id"], "") or "").strip()
            if _ISRC.fullmatch(isrc):
                song["isrc"] = isrc.upper()
        except Exception:                    # optional: no module, no file, no row = no answer
            pass
    return song


class Deadline:
    """`get` with a time budget: each request's timeout is cut to what is left; none starts once it is
    spent (that counts as the source failing). budget=None: no limit (the nightly prefetch)."""

    def __init__(self, get, budget, clock_fn=None):
        self.get = get
        self.clock_fn = clock_fn or (lambda: time.monotonic())
        self.end = None if not budget else self.clock_fn() + budget

    def remaining(self):
        return None if self.end is None else self.end - self.clock_fn()

    def __call__(self, url, params=None, headers=None, timeout=TIMEOUT):
        left = self.remaining()
        if left is not None:
            if left <= 0.3:
                raise SourceFailed("out of time")
            timeout = min(timeout, left)
        return self.get(url, params, headers, timeout)


Resolved = namedtuple("Resolved", "found answered failed")


def resolve_ex(song, sources, get=None, budget=None):
    """Asks the sources in order. -> Resolved(found, answered, failed): `found` is (name, answer) for
    the first synced answer, else the first plain one, else None; `answered` are the sources that said
    yes or a clean no; `failed` are the ones that did not answer."""
    get = Deadline(get or http_get, budget)
    fallback, answered, failed = None, [], []
    for name in sources:
        left = get.remaining()
        if left is not None and left <= 0.3:
            failed.append(name)
            continue
        try:
            got = FETCHERS[name](song, get)
        except Exception as e:           # SourceFailed, a timeout, a connection error, a bug: never a "no"
            log.warning("lyrics source %s did not answer: %s", name, type(e).__name__)
            failed.append(name)
            continue
        answered.append(name)
        if not got:
            continue
        if got["sync"] in ("word", "line"):
            return Resolved((name, got), answered, failed)
        fallback = fallback or (name, got)
    return Resolved(fallback, answered, failed)


def resolve(song, sources, get=None):
    """(source, {"sync", "lrc"}) for the first synced answer, else the first plain one, else None."""
    return resolve_ex(song, sources, get).found


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
        entry = {**entry, "at": int(self.now()), "n": time.time_ns()}      # "n": tells a rewrite from a same-second one
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


class KeyLocks:
    """One lock per song key, so two requests for the same song ask the sources once."""

    def __init__(self):
        self._m, self._g = {}, threading.Lock()

    @contextlib.contextmanager
    def hold(self, key):
        with self._g:
            ent = self._m.setdefault(key, [threading.Lock(), 0])
            ent[1] += 1
        try:
            with ent[0]:
                yield
        finally:
            with self._g:
                ent[1] -= 1
                if ent[1] == 0:
                    self._m.pop(key, None)


LOCKS = KeyLocks()

_RANK = {"word": 3, "line": 2, "plain": 1}
Outcome = namedtuple("Outcome", "state result")     # state: found | missing | failed | unknown


def _result(entry, cached=True):
    return {"source": entry["source"], "sync": entry["sync"], "lrc": entry["lrc"], "cached": cached}


def _read(entry, sources, t, miss_ttl, refresh):
    """What the cache entry says. -> (state, result, old)
         "hit"     answer from the cache (result)
         "miss"    every source said no, recently       -> 404
         "failed"  a source failed recently             -> 404 + retry
         "ask"     go to the sources; `old` is a cached answer to fall back on (plain text, or one
                   given while a source was failing) so asking again can't lose it."""
    if not entry:
        return "ask", None, None
    if entry.get("lrc"):
        if entry.get("source") not in sources:
            return "ask", None, None
        res = _result(entry)
        due = entry.get("recheck")
        if due and (refresh or t >= due):
            return "ask", None, res
        return "hit", res, None
    if refresh:
        return "ask", None, None
    age = t - entry.get("at", 0)
    if entry.get("transient"):
        return ("failed", None, None) if age < TRANSIENT_TTL else ("ask", None, None)
    if entry.get("v") == CACHE_VERSION and set(sources) <= set(entry.get("tried", [])) and age < miss_ttl:
        return "miss", None, None
    return "ask", None, None


def peek(song, sources, cache, now=time.time, miss_ttl=NEGATIVE_TTL) -> str:
    """"hit" | "miss" | "failed" | "ask" from the cache alone (the prefetch uses it to skip songs)."""
    return _read(cache.get(song_key(song)), sources, now(), miss_ttl, False)[0]


def lookup_ex(song, sources, cache, get=None, now=time.time, miss_ttl=NEGATIVE_TTL, fetch=True,
              refresh=False, budget=ROUTE_BUDGET):
    """The one place that reads and writes the per-song cache (the route and the prefetch share it).
    -> Outcome(state, result): found (result is {"source","sync","lrc","cached"}), missing (every
    source answered: nobody has it), failed (a source did not answer: nothing is remembered as a miss),
    unknown (fetch=False and the cache can't say).

    A synced hit is kept for good. A miss counts for [miss_ttl] and only when this cache version
    wrote it for at least these sources. A failure is remembered for 5 minutes (not as a miss). Plain
    text, and an answer given while a source was failing, are looked at again later; asking again never
    loses what was cached. refresh=True ignores a remembered miss / failure / recheck (never a hit)."""
    key = song_key(song)
    before = cache.get(key)
    state, res, old = _read(before, sources, now(), miss_ttl, refresh)
    if state == "hit":
        return Outcome("found", res)
    if state == "miss":
        return Outcome("missing", None)
    if state == "failed":
        return Outcome("failed", None)
    if not fetch:
        return Outcome("unknown", None)
    with LOCKS.hold(key):
        entry = cache.get(key)               # someone may have asked while we waited for the lock
        rewritten = (entry or {}).get("n") != (before or {}).get("n")
        state, res, old = _read(entry, sources, now(), miss_ttl, refresh and not rewritten)
        if state == "hit":
            return Outcome("found", res)
        if state == "miss":
            return Outcome("missing", None)
        if state == "failed":
            return Outcome("failed", None)
        return _ask(key, song, sources, cache, get, now, old, budget)


def _ask(key, song, sources, cache, get, now, old, budget):
    r = resolve_ex(enrich_song(song), sources, get, budget)
    t = int(now())
    if r.found:
        name, got = r.found
        shaky = bool(r.failed) or bool(got.get("partial"))
        wait = PARTIAL_RECHECK if shaky else PLAIN_RECHECK
        if old and _RANK.get(old["sync"], 0) >= _RANK.get(got["sync"], 0):
            # Nothing better than what we hold: keep it, look again later.
            cache.put(key, {"v": CACHE_VERSION, "source": old["source"], "sync": old["sync"], "lrc": old["lrc"],
                            "recheck": t + wait})
            return Outcome("found", old)
        entry = {"v": CACHE_VERSION, "source": name, "sync": got["sync"], "lrc": got["lrc"]}
        if got["sync"] == "plain" or shaky:
            entry["recheck"] = t + wait
        cache.put(key, entry)
        return Outcome("found", {"source": name, "sync": got["sync"], "lrc": got["lrc"], "cached": False})
    if old:                                  # the sources have nothing now: the old answer stands
        cache.put(key, {"v": CACHE_VERSION, "source": old["source"], "sync": old["sync"], "lrc": old["lrc"],
                        "recheck": t + (PARTIAL_RECHECK if r.failed else PLAIN_RECHECK)})
        return Outcome("found", old)
    if r.failed:                             # somebody did not answer: NOT a miss
        cache.put(key, {"v": CACHE_VERSION, "transient": True, "tried": r.answered, "failed": r.failed})
        return Outcome("failed", None)
    cache.put(key, {"v": CACHE_VERSION, "tried": list(sources)})
    return Outcome("missing", None)


def lookup(song, sources, cache, get=None, now=time.time, miss_ttl=NEGATIVE_TTL, fetch=True, refresh=False,
           budget=ROUTE_BUDGET):
    """lookup_ex's answer as a dict, or None when nothing was found (or, fetch=False, cached)."""
    return lookup_ex(song, sources, cache, get, now, miss_ttl, fetch, refresh, budget).result


# ── the route ──────────────────────────────────────────────────────────────────────────────────

def register_lyrics_proxy_routes(app, require_auth, get=None, cache=None, now=time.time):
    cache = cache or SongCache(CACHE_DIR, now)
    hits = {}                            # user -> [timestamps in the last minute]
    refreshes = {}                       # user -> [timestamps in the last hour]
    lock = threading.Lock()

    def too_many(user):
        t = now()
        with lock:
            recent = [x for x in hits.get(user, []) if t - x < 60]
            recent.append(t)
            hits[user] = recent
            return len(recent) > RATE_PER_MIN

    def too_many_refreshes(user):
        t = now()
        with lock:
            recent = [x for x in refreshes.get(user, []) if t - x < 3600]
            recent.append(t)
            refreshes[user] = recent
            return len(recent) > REFRESH_PER_HOUR

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
        user = getattr(g, "username", "")
        if too_many(user):
            return reply({"error": "Too many lyrics requests. Try again in a minute."}, 429)
        refresh = (a.get("refresh") or "").strip().lower() in ("1", "true", "yes")
        if refresh and too_many_refreshes(user):
            return reply({"error": f"You can search again {REFRESH_PER_HOUR} times an hour. Try again later."}, 429)

        out = lookup_ex(song, sources, cache, get, now, refresh=refresh)
        if out.state == "found":
            return reply(out.result)
        if out.state == "failed":
            return reply({"error": "The lyrics sources did not answer. Try again in a moment.", "retry": True}, 404)
        return reply({"error": "No lyrics found for this song."}, 404)
