"""
navivibe/ytmusic_lyrics_helper.py   (lyrics-v2)

Run by tg-fetcher's Python (it has ytmusicapi; the shuffle server's venv doesn't) so neither venv is
changed:   <tg-fetcher python> -I ytmusic_lyrics_helper.py < {"title","artist","duration"}

Prints ONE JSON line:
    {"sync": "line", "lines": [[start_ms, "text"], ...]}     timed lyrics
    {"sync": "plain", "text": "..."}                         untimed lyrics
    {}                                                       nothing found
Exit 0 always for "nothing"; non-zero only for a broken environment.

It searches YouTube Music for the song, accepts a result only when its title matches and its duration
is within 4 s, then reads the lyrics text. No audio or video is requested; nothing is signed in.
Unofficial: it uses YouTube Music's web interface through ytmusicapi and may go against YouTube's
terms of service.
"""
import json
import re
import sys

TOLERANCE_S = 4


def norm(s):
    s = re.sub(r"\(.*?\)|\[.*?\]", " ", (s or "").lower())
    return " ".join(re.findall(r"\w+", s))


def pick(results, title, duration):
    want = norm(title)
    best = None
    for r in results or []:
        if not isinstance(r, dict) or not r.get("videoId"):
            continue
        if norm(r.get("title", "")) != want:
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
    if not title:
        print("{}")
        return 0
    from ytmusicapi import YTMusic
    yt = YTMusic()
    hit = pick(yt.search(f"{title} {artist}".strip(), filter="songs", limit=6), title, duration)
    print(json.dumps(read(yt, hit["videoId"]) if hit else {}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:                  # a source's trouble is never the caller's
        print(f"ytmusic helper: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(3)
