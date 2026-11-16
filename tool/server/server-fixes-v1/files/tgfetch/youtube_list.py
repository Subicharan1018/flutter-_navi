"""
tgfetch/youtube_list.py  (server-fixes-v1)
──────────────────────────────────────────
A YouTube or YouTube Music playlist link → its list of names. Used ONLY as a
list of names: ytmusicapi's get_playlist (public playlists, no sign-in, no
cookies, no API key) reads titles, artists, album and length. No audio,
video, stream URL or thumbnail is ever requested; every song is then searched
on the music bot by name (tgfetch/youtube_batch.py).

Accepted links (anything else is refused with a reason the app shows as is):
  https://www.youtube.com/playlist?list=<id>      (also youtube.com, m.youtube.com)
  https://music.youtube.com/playlist?list=<id>
  https://www.youtube.com/watch?v=<video>&list=<id>  (only `list` is used)
  https://youtu.be/<video>?list=<id>                 (only `list` is used)
  <id>: [A-Za-z0-9_-]{13,64} (PL… playlists, OLAK5uy_… albums). Refused:
  RD… (mixes made for you), LL / LM / WL (liked, watch later: private), UU…
  (a channel's uploads). The link is rebuilt as
  https://music.youtube.com/playlist?list=<id>; every other parameter, the
  fragment and any user:password@ part are dropped. The user's URL is never
  fetched itself.
"""

import asyncio
import re
import unicodedata
from urllib.parse import parse_qs

from tgfetch.rank import Candidate

MAX_TRACKS = 300
TIMEOUT_S = 20
YT_HOSTS = frozenset({"youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"})
LIST_ID = re.compile(r"^[A-Za-z0-9_-]{13,64}$")
_PATHS = re.compile(r"^/(playlist|watch)/?$")
_VIDEO = re.compile(r"^/[A-Za-z0-9_-]{6,20}/?$")
_CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f​-‏‪-‮⁦-⁩]")
NOT_PLAYLIST = "That YouTube link isn't a playlist. Open the playlist and copy its link."


def _error(msg: str):
    from tgfetch.links import LinkError
    return LinkError(msg)


def is_youtube_host(host: str) -> bool:
    return host in YT_HOSTS or host == "youtu.be"


def list_id(u) -> str:
    """The playlist id of a parsed YouTube link, or LinkError saying why not."""
    host = (u.hostname or "").lower()
    if (u.scheme or "").lower() != "https":
        raise _error("Paste the playlist's https:// link.")
    if host == "youtu.be":
        if not _VIDEO.match(u.path or "/"):
            raise _error(NOT_PLAYLIST)
    elif not _PATHS.match(u.path or "/"):
        raise _error(NOT_PLAYLIST)
    lists = parse_qs(u.query or "").get("list") or []
    if len(lists) != 1 or not lists[0]:
        raise _error(NOT_PLAYLIST)
    pid = lists[0].strip()
    if pid.startswith("RD"):
        raise _error("YouTube mixes made for you can't be read. Save it as a playlist first and share that link.")
    if pid in ("LL", "LM", "WL"):
        raise _error("Liked songs and Watch later are private. Copy them into a public playlist and share that link.")
    if pid.startswith("UU") and LIST_ID.match(pid):
        raise _error("That's a channel's uploads, not a playlist. Open a playlist and copy its link.")
    if not LIST_ID.match(pid):
        raise _error("That YouTube playlist link doesn't look right. Copy it again from Share.")
    return pid


def is_youtube_link(url: str) -> bool:
    """True for a stored (canonical) YouTube playlist link; never raises."""
    from urllib.parse import urlparse
    try:
        return is_youtube_host((urlparse(url or "").hostname or "").lower())
    except ValueError:
        return False


def canonical(pid: str) -> str:
    return f"https://music.youtube.com/playlist?list={pid}"


def _client():
    from ytmusicapi import YTMusic          # installed (pinned) by server-fixes-v1/install.sh
    return YTMusic()


def _text(s, limit: int) -> str:
    s = _CONTROL.sub(" ", unicodedata.normalize("NFKC", str(s or "")))
    return re.sub(r"\s+", " ", s).strip()[:limit]


def to_candidates(data: dict) -> tuple[str, list[Candidate]]:
    """get_playlist's answer → (playlist name, candidates in order). Unavailable
    or deleted items are left out; the same video twice is one song."""
    from tgfetch.youtube_batch import apply_clean
    out, seen = [], set()
    for t in (data or {}).get("tracks") or []:
        vid = t.get("videoId") or ""
        raw = _text(t.get("title"), 300)
        if not vid or not raw or t.get("isAvailable") is False or vid in seen:
            continue
        seen.add(vid)
        artists = [_text(a.get("name"), 80) for a in (t.get("artists") or []) if isinstance(a, dict) and a.get("name")]
        album = _text(((t.get("album") or {}).get("name") if isinstance(t.get("album"), dict) else ""), 200)
        dur = t.get("duration_seconds")
        c = Candidate(index=len(out), result_id=vid, title=raw[:200], artist=", ".join(artists[:6]), album="",
                      duration_s=float(dur) if isinstance(dur, (int, float)) and dur > 0 else None)
        c.reasons = [{"youtube": {"raw": raw, "yt_artists": artists[:6], "yt_album": album,
                                  "video_type": _text(t.get("videoType"), 40)}}]
        apply_clean(c)
        out.append(c)
        if len(out) >= MAX_TRACKS:
            break
    return _text((data or {}).get("title"), 200) or "YouTube playlist", out


async def fetch(pid: str, client_factory=None, timeout: float = TIMEOUT_S) -> tuple[str, list[Candidate]]:
    """(playlist name, songs). LinkError when the list can't be read."""
    def read():
        return (client_factory or _client)().get_playlist(pid, limit=MAX_TRACKS)
    try:
        data = await asyncio.wait_for(asyncio.to_thread(read), timeout)
    except asyncio.TimeoutError:
        raise _error("YouTube took too long to answer. Try again.") from None
    except ImportError:
        raise _error("YouTube playlists aren't set up on the server yet.") from None
    except Exception:
        raise _error("That YouTube playlist is private or no longer exists.") from None
    name, songs = to_candidates(data)
    if not songs:
        raise _error("That YouTube playlist has no songs that can be read.")
    return name, songs
