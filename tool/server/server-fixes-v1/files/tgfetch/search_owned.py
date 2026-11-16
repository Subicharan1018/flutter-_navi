"""
tgfetch/search_owned.py  (server-fixes-v1)
──────────────────────────────────────────
Online song search and the library.

Before: a song search whose text equalled a library title (or sounded like
one) finished at once as `in_library`, whatever the artist. "pondatti" found
the user's "Pondatti" and never asked the bot, though the user wanted another
song with that name.

Now a search ends as `in_library` only when the text names the song AND its
artist: the title plus words that are all in that song's artist credit
("pondatti anirudh", "anirudh pondatti"). A title alone runs the bot search as
usual, and the owned song comes back beside the results as a hint:

    "owned_hint": {"song_id": "…", "title": "…", "artist": "…", "album": "…"}

Force ("Search online anyway"): `POST /searches` with `"force": true` or
`?force=1` marks a song search `forced`. It never ends as `in_library`; the
bot is always asked, and owned_hint is still set when the library has the title.

Superseding: a user's newer search replaces their older one that is still
queued or running (switching Songs → Albums no longer waits behind a slow
song search). The older one gets status `superseded`; a running one stops
before its next bot request.
"""

import re
import time

from rapidfuzz import fuzz

from navivibe.catalog.enrich import norm_title
from navivibe.recsys.data import phonetic_key
from tgfetch.library import IN_LIBRARY, other_version

ARTIST_WORD = 85            # a typed word is in the credit when it is this close to one of its words
USER_KINDS = ("song", "album", "artist", "playlist", "label")


def _words(s: str) -> list[str]:
    return norm_title(re.sub(r"\.\s*", "", s or "")).split()


def _in_credit(words: list[str], credit: str) -> bool:
    have = _words(credit)
    return bool(words) and all(any(w == h or (len(w) > 3 and fuzz.ratio(w, h) >= ARTIST_WORD) for h in have)
                               for w in words)


def _rest(q: list[str], t: list[str]) -> list[str] | None:
    """The words of q around title t (t at the start or the end), or None."""
    n = len(t)
    if n == 0 or len(q) <= n:
        return None
    if q[:n] == t:
        return q[n:]
    if q[-n:] == t:
        return q[:-n]
    return None


def clearly_named(query: str, library: list[dict]) -> dict | None:
    """The library song the query names by title AND artist, or None."""
    q = norm_title(query).split()
    if len(q) < 2:
        return None
    best = None
    for song in library:
        t = norm_title(song.get("title") or "").split()
        rest = _rest(q, t)
        if rest is None:
            # Same title in another spelling: compare phonetically, title first or last.
            for n in range(1, len(q)):
                for title_part, extra in ((q[:n], q[n:]), (q[-n:], q[:-n])):
                    if t and phonetic_key(" ".join(title_part)) == phonetic_key(" ".join(t)):
                        rest = extra
                        break
                if rest is not None:
                    break
        if rest is None or not _in_credit(rest, song.get("artist") or ""):
            continue
        if other_version(song.get("title") or "", query):
            continue
        if best is None or float(song.get("duration") or 0) > float(best.get("duration") or 0):
            best = song
    return best


def verdict_for(song: dict, query: str) -> dict:
    """The `library` payload of an in_library search (the shape check() returns)."""
    return {"query": query, "artist": "", "verdict": "in_library",
            "matches": [{"id": song["id"], "title": song["title"], "artist": song["artist"],
                         "album": song.get("album", ""), "suffix": song.get("suffix", ""),
                         "score": 100.0, "reason": "title and artist"}]}


def with_hint(owned: dict) -> dict:
    """check()'s result plus `hint`: the owned song with this exact title, if any."""
    top = (owned.get("matches") or [None])[0]
    if top and top.get("score", 0) >= IN_LIBRARY:
        owned = {**owned, "hint": {"song_id": top["id"], "title": top["title"], "artist": top["artist"],
                                   "album": top.get("album", "")}}
    return owned


def hint_of(library_payload) -> dict | None:
    """What the API sends as owned_hint for a search."""
    if isinstance(library_payload, dict):
        h = library_payload.get("hint")
        return h if isinstance(h, dict) else None
    return None


# ── "Search online anyway" ───────────────────────────────────────────────────

def wants_force(body_flag, query_value) -> bool:
    """`"force": true` in the body or `?force=1` (also true/yes) on the URL."""
    return body_flag is True or str(query_value or "").strip().lower() in ("1", "true", "yes")


def mark_forced(conn, search_id: int) -> None:
    """A forced song search never ends as in_library; the bot is always asked."""
    conn.execute("UPDATE searches SET forced=1 WHERE id=?", (search_id,))


# ── one search at a time per user ────────────────────────────────────────────

def supersede_older(conn, user: str, newer_id: int) -> int:
    """Mark the user's older queued / running searches superseded. Link
    previews and an artist's song list are left alone (not a type switch)."""
    marks = ",".join("?" * len(USER_KINDS))
    return conn.execute(
        f"UPDATE searches SET status='superseded', note='Replaced by a newer search', updated_at=? "
        f"WHERE user=? AND id<? AND status IN ('queued', 'searching') AND kind IN ({marks})",
        (time.time(), user, newer_id, *USER_KINDS)).rowcount


def is_superseded(conn, search_id: int) -> bool:
    r = conn.execute("SELECT status FROM searches WHERE id=?", (search_id,)).fetchone()
    return r is not None and r[0] == "superseded"


class Superseded(Exception):
    """Raised inside a running search when a newer one replaced it."""
