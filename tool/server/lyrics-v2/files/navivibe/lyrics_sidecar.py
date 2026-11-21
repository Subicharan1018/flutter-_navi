"""
navivibe/lyrics_sidecar.py   (lyrics-v2)   OPT-IN. Does nothing to your files unless told to.

Writes <song>.lrc next to the audio file for songs whose lyrics are in the lyrics cache, so Navidrome
(on its next scan) and any other client show them too.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m navivibe.lyrics_sidecar            # DRY RUN
    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m navivibe.lyrics_sidecar --apply    # writes

      default   a dry run: says how many files it WOULD add and shows a few names; writes nothing
      --apply   actually writes the files
      --plain   also write songs whose lyrics are plain text (not timed) as .lrc; default: timed only
      --words   keep word timing tags (<mm:ss.xx>) in the file; default: line timing only, which is
                what every LRC reader understands
      --music-root DIR   where the audio is (default /DATA/Media/Music or $NAVIVIBE_MUSIC_ROOT)
      --limit N

Safe by rules: it never overwrites or touches an existing .lrc (yours, or tg-fetcher's); it only
writes inside the music root; a file name is the audio file's with the extension swapped, the same
way tg-fetcher names its own sidecars. The tg-fetcher auto-import watcher only imports audio files
(.flac .mp3 .m4a ...), so a new .lrc is ignored by it; it also leaves a FLAC alone that already has
a .lrc.
"""
import argparse
import os
import re
import sqlite3
import sys

from navivibe import lyrics_proxy as lp

WORD_TAG = re.compile(r"<\d{1,2}:\d{2}[.:]\d{2,3}>\s*")
DEFAULT_ROOT = os.getenv("NAVIVIBE_MUSIC_ROOT", "/DATA/Media/Music")


def line_lrc(lrc: str) -> str:
    """Enhanced LRC -> plain line-timed LRC (the word tags dropped, spaces kept)."""
    return "\n".join(WORD_TAG.sub("", l).strip() for l in lrc.splitlines() if l.strip())


def plan(db_path, cache, root, include_plain=False, keep_words=False, limit=0):
    """-> (to_write [(path, text, source)], skipped {reason: count}). Reads only."""
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5)
    try:
        rows = con.execute("SELECT id, title, artist, duration, path FROM songs "
                           "WHERE missing = 0 AND path IS NOT NULL AND path <> '' ORDER BY id").fetchall()
    finally:
        con.close()
    root = os.path.realpath(root)
    out, skipped = [], {"no lyrics cached": 0, "plain text (use --plain)": 0, "already has a .lrc": 0,
                        "audio file not found": 0, "outside the music root": 0}
    for sid, title, artist, duration, rel in rows:
        entry = cache.get(sid)
        if not entry or not entry.get("lrc"):
            skipped["no lyrics cached"] += 1
            continue
        timed = entry.get("sync") in ("word", "line")
        if not timed and not include_plain:
            skipped["plain text (use --plain)"] += 1
            continue
        audio = os.path.realpath(os.path.join(root, rel))
        if not audio.startswith(root + os.sep):
            skipped["outside the music root"] += 1
            continue
        if not os.path.isfile(audio):
            skipped["audio file not found"] += 1
            continue
        target = os.path.splitext(audio)[0] + ".lrc"
        if os.path.exists(target) or os.path.islink(target):
            skipped["already has a .lrc"] += 1
            continue
        text = entry["lrc"] if (keep_words or not timed) else line_lrc(entry["lrc"])
        out.append((target, text.strip() + "\n", entry.get("source", "")))
        if limit and len(out) >= limit:
            break
    return out, skipped


def apply(to_write):
    written = 0
    for path, text, _ in to_write:
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)   # EXCL: never overwrite
        except FileExistsError:
            continue
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        written += 1
    return written


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--plain", action="store_true")
    ap.add_argument("--words", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--music-root", default=DEFAULT_ROOT)
    ap.add_argument("--cache-dir", default=lp.CACHE_DIR)
    ap.add_argument("--catalog", default=lp.CATALOG_DB)
    a = ap.parse_args(argv)
    if not os.path.isdir(a.music_root):
        print(f"!! {a.music_root} is not a folder")
        return 1
    todo, skipped = plan(a.catalog, lp.SongCache(a.cache_dir), a.music_root, a.plain, a.words, a.limit)
    for reason, n in skipped.items():
        if n:
            print(f"   skipped {n}: {reason}")
    if not a.apply:
        print(f"DRY RUN: would add {len(todo)} .lrc files under {a.music_root} (nothing written).")
        for path, _, source in todo[:5]:
            print(f"   e.g. {os.path.relpath(path, a.music_root)}  ({source})")
        print("Run with --apply to write them. Then rescan the library in Navidrome.")
        return 0
    n = apply(todo)
    print(f"wrote {n} .lrc files under {a.music_root}. Rescan the library in Navidrome to show them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
