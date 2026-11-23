#!/usr/bin/env python3
"""Read-only data-quality report for NaviVibe listening logs (`<user>_listening_log.db`).

Opens every database with SQLite's read-only mode and never writes. Point it at a COPY of a
log when you can (`cp` the .db next to its -wal/-shm, or use `sqlite3 x.db ".backup copy.db"`
on the server); a read-only open of a live WAL database is also safe, it just cannot
checkpoint.

    python3 data_quality.py --db admin_listening_log.db
    python3 data_quality.py --dir /DATA/AppData/navivibe/listening_logs
    python3 data_quality.py --dir ... --json > report.json

What it reports, per database and overall:
  rows by origin           app / navidrome_sync / import (+ apple_plays, legacy_plays sizes)
  duplicates               the same song at the same second; clusters of rows sharing one timestamp
  fake burst rows          "finished naturally at 0 %" (no song ends naturally at 0 %), as a share of app rows
  impossible values        ratio outside 0..1, seconds_played > duration, negative numbers,
                           timestamps in the future or before 2020, hour that disagrees with the time
  fake weather             800 / 25.0 on every old app row (the old app sent constants)
  missing fields           % NULL per column, split by client_version ("(none)" = old app)
  refused events           the server's rejected_counts table, if the play-events-v2 package ran
"""
import argparse
import glob
import json
import os
import sqlite3
import sys
import time
from collections import OrderedDict

MIN_VALID_EPOCH = 1577836800  # 2020-01-01
FUTURE_SKEW_S = 300
FIELDS = ("file_path", "genre_bucket", "composer", "duration_s", "session_id", "listen_ratio",
          "end_reason", "play_id", "seconds_played", "tz_offset_min", "local_hour", "play_source",
          "slot", "score", "served_by", "holdout", "weather_code")


def connect_ro(path):
    uri = "file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/")
    conn = sqlite3.connect(uri, uri=True, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


def _cols(conn, table):
    return [r[1] for r in conn.execute("PRAGMA table_info(%s)" % table)]


def _has_table(conn, name):
    return conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)).fetchone() is not None


def _pct(n, d):
    return round(100.0 * n / d, 2) if d else 0.0


def analyse_db(path, now=None):
    now = int(now or time.time())
    conn = connect_ro(path)
    try:
        rep = OrderedDict(db=os.path.basename(path))
        if not _has_table(conn, "play_events"):
            rep["error"] = "no play_events table"
            return rep
        cols = set(_cols(conn, "play_events"))
        q = lambda sql, *a: conn.execute(sql, a).fetchone()[0]  # noqa: E731

        total = q("SELECT COUNT(*) FROM play_events")
        rep["rows"] = total
        origin_expr = ("COALESCE(origin, CASE WHEN session_id='navidrome_sync' THEN 'navidrome_sync' "
                       "WHEN session_id LIKE 'import:%' THEN 'import' ELSE 'app' END)") if "origin" in cols else \
            ("CASE WHEN session_id='navidrome_sync' THEN 'navidrome_sync' "
             "WHEN session_id LIKE 'import:%' THEN 'import' ELSE 'app' END")
        by_origin = {r[0]: r[1] for r in conn.execute(
            "SELECT %s AS o, COUNT(*) FROM play_events GROUP BY o" % origin_expr)}
        rep["by_origin"] = by_origin
        app_rows = by_origin.get("app", 0)
        rep["history_tables"] = {t: q("SELECT COUNT(*) FROM %s" % t)
                                 for t in ("apple_plays", "legacy_plays") if _has_table(conn, t)}
        if not total:
            return rep
        rep["time_range"] = [q("SELECT MIN(played_at) FROM play_events"), q("SELECT MAX(played_at) FROM play_events")]

        # duplicates
        dup_same_second = q("SELECT COALESCE(SUM(c - 1), 0) FROM (SELECT COUNT(*) c FROM play_events "
                            "GROUP BY track_title, played_at HAVING c > 1)")
        cluster_rows = q("SELECT COALESCE(SUM(c), 0) FROM (SELECT COUNT(*) c FROM play_events "
                         "WHERE %s = 'app' GROUP BY played_at HAVING c >= 3)" % origin_expr)
        sync_same_ts = q("SELECT COALESCE(SUM(c - 1), 0) FROM (SELECT COUNT(*) c FROM play_events "
                         "WHERE %s = 'navidrome_sync' GROUP BY track_title, played_at HAVING c > 1)" % origin_expr)
        rep["duplicates"] = {
            "same_song_same_second_extra_rows": dup_same_second,
            "of_which_navidrome_sync_invented_timestamps": sync_same_ts,
            "app_rows_in_clusters_of_3plus_sharing_one_second": cluster_rows,
        }

        # fake bursts
        burst = q("SELECT COUNT(*) FROM play_events WHERE %s = 'app' AND LOWER(COALESCE(end_reason,'')) IN "
                  "('natural','trackdone') AND listen_ratio = 0" % origin_expr)
        flagged = q("SELECT COUNT(*) FROM play_events WHERE quality = 'suspect_burst'") if "quality" in cols else 0
        rep["fake_burst"] = {"rows": burst, "share_of_app_rows_pct": _pct(burst, app_rows),
                             "already_flagged": flagged}

        # impossible values
        imp = OrderedDict()
        imp["listen_ratio_outside_0_1"] = q("SELECT COUNT(*) FROM play_events WHERE listen_ratio < 0 OR listen_ratio > 1.0001")
        imp["duration_not_positive_or_over_6h"] = q(
            "SELECT COUNT(*) FROM play_events WHERE duration_s IS NOT NULL AND (duration_s < 0 OR duration_s > 21600)")
        imp["played_at_in_future"] = q("SELECT COUNT(*) FROM play_events WHERE played_at > ?", now + FUTURE_SKEW_S)
        imp["played_at_before_2020"] = q("SELECT COUNT(*) FROM play_events WHERE played_at < ?", MIN_VALID_EPOCH)
        imp["hour_outside_0_23"] = q("SELECT COUNT(*) FROM play_events WHERE ist_hour < 0 OR ist_hour > 23")
        imp["hour_disagrees_with_timestamp"] = q(
            "SELECT COUNT(*) FROM play_events WHERE ist_timestamp IS NOT NULL AND ist_hour IS NOT NULL AND "
            "CAST(substr(ist_timestamp, 12, 2) AS INTEGER) != ist_hour")
        imp["negative_session_depth"] = q("SELECT COUNT(*) FROM play_events WHERE session_depth < 0")
        if "seconds_played" in cols:
            imp["seconds_played_negative"] = q("SELECT COUNT(*) FROM play_events WHERE seconds_played < 0")
            imp["seconds_played_over_duration"] = q(
                "SELECT COUNT(*) FROM play_events WHERE seconds_played IS NOT NULL AND duration_s > 0 "
                "AND seconds_played > duration_s * 1.1 + 2")
        imp["listen_ratio_exactly_1_but_skipped"] = q(
            "SELECT COUNT(*) FROM play_events WHERE listen_ratio >= 1.0 AND LOWER(COALESCE(end_reason,'')) = 'fwdbtn' "
            "AND %s = 'app'" % origin_expr)
        rep["impossible_values"] = imp
        rep["impossible_total"] = sum(imp.values())

        # fake weather
        const_w = q("SELECT COUNT(*) FROM play_events WHERE weather_code = 800 AND temperature_c = 25.0 AND %s = 'app'" % origin_expr)
        null_w = q("SELECT COUNT(*) FROM play_events WHERE weather_code IS NULL")
        rep["weather"] = {"constant_800_25_on_app_rows": const_w,
                          "share_of_app_rows_pct": _pct(const_w, app_rows),
                          "null_weather_code": null_w,
                          "null_weather_share_pct": _pct(null_w, total)}

        # missing fields per client version
        ver_expr = "COALESCE(client_version, '(none)')" if "client_version" in cols else "'(none)'"
        miss = OrderedDict()
        versions = [r[0] for r in conn.execute(
            "SELECT %s AS v FROM play_events WHERE %s = 'app' GROUP BY v ORDER BY COUNT(*) DESC" % (ver_expr, origin_expr))]
        for v in versions:
            n = q("SELECT COUNT(*) FROM play_events WHERE %s = 'app' AND %s = ?" % (origin_expr, ver_expr), v)
            row = OrderedDict(rows=n)
            for f in FIELDS:
                if f in cols:
                    nulls = q("SELECT COUNT(*) FROM play_events WHERE %s = 'app' AND %s = ? AND (%s IS NULL OR %s = '')"
                              % (origin_expr, ver_expr, f, f), v)
                    row[f] = _pct(nulls, n)
                else:
                    row[f] = 100.0  # the column does not exist yet = missing everywhere
            miss[v] = row
        rep["missing_pct_by_client_version"] = miss

        # tracked by the play-events-v2 package
        if _has_table(conn, "rejected_counts"):
            rep["server_refused_events"] = {r[0]: r[1] for r in conn.execute(
                "SELECT reason, n FROM rejected_counts ORDER BY n DESC")}
        if "holdout" in cols:
            h = q("SELECT COUNT(*) FROM play_events WHERE holdout = 1")
            known = q("SELECT COUNT(*) FROM play_events WHERE holdout IS NOT NULL")
            rep["holdout"] = {"flagged": h, "rows_with_flag": known, "share_pct": _pct(h, known)}
        rep["integrity_ok"] = conn.execute("PRAGMA quick_check").fetchone()[0] == "ok"
        return rep
    finally:
        conn.close()


def merge(reports):
    """Overall totals across databases."""
    tot = OrderedDict(databases=len(reports), rows=0, app_rows=0, burst_rows=0, impossible=0,
                      const_weather=0, extra_duplicate_rows=0)
    for r in reports:
        tot["rows"] += r.get("rows", 0)
        tot["app_rows"] += r.get("by_origin", {}).get("app", 0)
        tot["burst_rows"] += r.get("fake_burst", {}).get("rows", 0)
        tot["impossible"] += r.get("impossible_total", 0)
        tot["const_weather"] += r.get("weather", {}).get("constant_800_25_on_app_rows", 0)
        tot["extra_duplicate_rows"] += r.get("duplicates", {}).get("same_song_same_second_extra_rows", 0)
    tot["burst_share_of_app_rows_pct"] = _pct(tot["burst_rows"], tot["app_rows"])
    tot["const_weather_share_of_app_rows_pct"] = _pct(tot["const_weather"], tot["app_rows"])
    return tot


def render(reports, total):
    out = []
    w = out.append
    for r in reports:
        w("== %s" % r["db"])
        if "error" in r:
            w("   %s" % r["error"])
            continue
        w("   rows %d   by origin %s   history tables %s" % (r["rows"], dict(r["by_origin"]), r.get("history_tables")))
        if not r["rows"]:
            continue
        d = r["duplicates"]
        w("   duplicates: %d extra rows (same song, same second); %d of them invented by the Navidrome sync; "
          "%d app rows sit in clusters of 3+ sharing one second" % (
              d["same_song_same_second_extra_rows"], d["of_which_navidrome_sync_invented_timestamps"],
              d["app_rows_in_clusters_of_3plus_sharing_one_second"]))
        b = r["fake_burst"]
        w("   fake burst rows (natural end at 0 %%): %d = %.1f %% of app rows (%d already flagged)" % (
            b["rows"], b["share_of_app_rows_pct"], b["already_flagged"]))
        w("   impossible values: %d total %s" % (r["impossible_total"], {k: v for k, v in r["impossible_values"].items() if v}))
        wt = r["weather"]
        w("   weather: %d app rows carry the constant 800 / 25.0 (%.1f %% of app rows); %.1f %% of all rows have no weather" % (
            wt["constant_800_25_on_app_rows"], wt["share_of_app_rows_pct"], wt["null_weather_share_pct"]))
        for v, row in r["missing_pct_by_client_version"].items():
            worst = ", ".join("%s %.0f%%" % (k, x) for k, x in row.items() if k != "rows" and x >= 50)
            w("   client %-10s rows %-6d fields missing >= 50 %%: %s" % (v, row["rows"], worst or "none"))
        if r.get("server_refused_events"):
            w("   server refused: %s" % r["server_refused_events"])
        if "holdout" in r:
            w("   holdout: %s" % r["holdout"])
        if not r.get("integrity_ok", True):
            w("   !! PRAGMA quick_check failed")
    w("")
    w("TOTAL  %s" % dict(total))
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", action="append", default=[], help="a *_listening_log.db file (repeatable)")
    ap.add_argument("--dir", help="a folder of *_listening_log.db files")
    ap.add_argument("--json", action="store_true", help="print JSON instead of text")
    args = ap.parse_args(argv)
    paths = list(args.db)
    if args.dir:
        paths += sorted(glob.glob(os.path.join(args.dir, "*_listening_log.db")))
    if not paths:
        ap.error("give --db FILE or --dir FOLDER")
    reports = []
    for p in paths:
        try:
            reports.append(analyse_db(p))
        except sqlite3.Error as e:
            reports.append(OrderedDict(db=os.path.basename(p), error="cannot read: %s" % e))
    total = merge(reports)
    if args.json:
        print(json.dumps({"databases": reports, "total": total}, indent=2, default=str))
    else:
        print(render(reports, total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
