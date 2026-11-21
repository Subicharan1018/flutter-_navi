"""
navivibe/ytmusic_lyrics_helper.py   (lyrics-v2, matching tightened in v3)

Run by tg-fetcher's Python (it has ytmusicapi; the shuffle server's venv doesn't) so neither venv is
changed:   <tg-fetcher python> -I ytmusic_lyrics_helper.py < {"title","artist","duration"}

Prints ONE JSON line:
    {"sync": "line", "lines": [[start_ms, "text"], ...]}     timed lyrics
    {"sync": "plain", "text": "..."}                         untimed lyrics
    {}                                                       nothing found
Exit 0 always for "nothing"; non-zero only when the helper itself could not run or YouTube Music did not
answer (the proxy then counts the source as FAILED, never as "no lyrics").

It searches YouTube Music for the song and accepts a result only when its title matches, one of its
artists is the song's artist (v3) and its duration is within 4 s, then reads the lyrics text. No audio
or video is requested; nothing is signed in. Unofficial: it uses YouTube Music's web interface through
ytmusicapi and may go against YouTube's terms of service.
"""
import json
import re
import sys
import unicodedata

TOLERANCE_S = 4
_VARIANT = re.compile(r"\b(remix|mix|mashup|sped\s?up|slowed|reverb|live|acoustic|unplugged|instrumental|karaoke"
                      r"|revival|reprise|cover|lofi|lo-fi|8d|nightcore|extended|stripped|demo|male|female|duet)\b")


def _fold(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s or "") if not unicodedata.combining(c)).lower()


def norm(s):
    s = re.sub(r"\(.*?\)|\[.*?\]", " ", _fold(s))
    s = re.sub(r"\s[-–—]\s*(from|remaster|original|feat|with)\b.*$", " ", s)
    return " ".join(re.findall(r"\w+", s.replace("'", "")))


def variants(s):
    """remix / live / acoustic ... named in a bracket or dash tail: a different recording."""
    t = _fold(s)
    segs = re.findall(r"[\(\[]([^\)\]]*)[\)\]]", t) + re.findall(r"\s[-–—]\s(.+)$", t)
    return frozenset(m.group(1) for seg in segs for m in _VARIANT.finditer(seg)
                     if not re.match(r"\s*(from|music from)\b", seg))


def _names(s):
    parts = re.split(r"\s*(?:•|·|;|,|&|/|\bfeat\.?|\bft\.?|\bx\b|\band\b|\bwith\b)\s*", s or "", flags=re.I)
    return [set(re.findall(r"\w+", _fold(p).replace("'", ""))) for p in parts if p.strip()]


def artist_ok(want, result):
    """Any of the song's artists shares a name with one of the result's artists. No artist asked: ok."""
    mine = _names(want)
    if not mine:
        return True
    names = result.get("artists") or []
    theirs = [set(re.findall(r"\w+", _fold(a.get("name", "") if isinstance(a, dict) else str(a)).replace("'", "")))
              for a in names]
    if not any(theirs):
        return True              # the result lists no artists: the title and duration have to do
    return any(m & t for m in mine for t in theirs if m and t)


def pick(results, title, duration, artist=""):
    want = norm(title)
    want_v = variants(title)
    best = None
    for r in results or []:
        if not isinstance(r, dict) or not r.get("videoId"):
            continue
        if norm(r.get("title", "")) != want or variants(r.get("title", "")) != want_v:
            continue
        if not artist_ok(artist, r):
            continue
        d = r.get("duration_seconds")
        if duration and isinstance(d, (int, float)) and abs(d - duration) > TOLERANCE_S:
            continue
        if duration and not isinstance(d, (int, float)):
            continue
        gap = abs(d - duration) if duration and isinstance(d, (int, float)) else 0
        if best is None or gap < best[0]:
            best = (gap, r)
    return best[1] if best else None


def field(obj, *names):
    for n in names:
        v = obj.get(n) if isinstance(obj, dict) else getattr(obj, n, None)
        if v is not None:
            return v
    return None


def read(yt, video_id):
    watch = yt.get_watch_playlist(videoId=video_id)
    browse_id = (watch or {}).get("lyrics")
    if not browse_id:
        return {}
    try:
        got = yt.get_lyrics(browse_id, timestamps=True)
    except TypeError:                       # an older ytmusicapi: no timestamps argument
        got = yt.get_lyrics(browse_id)
    body = field(got, "lyrics")
    if isinstance(body, list):
        lines = []
        for l in body:
            text = field(l, "text")
            start = field(l, "start_time")
            if text and isinstance(start, (int, float)):
                lines.append([int(start), str(text)])
        if lines:
            return {"sync": "line", "lines": lines}
        return {}
    if isinstance(body, str) and body.strip():
        return {"sync": "plain", "text": body.strip()}
    return {}


def main():
    q = json.loads(sys.stdin.read() or "{}")
    title, artist = str(q.get("title") or "").strip(), str(q.get("artist") or "").strip()
    duration = q.get("duration") or 0
    full = str(q.get("full_title") or title).strip()      # with its "(Reprise)" / "- Live" tail, for matching
    if not title:
        print("{}")
        return 0
    from ytmusicapi import YTMusic
    yt = YTMusic()
    hit = pick(yt.search(f"{title} {artist}".strip(), filter="songs", limit=6), full, duration, artist)
    print(json.dumps(read(yt, hit["videoId"]) if hit else {}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:                  # a source's trouble is never the caller's
        print(f"ytmusic helper: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(3)
