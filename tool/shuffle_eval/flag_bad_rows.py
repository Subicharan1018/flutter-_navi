#!/usr/bin/env python3
"""Backup-first cleanup for existing listening-log rows. RUN BY THE OWNER, never by a session.

It never deletes a row. It only ADDS information:
  * adds the columns `origin` and `quality` if missing
  * origin  = app | navidrome_sync | import   (from session_id, for rows that have none)
  * quality = suspect_burst   "finished naturally at 0 %" from the old app (not a real listen)
              synthetic_time  Navidrome-sync rows beyond the first one of a song that share one
                              invented timestamp
              impossible      ratio outside 0..1, duration < 0 or > 6 h, time in the future/before 2020
  Rows already carrying a `quality` value are left alone.
  * with --null-fake-weather: weather_code / temperature_c = NULL on old app rows that carry the
    constant 800 / 25.0 (the old app sent those for every play). Off by default.

Nothing in the server reads `quality` until the play-events-v2 package is installed, and then
only to keep suspect rows out of live learning; tagging alone changes no recommendation.

Usage (dry run is the default; --apply writes):
    python3 flag_bad_rows.py --db /DATA/AppData/navivibe/listening_logs/admin_listening_log.db
    python3 flag_bad_rows.py --db ...admin_listening_log.db --apply
    python3 flag_bad_rows.py --dir /DATA/AppData/navivibe/listening_logs --apply

Safety:
  1. a consistent copy is made with SQLite's backup API to <db>.bak-<timestamp> first;
     the script stops if the copy fails or fails PRAGMA integrity_check
  2. everything is one transaction (BEGIN IMMEDIATE, 30 s lock wait); an error rolls it back
  3. it prints the counts before and after
Undo: stop the service, copy the .bak file over the .db (delete any -wal/-shm beside it), start it.
"""
import argparse
import glob
import os
import sqlite3
import sys
import time

MIN_VALID_EPOCH = 1577836800
FUTURE_SKEW_S = 300

ORIGIN_SQL = ("UPDATE play_events SET origin = CASE WHEN session_id = 'navidrome_sync' THEN 'navidrome_sync' "
              "WHEN session_id LIKE 'import:%' THEN 'import' ELSE 'app' END WHERE origin IS NULL")

BURST_SQL = ("UPDATE play_events SET quality = 'suspect_burst' WHERE quality IS NULL AND origin = 'app' "
             "AND LOWER(COALESCE(end_reason,'')) IN ('natural','trackdone') AND listen_ratio = 0")

SYNC_SQL = ("UPDATE play_events SET quality = 'synthetic_time' WHERE quality IS NULL AND origin = 'navidrome_sync' "
            "AND id NOT IN (SELECT MAX(id) FROM play_events WHERE origin = 'navidrome_sync' "
            "GROUP BY track_title, played_at)")

IMPOSSIBLE_SQL = ("UPDATE play_events SET quality = 'impossible' WHERE quality IS NULL AND ("
                  "listen_ratio < 0 OR listen_ratio > 1.0001 OR duration_s < 0 OR duration_s > 21600 "
                  "OR played_at > :future OR played_at < :min_epoch)")

FAKE_WEATHER_SQL = ("UPDATE play_events SET weather_code = NULL, temperature_c = NULL WHERE origin = 'app' "
                    "AND weather_code = 800 AND temperature_c = 25.0")


def _counts(conn):
    rows = conn.execute("SELECT COALESCE(quality,'(none)'), COUNT(*) FROM play_events GROUP BY 1").fetchall()
    return dict(rows)


def backup(db):
    dest = "%s.bak-%s" % (db, time.strftime("%Y%m%d-%H%M%S"))
    if os.path.exists(dest):
        raise SystemExit("backup target exists: %s" % dest)
    src = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(db).replace("\\", "/"), uri=True, timeout=30)
    try:
        dst = sqlite3.connect(dest)
        try:
            src.backup(dst)
        finally:
            dst.close()
    finally:
        src.close()
    chk = sqlite3.connect(dest)
    try:
        ok = chk.execute("PRAGMA integrity_check").fetchone()[0]
        n_src = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(db).replace("\\", "/"), uri=True).execute(
            "SELECT COUNT(*) FROM play_events").fetchone()[0]
        n_bak = chk.execute("SELECT COUNT(*) FROM play_events").fetchone()[0]
    finally:
        chk.close()
    if ok != "ok" or n_bak < n_src - 5:   # a few rows may arrive while it copies; a big gap is a bad copy
        os.remove(dest)
        raise SystemExit("backup failed verification (%s, %d vs %d rows): nothing changed" % (ok, n_bak, n_src))
    return dest


def process(db, apply, null_fake_weather, now=None):
    now = int(now or time.time())
    ro = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(db).replace("\\", "/"), uri=True, timeout=30)
    try:
        if not ro.execute("SELECT 1 FROM sqlite_master WHERE name='play_events'").fetchone():
            print("  %s: no play_events table, skipped" % os.path.basename(db))
            return None
        before_rows = ro.execute("SELECT COUNT(*) FROM play_events").fetchone()[0]
    finally:
        ro.close()
    print("== %s (%d rows)" % (os.path.basename(db), before_rows))
    if not apply:
        print("   dry run: nothing written. Planned (counts need the columns, so computed on an in-memory copy)")
        mem = sqlite3.connect(":memory:")
        src = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(db).replace("\\", "/"), uri=True, timeout=30)
        try:
            src.backup(mem)
        finally:
            src.close()
        return _run(mem, now, null_fake_weather, commit=False)
    bak = backup(db)
    print("   backup: %s" % bak)
    conn = sqlite3.connect(db, timeout=30, isolation_level=None)
    try:
        conn.execute("PRAGMA busy_timeout=30000")
        res = _run(conn, now, null_fake_weather, commit=True)
        after = conn.execute("SELECT COUNT(*) FROM play_events").fetchone()[0]
        if after < before_rows:
            raise SystemExit("row count dropped (%d -> %d): restore %s" % (before_rows, after, bak))
        return res
    finally:
        conn.close()


def _run(conn, now, null_fake_weather, commit):
    try:
        conn.execute("BEGIN IMMEDIATE")
        have = {r[1] for r in conn.execute("PRAGMA table_info(play_events)")}
        for col in ("origin", "quality"):
            if col not in have:
                conn.execute("ALTER TABLE play_events ADD COLUMN %s TEXT" % col)
        before = _counts(conn)
        changed = {}
        changed["origin_filled"] = conn.execute(ORIGIN_SQL).rowcount
        changed["suspect_burst"] = conn.execute(BURST_SQL).rowcount
        changed["synthetic_time"] = conn.execute(SYNC_SQL).rowcount
        changed["impossible"] = conn.execute(IMPOSSIBLE_SQL, {"future": now + FUTURE_SKEW_S, "min_epoch": MIN_VALID_EPOCH}).rowcount
        if null_fake_weather:
            changed["fake_weather_nulled"] = conn.execute(FAKE_WEATHER_SQL).rowcount
        after = _counts(conn)
        for k, v in changed.items():
            print("   %-22s %d" % (k, v))
        print("   quality before %s -> after %s" % (before, after))
        if commit:
            conn.execute("COMMIT")
        else:
            conn.execute("ROLLBACK")
        return changed
    except BaseException:
        try:
            conn.execute("ROLLBACK")
        except sqlite3.Error:
            pass
        raise


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", action="append", default=[])
    ap.add_argument("--dir")
    ap.add_argument("--apply", action="store_true", help="write (default: dry run)")
    ap.add_argument("--null-fake-weather", action="store_true")
    args = ap.parse_args(argv)
    paths = list(args.db)
    if args.dir:
        paths += sorted(glob.glob(os.path.join(args.dir, "*_listening_log.db")))
    if not paths:
        ap.error("give --db FILE or --dir FOLDER")
    for p in paths:
        process(p, args.apply, args.null_fake_weather)
    if not args.apply:
        print("\nDry run only. Re-run with --apply to write (a backup is made first).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
