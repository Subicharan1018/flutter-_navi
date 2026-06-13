#!/usr/bin/env python3
"""
One-time backfill: populate play_events.duration_s from known song durations.

Why: the /feedback pipeline never stored track length, so stats.py forced
duration_s = 0 for live plays -> Dashboard "Minutes" reads 0 for the 7/30-day
windows. This fills the existing rows in place (no events are removed) using the
legacy `plays` table as the duration source (title match, case/space-insensitive).

Coverage measured 2026-06-13: 484/713 admin rows (~67%, ~1861 min) match the
legacy table. Rows with no known duration are left at 0 and can be filled later
from Navidrome.

Usage:
    python3 backfill_play_event_durations.py            # dry run (no writes)
    python3 backfill_play_event_durations.py --apply    # write changes

Point --events / --legacy at other user DBs as needed.
"""
import argparse
import re
import sqlite3
import sys

LOG_DIR = "/DATA/Media/Music/listening_logs"
DEFAULT_EVENTS = f"{LOG_DIR}/admin_listening_log.db"
DEFAULT_LEGACY = f"{LOG_DIR}/listening_log.db"


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip().lower())


def build_duration_map(legacy_path: str) -> dict[str, int]:
    """title -> duration_s, from legacy `plays` rows that have a real duration."""
    conn = sqlite3.connect(legacy_path)
    try:
        rows = conn.execute(
            "SELECT title, duration_s FROM plays "
            "WHERE duration_s IS NOT NULL AND duration_s > 0"
        ).fetchall()
    finally:
        conn.close()
    by_title: dict[str, int] = {}
    for title, dur in rows:
        by_title.setdefault(norm(title), int(dur))
    return by_title


def ensure_column(conn: sqlite3.Connection) -> None:
    cols = {r[1] for r in conn.execute("PRAGMA table_info(play_events)").fetchall()}
    if "duration_s" not in cols:
        conn.execute("ALTER TABLE play_events ADD COLUMN duration_s INTEGER")
        print("Added column play_events.duration_s")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--events", default=DEFAULT_EVENTS)
    ap.add_argument("--legacy", default=DEFAULT_LEGACY)
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    args = ap.parse_args()

    dur_by_title = build_duration_map(args.legacy)
    print(f"Loaded {len(dur_by_title)} distinct durations from {args.legacy}")

    conn = sqlite3.connect(args.events)
    try:
        has_col = "duration_s" in {
            r[1] for r in conn.execute("PRAGMA table_info(play_events)").fetchall()
        }

        # Read-only in dry run: if the column is missing, every row needs a
        # duration; otherwise only the 0/NULL rows do.
        if has_col:
            rows = conn.execute(
                "SELECT id, track_title FROM play_events "
                "WHERE duration_s IS NULL OR duration_s = 0"
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT id, track_title FROM play_events"
            ).fetchall()

        updates = []
        for row_id, title in rows:
            dur = dur_by_title.get(norm(title))
            if dur:
                updates.append((dur, row_id))

        added_sec = sum(d for d, _ in updates)
        print(
            f"Rows missing duration: {len(rows)} | "
            f"backfillable from legacy: {len(updates)} | "
            f"minutes added: {added_sec // 60}"
        )

        if not args.apply:
            print("DRY RUN — re-run with --apply to write.")
            return 0

        ensure_column(conn)
        conn.executemany(
            "UPDATE play_events SET duration_s = ? WHERE id = ?", updates
        )
        conn.commit()
        print(f"Applied {len(updates)} updates to {args.events}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
