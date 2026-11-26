"""match-relaxed-v1: accept a channel post when its title is (nearly) exact and the artist cannot be compared, not only when
the artist words overlap.

What the 258 "not found" failures of 24-25 Nov 2026 showed (read from the channel cache): in 163 the channels had no FLAC post
at all, but in ~90 a FLAC post with the same title existed and was rejected. 59 of them by the artist rule alone: Spotify
names the singers, the channel names the composer or "Various Artists" ("Vinmeen": Nivas K Prasanna vs Abhay Jodhpurkar),
spells it differently ("S. Janaki" vs "S. Janki"), or gives no artist at all (a bare "12. Thiththikkum.flac").

The strict rule still runs first. Only when it finds nothing in a channel, a second look accepts a post whose title is >= 95
similar, is not a remix/live/cover/karaoke cut, and either
  - its length is within 3 s of the song's (both known): the same recording, whoever the post names, or
  - it names no artist at all and the title has two or more words.
A post that names another artist and has a different length, or an unknown length, is still refused (same-title songs
by someone else, e.g. "Thoovaanam" 265 s vs 203 s).

Anchored patch to tgfetch/channels_first.py; each anchor must be found exactly once, or nothing is written.
usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not the expected file.
"""
import sys
from pathlib import Path

CH = "tgfetch/channels_first.py"

HELPER = '''def relaxed_match(song: dict, rows: list[dict]):
    """The first cached post (a dict) that is this song by title and length, or by title when it names no artist.
    match-relaxed-v1; the strict artist rule has already found nothing."""
    import re as _re
    from rapidfuzz import fuzz
    title = song.get("title") or ""
    want = cf.norm(title)
    if not want:
        return None
    wants = set(_re.findall(r"[a-z]+", title.lower()))
    dur = song.get("duration_s")
    for r in rows:
        fname = r.get("fname") or ""
        if not ("flac" in (r.get("mime") or "").lower() or fname.lower().endswith(".flac")):
            continue
        stem = _re.sub(r"\\.[A-Za-z0-9]{2,4}$", "", fname)
        first = (r.get("text") or "").strip().splitlines()[0] if (r.get("text") or "").strip() else ""
        names = [_re.sub(r"^\\s*\\d{1,3}\\s*[.)_-]*\\s+", "", n) for n in (r.get("title") or "", stem, first) if n]   # "12. Song" -> "Song"
        if not names or max(fuzz.ratio(want, cf.norm(n)) for n in names) < 95:
            continue
        if any((set(_re.findall(r"[a-z]+", n.lower())) & cf.VERSION_WORDS) - wants for n in names):
            continue
        pdur = r.get("dur")
        if dur and pdur:
            if abs(float(dur) - float(pdur)) <= 3:
                return r
            continue
        names_artist = bool((r.get("performer") or "").strip()) or bool(_re.search(r"[A-Za-z]{3,}\\s+-\\s+[A-Za-z]{3,}", fname))
        if not names_artist and len(want.split()) >= 2:
            return r
    return None


async def find(worker, bid: int, song: dict):
'''

P = [
    (CH, "async def find(worker, bid: int, song: dict):\n", HELPER),
    (CH,
     "            _, msg = cf.best_match(title, artist, posts)\n"
     "            if msg is not None:\n"
     "                return ch, next(r for r in seen[ch] if r[\"id\"] == msg.id)\n",
     "            _, msg = cf.best_match(title, artist, posts)\n"
     "            if msg is not None:\n"
     "                return ch, next(r for r in seen[ch] if r[\"id\"] == msg.id)\n"
     "            loose = relaxed_match(song, [r for r in seen[ch] if not r[\"size\"] or r[\"size\"] <= cap])   # match-relaxed-v1\n"
     "            if loose is not None:\n"
     "                return ch, loose\n"),
    # the old parity test: the "someone else" post has the song's own length (the helper's fixed 240 s); a real other
    # recording of the same title is another length
    ("tests/test_channels_primary_v1.py",
     "    src = Src({\"one\": wrong, \"two\": []})\n    w = worker(conn, cfg, src)\n    b, jid, cand = song_job(conn)\n    bot = Bot()\n"
     "    run(chf.fetch_one(w, b, jid, cand, bot))\n    assert bot.calls == [jid]                                    # none accepted: the bot is asked\n",
     "    wrong[1].document.attributes[0].duration = 120      # match-relaxed-v1: another recording of the title is another length\n"
     "    src = Src({\"one\": wrong, \"two\": []})\n    w = worker(conn, cfg, src)\n    b, jid, cand = song_job(conn)\n    bot = Bot()\n"
     "    run(chf.fetch_one(w, b, jid, cand, bot))\n    assert bot.calls == [jid]                                    # none accepted: the bot is asked\n"),
]


def main(root: str) -> int:
    base = Path(root)
    texts: dict[str, str] = {}
    for rel, old, new in P:
        text = texts.get(rel)
        if text is None:
            text = (base / rel).read_text(encoding="utf-8")
        if new in text:
            texts[rel] = text
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected anchor not found exactly once:\n{old[:140]!r}")
            return 2
        texts[rel] = text.replace(old, new)
    for rel, text in texts.items():
        (base / rel).write_text(text, encoding="utf-8")
    print("match-relaxed-v1: channels_first.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
