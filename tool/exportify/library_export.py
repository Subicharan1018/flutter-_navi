#!/usr/bin/env python3
"""Export the whole NaviVibe library as playlist-transfer files (TuneMyMusic, Soundiiz) so it can be put into
Spotify playlists and then exported again with Exportify (which adds Spotify's energy/valence/... per song).

Reads only. Nothing on the server is changed. Python 3.9+, standard library only.

Where the library comes from (pick one):
  --subsonic URL      Navidrome's Subsonic API. Credentials from the environment, never the command line:
                      NAVIDROME_USER and NAVIDROME_PASSWORD (URL may also come from NAVIDROME_URL).
  --catalog FILE      a copy of the shuffle server's catalog.db (scp it from /opt/shuffle-server/catalog.db).
                      Has an ISRC for most songs.
Optional ISRC extras:
  --details FILE      a copy of spotify_details.db (fills ISRCs the library has none for)

Output (in --out, default ./library_export):
  navivibe_library_01.csv, _02.csv ...   title, artist, album, album artist, duration (seconds), isrc
  navivibe_library_01.txt ...            "Artist - Title" lines   (--formats csv,txt,m3u8; default csv,txt)
At most --max-songs (default 9500) songs per playlist: Spotify's cap is 10,000.

  python tool/exportify/library_export.py --catalog catalog.db --details spotify_details.db --dry-run

Calibration sample (the free transfer tiers move only a few hundred songs): the N songs that best cover energy x valence,
tempo, era, language, composers; ISRC songs first; deterministic. A later batch skips what an earlier file had.
  python tool/exportify/library_export.py --catalog catalog.db --sample 500 --out sample_1
  python tool/exportify/library_export.py --catalog catalog.db --sample 200 --exclude sample_1/navivibe_sample_01.csv --out sample_2
  python tool/exportify/library_export.py --catalog catalog.db --sample 500 --sample-report --dry-run
"""

import argparse
import csv
import hashlib
import io
import json
import os
import secrets
import sqlite3
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import library_sample  # noqa: E402

COLUMNS = ["title", "artist", "album", "album artist", "duration", "isrc"]
MAX_SONGS = 9500
_CTRL = {c: " " for c in range(32) if c not in (9,)}
_CTRL.update({127: None})


def clean(text) -> str:
    """One line of printable text: control characters and line breaks become spaces."""
    return " ".join(str(text or "").translate(_CTRL).split())


def norm_isrc(value) -> str:
    v = "".join(ch for ch in str(value or "").upper() if ch.isalnum())
    return v if len(v) == 12 and v[:2].isalpha() else ""


def make_song(title, artist="", album="", album_artist="", duration=0, isrc="") -> dict:
    try:
        dur = int(round(float(duration or 0)))
    except (TypeError, ValueError):
        dur = 0
    return {"title": clean(title), "artist": clean(artist), "album": clean(album),
            "album artist": clean(album_artist), "duration": dur, "isrc": norm_isrc(isrc)}


# ── sources ──────────────────────────────────────────────────────────────────

def read_catalog(path: str) -> list:
    c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)
    try:
        rows = c.execute("SELECT id, title, artist, album, album_artist, duration, isrc FROM songs "
                         "WHERE COALESCE(missing,0)=0 ORDER BY lower(artist), lower(album), lower(title)").fetchall()
        extra = {}
        try:        # what the sampler stratifies on; an older catalog without these columns still exports
            for r in c.execute("SELECT id, energy, valence, bpm, year, composer, language, "
                               "COALESCE(genre_display, genre_primary), feature_source FROM songs"):
                extra[r[0]] = dict(zip(("energy", "valence", "bpm", "year", "composer", "language", "genre",
                                        "feature_source"), r[1:]))
        except sqlite3.Error:
            pass
    finally:
        c.close()
    out = []
    for sid, *rest in rows:
        s = make_song(*rest)
        s["id"] = sid
        s.update(extra.get(sid, {}))
        out.append(s)
    return out


def read_details_isrcs(path: str) -> dict:
    c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)
    try:
        return {sid: norm_isrc(i) for sid, i in c.execute("SELECT song_id, isrc FROM spotify_details") if norm_isrc(i)}
    finally:
        c.close()


def subsonic_params(user: str, password: str, salt: str = None) -> dict:
    salt = salt or secrets.token_hex(6)
    return {"u": user, "t": hashlib.md5((password + salt).encode()).hexdigest(), "s": salt,
            "v": "1.16.1", "c": "navivibe-export", "f": "json"}


def subsonic_song(d: dict) -> dict:
    isrc = d.get("isrc") or ""
    if isinstance(isrc, list):                        # OpenSubsonic: a list of strings
        isrc = next((norm_isrc(x) for x in isrc if norm_isrc(x)), "")
    s = make_song(d.get("title"), d.get("artist"), d.get("album"), d.get("albumArtist") or d.get("displayAlbumArtist"),
                  d.get("duration"), isrc)
    s["id"] = d.get("id")
    return s


def read_subsonic(base: str, user: str, password: str, fetch=None, page: int = 500) -> list:
    """Every song through search3 with an empty query, in pages. `fetch(url) -> dict` is injectable for tests."""
    def real_fetch(url):
        with urllib.request.urlopen(url, timeout=60) as r:       # the URL (with the token) is never printed
            return json.loads(r.read().decode("utf-8"))
    fetch = fetch or real_fetch
    base = base.rstrip("/")
    out, offset = [], 0
    while True:
        q = dict(subsonic_params(user, password), query='""', songCount=page, songOffset=offset,
                 artistCount=0, albumCount=0)
        body = fetch(base + "/rest/search3?" + urllib.parse.urlencode(q))
        resp = body.get("subsonic-response", {})
        if resp.get("status") != "ok":
            raise SystemExit("Subsonic error: %s" % (resp.get("error", {}).get("message", "unknown")))
        songs = resp.get("searchResult3", {}).get("song", [])
        out.extend(subsonic_song(d) for d in songs)
        if len(songs) < page:
            return out
        offset += page


# ── splitting and writing ────────────────────────────────────────────────────

def merge_isrcs(songs: list, details: dict) -> None:
    for s in songs:
        if not s["isrc"] and s.get("id") in details:
            s["isrc"] = details[s["id"]]


def dedupe(songs: list) -> list:
    """The same recording once (ISRC, else title+artist+duration); the library's order is kept."""
    seen, out = set(), []
    for s in songs:
        k = s["isrc"] or (s["title"].lower(), s["artist"].lower(), s["duration"])
        if k in seen or not s["title"]:
            continue
        seen.add(k)
        out.append(s)
    return out


def split(songs: list, max_songs: int = MAX_SONGS) -> list:
    if max_songs < 1:
        raise ValueError("max_songs must be at least 1")
    return [songs[i:i + max_songs] for i in range(0, len(songs), max_songs)]


def csv_text(songs: list) -> str:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\r\n", quoting=csv.QUOTE_MINIMAL)
    w.writerow(COLUMNS)
    for s in songs:
        w.writerow([s[c] for c in COLUMNS])
    return buf.getvalue()


def txt_text(songs: list) -> str:
    return "".join("%s - %s\n" % (s["artist"], s["title"]) if s["artist"] else "%s\n" % s["title"] for s in songs)


def m3u8_text(songs: list) -> str:
    return "#EXTM3U\n" + "".join("#EXTINF:%d,%s\n%s\n" % (
        s["duration"], ("%s - %s" % (s["artist"], s["title"])) if s["artist"] else s["title"], s["title"]) for s in songs)


WRITERS = {"csv": csv_text, "txt": txt_text, "m3u8": m3u8_text}


def write_all(songs: list, out_dir: str, formats=("csv", "txt"), max_songs: int = MAX_SONGS,
              prefix: str = "navivibe_library") -> list:
    os.makedirs(out_dir, exist_ok=True)
    files = []
    for n, part in enumerate(split(songs, max_songs), 1):
        for fmt in formats:
            path = os.path.join(out_dir, "%s_%02d.%s" % (prefix, n, fmt))
            with open(path, "w", encoding="utf-8-sig" if fmt == "csv" else "utf-8", newline="") as f:
                f.write(WRITERS[fmt](part))
            files.append(path)
    return files


def summary(songs: list, max_songs: int = MAX_SONGS, formats=("csv", "txt")) -> str:
    with_isrc = sum(1 for s in songs if s["isrc"])
    parts = len(split(songs, max_songs))
    return ("songs: %d\nwith ISRC: %d (%d without)\nplaylists: %d (at most %d songs each)\nfiles: %d (%s)"
            % (len(songs), with_isrc, len(songs) - with_isrc, parts, max_songs, parts * len(formats), ", ".join(formats)))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--subsonic", metavar="URL", nargs="?", const=os.environ.get("NAVIDROME_URL", ""))
    ap.add_argument("--catalog", metavar="FILE")
    ap.add_argument("--details", metavar="FILE")
    ap.add_argument("--out", default="library_export")
    ap.add_argument("--formats", default="csv,txt")
    ap.add_argument("--max-songs", type=int, default=MAX_SONGS)
    ap.add_argument("--dry-run", action="store_true", help="only print the summary; write nothing")
    ap.add_argument("--sample", type=int, metavar="N", default=0,
                    help="write ONE calibration playlist of the N best-spread songs (needs --catalog)")
    ap.add_argument("--sample-report", action="store_true", help="print how well the sample covers the library")
    ap.add_argument("--exclude", action="append", default=[], metavar="FILE",
                    help="an earlier export CSV (ours or Exportify's): its songs are skipped; repeatable")
    ap.add_argument("--fill-gaps", action="store_true",
                    help="with --sample: pick the songs farthest (audio embedding) from every song already labelled by "
                         "Spotify (the --exclude files and the catalog's Spotify rows): the biggest coverage gaps")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--include-have-spotify", action="store_true",
                    help="also sample songs that already carry Spotify values in the catalog (default: skipped)")
    a = ap.parse_args(argv)
    formats = tuple(f for f in a.formats.split(",") if f)
    if any(f not in WRITERS for f in formats):
        ap.error("formats: choose from %s" % ", ".join(WRITERS))
    if a.max_songs > 9999:
        ap.error("--max-songs must stay under Spotify's 10,000 cap")
    if a.catalog:
        songs = read_catalog(a.catalog)
    elif a.subsonic is not None:
        user, pw = os.environ.get("NAVIDROME_USER"), os.environ.get("NAVIDROME_PASSWORD")
        if not (a.subsonic and user and pw):
            ap.error("--subsonic needs a URL and the NAVIDROME_USER / NAVIDROME_PASSWORD environment variables")
        songs = read_subsonic(a.subsonic, user, pw)
    else:
        ap.error("choose --catalog FILE or --subsonic URL")
    if a.details:
        merge_isrcs(songs, read_details_isrcs(a.details))
    songs = dedupe(songs)
    prefix = "navivibe_library"
    if a.sample or a.sample_report:
        if not a.catalog:
            ap.error("--sample needs --catalog (energy / valence / genre come from the catalog)")
        n = a.sample or 500
        ex_isrc, ex_keys = library_sample.read_exclusions(a.exclude)
        ex_ids = library_sample.excluded_ids(a.exclude, songs)
        exclude = (ex_isrc, ex_keys, ex_ids)
        if a.fill_gaps:
            import embedding_gap
            emb = embedding_gap.load_embeddings(a.catalog)
            if not emb:
                ap.error("--fill-gaps needs the embeddings table in the catalog")
            labelled = set(ex_ids) | {s["id"] for s in songs if s.get("feature_source") == "spotify"}
            print("labelled songs (earlier files + Spotify values already in the catalog): %d" % len(labelled))
            chosen = library_sample.pick_gaps(songs, n, labelled, emb, exclude, a.seed)
        else:
            chosen = library_sample.pick(songs, n, a.seed, exclude, skip_have_spotify=not a.include_have_spotify)
        print(library_sample.coverage(chosen, songs))
        if len(chosen) < n:
            print("only %d eligible songs were left (asked for %d)" % (len(chosen), n))
        songs, prefix = chosen, "navivibe_sample"
    print(summary(songs, a.max_songs, formats))
    if not a.dry_run and not (a.sample_report and not a.sample):
        files = write_all(songs, a.out, formats, a.max_songs, prefix)
        print("wrote %d files to %s" % (len(files), os.path.abspath(a.out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
