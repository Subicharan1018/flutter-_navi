"""
spotify-history-import-v1: dry run of the whole pipeline on a real export, WITHOUT touching a live server.

    PYTHONPATH=<shuffle-server checkout with navivibe/> python files/tools/dryrun.py \
        <export folder> <catalog.db copy> [--tg <tg-fetcher root>] [--out report.json]

  1. reads Streaming_History_Audio_*.json (or StreamingHistory*.json) and strips them exactly like the app's parser
     (lib/features/spotify_import/logic/spotify_parser.dart): only ts, ms, title, artist, album, reason_end, skipped
     stay; episodes, audiobooks, incognito plays and rows without a title are dropped; video files are never read;
  2. loads the songs of a catalog copy as the library;
  3. runs the real server code (tgfetch/spotify_history.py) page by page into a SCRATCH fetch.db and a SCRATCH
     listening-log folder (temp dir, deleted at the end);
  4. prints counts only. Unmatched titles are shown as shapes (first letter + length), never as text.

Nothing is written outside the temp dir, and nothing is sent anywhere.
"""

import argparse
import collections
import json
import re
import shutil
import sqlite3
import sys
import tempfile
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

PAGE = 1000


def strip_extended(rows) -> tuple[list[dict], collections.Counter]:
    """The app's cleaner, step for step (see spotify_parser.dart)."""
    drop = collections.Counter()
    out = []
    for r in rows:
        if not isinstance(r, dict):
            drop["not_object"] += 1
            continue
        if r.get("episode_name") or r.get("spotify_episode_uri") or r.get("episode_show_name"):
            drop["episode"] += 1
            continue
        if r.get("audiobook_title") or r.get("audiobook_uri") or r.get("audiobook_chapter_uri"):
            drop["audiobook"] += 1
            continue
        if r.get("incognito_mode") is True:
            drop["incognito"] += 1
            continue
        title, artist = r.get("master_metadata_track_name"), r.get("master_metadata_album_artist_name")
        if not isinstance(title, str) or not title.strip() or not isinstance(artist, str) or not artist.strip():
            drop["no_title_or_artist"] += 1
            continue
        try:
            t = int(datetime.fromisoformat(str(r.get("ts")).replace("Z", "+00:00")).timestamp())
        except (ValueError, TypeError):
            drop["bad_time"] += 1
            continue
        ms = r.get("ms_played")
        if isinstance(ms, bool) or not isinstance(ms, (int, float)):
            drop["bad_ms"] += 1
            continue
        sk = r.get("skipped")
        out.append({"t": t, "ms": int(ms), "title": title, "artist": artist,
                    "album": r.get("master_metadata_album_album_name") or "",
                    "end": r.get("reason_end") or "", "sk": sk if isinstance(sk, bool) else None})
    return out, drop


def strip_basic(rows) -> tuple[list[dict], collections.Counter]:
    drop = collections.Counter()
    out = []
    for r in rows:
        if not isinstance(r, dict) or not r.get("trackName") or not r.get("artistName"):
            drop["no_title_or_artist"] += 1
            continue
        try:   # "2023-11-02 11:28" (UTC)
            t = int(datetime.strptime(r["endTime"], "%Y-%m-%d %H:%M").replace(tzinfo=timezone.utc).timestamp())
        except (ValueError, KeyError, TypeError):
            drop["bad_time"] += 1
            continue
        ms = r.get("msPlayed")
        if isinstance(ms, bool) or not isinstance(ms, (int, float)):
            drop["bad_ms"] += 1
            continue
        out.append({"t": t, "ms": int(ms), "title": r["trackName"], "artist": r["artistName"], "album": "",
                    "end": "", "sk": None})
    return out, drop


def shape(title: str) -> str:
    """first letter + the rest as dots: 'Neela Megam (feat. X)' -> 'N••••• M••••• (f•••. X)'"""
    return re.sub(r"(?<=\w)\w", "•", title)


def script_of(s: str) -> str:
    for ch in s:
        if ch.isalpha():
            n = unicodedata.name(ch, "")
            return "latin" if n.startswith("LATIN") else n.split(" ")[0].lower()
    return "none"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("export")
    ap.add_argument("catalog")
    ap.add_argument("--tg", default=None)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    if a.tg:
        sys.path.insert(0, a.tg)
    from tgfetch import db, exportify as ex, history_import as hi, spotify_history as sh

    folder = Path(a.export)
    ext = sorted(folder.glob("Streaming_History_Audio_*.json"))
    basic = sorted(folder.glob("StreamingHistory*.json"))
    fmt = "extended" if ext else "basic"
    files = ext or basic
    total_rows, plays, drop = 0, [], collections.Counter()
    for f in files:
        data = json.loads(f.read_text(encoding="utf-8"))
        total_rows += len(data)
        p, d = (strip_extended if fmt == "extended" else strip_basic)(data)
        plays += p
        drop.update(d)
    plays.sort(key=lambda r: r["t"])

    cat = sqlite3.connect(f"file:{Path(a.catalog).as_posix()}?mode=ro", uri=True)
    cat.row_factory = sqlite3.Row
    library = [dict(r) | {"isrc": (r["isrc"] or "")} for r in cat.execute(
        "SELECT id, title, artist, album, duration, isrc FROM songs")]
    cat.close()

    tmp = Path(tempfile.mkdtemp(prefix="spotify-dryrun-"))
    try:
        import os
        os.environ["NAVIVIBE_LOG_DIR"] = str(tmp / "logs")
        conn = db.connect(tmp / "fetch.db")
        sh.ensure_schema(conn)
        job = sh.create_job(conn, "vijay", fmt, len(plays))[0]
        now = datetime.now(timezone.utc).timestamp()
        s = {}
        for i in range(0, len(plays), PAGE):
            s = sh.page(conn, job["id"], "vijay", library, plays[i:i + PAGE], now=now)
        s = sh.finish(conn, job["id"], "vijay")

        # a second, identical import must add nothing
        j2 = sh.create_job(conn, "vijay", fmt, len(plays))[0]
        again = {}
        for i in range(0, len(plays), PAGE):
            again = sh.page(conn, j2["id"], "vijay", library, plays[i:i + PAGE], now=now)
        again = sh.finish(conn, j2["id"], "vijay")
        log = hi.open_log("vijay")
        log.row_factory = sqlite3.Row
        n_log = log.execute("SELECT COUNT(*) FROM play_events").fetchone()[0]
        by_type = {r[0]: r[1] for r in log.execute("SELECT event_type, COUNT(*) FROM play_events GROUP BY 1")}
        by_reason = {r[0]: r[1] for r in log.execute("SELECT end_reason, COUNT(*) FROM play_events GROUP BY 1")}
        bad = log.execute("SELECT COUNT(*) FROM play_events WHERE seconds_played<0 OR listen_ratio<0 OR listen_ratio>1 "
                          "OR (event_type='complete' AND listen_ratio<0.5)").fetchone()[0]
        log.close()

        # distinct songs
        idx = sh.Index(library)
        songs: dict[str, dict] = {}
        for p in plays:
            k = ex.song_key("", p["title"].strip(), p["artist"].strip())
            e = songs.setdefault(k, {"title": p["title"], "artist": p["artist"], "plays": 0, "listens": 0})
            e["plays"] += 1
            e["listens"] += sh.skip_decision(p["ms"], p["end"], p["sk"], fmt) == "listen"
        matched = {k for k, e in songs.items() if idx.find(e["title"].strip(), e["artist"].strip(), None,
                                                               hi.DURATION_SLACK_S)}
        un = {k: e for k, e in songs.items() if k not in matched}
        un_listened = {k: e for k, e in un.items() if e["listens"] > 0}
        lib_titles = collections.defaultdict(set)
        for sng in library:
            lib_titles[sng["title"].casefold()].add(sng["artist"].casefold())
        why = collections.Counter()
        examples = []
        for k, e in sorted(un_listened.items(), key=lambda kv: -kv[1]["plays"]):
            t = e["title"]
            tags = []
            if script_of(t) != "latin":
                tags.append(f"script:{script_of(t)}")
            if re.search(r"\b(remix|sped up|slowed|reverb|live|acoustic|remaster|version|edit|cover|instrumental)\b", t, re.I):
                tags.append("version word")
            if re.search(r"\((feat|ft|with)\b|\bfeat\.", t, re.I):
                tags.append("feat in title")
            if re.search(r"\bfrom\b|\bmovie\b|\boriginal motion picture\b", t, re.I):
                tags.append("film/from tag")
            if t.casefold() in lib_titles:
                tags.append("title in library, other artist")
            if not tags:
                tags.append("plain: not in library")
            for g in tags:
                why[g] += 1
            if len(examples) < 12:
                examples.append({"shape": shape(t), "artist_shape": shape(e["artist"]), "listens": e["listens"],
                                 "why": tags})

        rep = {
            "files": [f.name for f in files], "format": fmt, "rows_in_files": total_rows,
            "dropped": dict(drop), "music_plays_kept": len(plays),
            "date_range": [datetime.fromtimestamp(plays[0]["t"], timezone.utc).date().isoformat(),
                           datetime.fromtimestamp(plays[-1]["t"], timezone.utc).date().isoformat()] if plays else None,
            "server": {k: s[k] for k in ("fetched", "imported", "wished", "already", "near_dups", "skips", "listens",
                                         "unclear", "skip_misses", "rejected", "rejected_total", "songs_matched",
                                         "songs_unmatched")},
            "log_rows": n_log, "log_by_event_type": by_type, "log_by_end_reason": by_reason, "log_rows_out_of_range": bad,
            "second_import": {k: again[k] for k in ("fetched", "imported", "wished", "already")},
            "wishlist_songs": conn.execute("SELECT COUNT(*) FROM exportify_songs").fetchone()[0],
            "wishlist_cap": hi.MAX_WISHLIST,
            "library_songs": len(library),
            "distinct_songs": len(songs), "distinct_matched": len(matched), "distinct_unmatched": len(un),
            "distinct_unmatched_listened": len(un_listened),
            "match_rate_songs": round(len(matched) / max(1, len(songs)), 4),
            "match_rate_plays": round(sum(songs[k]["plays"] for k in matched) / max(1, len(plays)), 4),
            "match_rate_listened_songs": round(
                sum(1 for k in matched if songs[k]["listens"]) / max(1, sum(1 for e in songs.values() if e["listens"])), 4),
            "unmatched_reasons": dict(why.most_common()), "unmatched_examples_shapes": examples,
        }
        print(json.dumps(rep, indent=2, ensure_ascii=False))
        if a.out:
            Path(a.out).write_text(json.dumps(rep, indent=2, ensure_ascii=False), encoding="utf-8")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
