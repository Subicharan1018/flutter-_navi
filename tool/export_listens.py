#!/usr/bin/env python3
"""Export one user's listening history (every play, with time, album and cover) from Navidrome.

Navidrome 0.64 keeps one row per play in its `scrobbles` table (user, song, submission_time in
unix seconds, UTC). This reads it read-only and writes CSV and/or JSON, optionally with the
album covers downloaded. Nothing on the server is changed. Python 3.9+, standard library only.

Where the data comes from (pick one):
  --db navidrome.db            a copy of the file (scp it from /DATA/AppData/navidrome/data/)
  --ssh <user>@<host>     reads the live file over ssh with `sqlite3 -readonly`
                               (needs Tailscale up and sqlite3 on the server)

Examples:
  python tool/export_listens.py --ssh <user>@<host> --user admin --out listens
  python tool/export_listens.py --db navidrome.db --user admin --from 2026-11-01 --to 2026-11-22 --out listens
  python tool/export_listens.py --db navidrome.db --user admin --out listens \
      --covers listens_covers --navidrome-url http://<host>:4533 --navidrome-user admin
      (the Navidrome password is read from the NAVIDROME_PASSWORD environment variable, never from the command line)

Output columns: played_at_utc, played_at_epoch, title, artist, album, album_artist, duration_s,
song_id, album_id, cover_id (use with Subsonic getCoverArt), cover_file (when --covers is used).
`played_at` is when Navidrome recorded the play (about when the song was counted as heard, not when
it started); subtract duration_s if you need an approximate start.
"""

import argparse
import csv
import hashlib
import json
import os
import re
import secrets
import shlex
import sqlite3
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

SQL = (
    "SELECT s.submission_time AS played_at_epoch, m.title, m.artist, m.album, m.album_artist, "
    "ROUND(m.duration) AS duration_s, m.id AS song_id, m.album_id "
    "FROM scrobbles s JOIN user u ON u.id = s.user_id JOIN media_file m ON m.id = s.media_file_id "
    "WHERE u.user_name = {user} AND s.submission_time >= {lo} AND s.submission_time < {hi} "
    "ORDER BY s.submission_time"
)
USER_OK = re.compile(r"^[\w .@+-]{1,64}$")


def day_start(text: str, end: bool = False) -> int:
    """'2026-11-22' -> epoch seconds at 00:00 UTC (the day after, for an end date: it is inclusive)."""
    d = datetime.strptime(text, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    return int(d.timestamp()) + (86400 if end else 0)


def quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def query(user: str, lo: int, hi: int) -> str:
    return SQL.format(user=quote(user), lo=int(lo), hi=int(hi))


def rows_from_db(path: str, user: str, lo: int, hi: int) -> list[dict]:
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in conn.execute(query(user, lo, hi))]
    finally:
        conn.close()


def rows_from_ssh(host: str, user: str, lo: int, hi: int,
                  db: str = "/DATA/AppData/navidrome/data/navidrome.db") -> list[dict]:
    if not re.match(r"^[\w.@-]+$", host):
        sys.exit("--ssh must look like user@host")
    remote = " ".join(shlex.quote(x) for x in
                      ["sqlite3", "-readonly", "-csv", "-header", db, query(user, lo, hi)])
    cmd = ["ssh", "-o", "BatchMode=yes", host, remote]      # ssh joins args for the remote shell: quote them
    out = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    if out.returncode:
        sys.exit(f"ssh failed: {out.stderr.strip() or out.returncode}")
    return list(csv.DictReader(out.stdout.splitlines()))


def tidy(row: dict) -> dict:
    epoch = int(row["played_at_epoch"])
    return {
        "played_at_utc": datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "played_at_epoch": epoch,
        "title": row["title"], "artist": row["artist"], "album": row["album"],
        "album_artist": row["album_artist"],
        "duration_s": int(float(row["duration_s"] or 0)),
        "song_id": row["song_id"], "album_id": row["album_id"],
        "cover_id": f"al-{row['album_id']}" if row["album_id"] else "",
    }


def download_covers(rows: list[dict], folder: str, url: str, user: str, size: int = 300) -> int:
    """One JPEG per album through the Subsonic API (token auth: the password is never sent)."""
    password = os.environ.get("NAVIDROME_PASSWORD", "")
    if not password:
        sys.exit("set NAVIDROME_PASSWORD in the environment to download covers")
    out = Path(folder)
    out.mkdir(parents=True, exist_ok=True)
    got = 0
    for cover in sorted({r["cover_id"] for r in rows if r["cover_id"]}):
        target = out / f"{cover}.jpg"
        if not target.exists():
            salt = secrets.token_hex(6)
            params = urllib.parse.urlencode({
                "u": user, "t": hashlib.md5((password + salt).encode()).hexdigest(), "s": salt,
                "v": "1.16.1", "c": "export-listens", "id": cover, "size": size})
            try:
                with urllib.request.urlopen(f"{url.rstrip('/')}/rest/getCoverArt?{params}", timeout=30) as r:
                    target.write_bytes(r.read())
            except Exception as e:                      # one missing cover never stops the export
                print(f"  cover {cover}: {e}", file=sys.stderr)
                continue
        got += 1
    for r in rows:
        r["cover_file"] = f"{cover_name(r['cover_id'])}" if (out / f"{r['cover_id']}.jpg").exists() else ""
    return got


def cover_name(cover_id: str) -> str:
    return f"{cover_id}.jpg"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--db", help="a copy of navidrome.db")
    src.add_argument("--ssh", help="user@host that has the live navidrome.db")
    ap.add_argument("--user", required=True, help="the Navidrome user name whose plays to export")
    ap.add_argument("--from", dest="start", help="first day, YYYY-MM-DD (UTC), default: everything")
    ap.add_argument("--to", dest="end", help="last day, YYYY-MM-DD (UTC, inclusive)")
    ap.add_argument("--out", default="listens", help="output name without extension (writes .csv and .json)")
    ap.add_argument("--covers", help="folder to download one cover per album into")
    ap.add_argument("--navidrome-url", help="needed with --covers, e.g. http://<host>:4533")
    ap.add_argument("--navidrome-user", help="needed with --covers (defaults to --user)")
    a = ap.parse_args()
    if not USER_OK.match(a.user):
        sys.exit("unexpected characters in --user")
    lo = day_start(a.start) if a.start else 0
    hi = day_start(a.end, end=True) if a.end else 4102444800        # 2100-01-01
    raw = rows_from_db(a.db, a.user, lo, hi) if a.db else rows_from_ssh(a.ssh, a.user, lo, hi)
    rows = [tidy(r) for r in raw]
    if a.covers:
        if not a.navidrome_url:
            sys.exit("--covers needs --navidrome-url")
        n = download_covers(rows, a.covers, a.navidrome_url, a.navidrome_user or a.user)
        print(f"covers: {n} albums in {a.covers}")
    cols = list(rows[0].keys()) if rows else list(tidy(
        {"played_at_epoch": 0, "title": "", "artist": "", "album": "", "album_artist": "",
         "duration_s": 0, "song_id": "", "album_id": ""}).keys())
    if a.covers and "cover_file" not in cols:
        cols.append("cover_file")
    with open(f"{a.out}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    Path(f"{a.out}.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
    first = rows[0]["played_at_utc"] if rows else "-"
    last = rows[-1]["played_at_utc"] if rows else "-"
    print(f"{len(rows)} plays, {first} .. {last} -> {a.out}.csv, {a.out}.json")


if __name__ == "__main__":
    main()
