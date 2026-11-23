#!/usr/bin/env python3
"""Scores the hybrid's shadow rankings against what was really played. Read-only.

    python3 shadow_report.py --dir /path/to/COPIES/of/listening_logs --owner admin
    python3 shadow_report.py --db admin_listening_log.db --json

Run it on a COPY of the logs (it opens every file with SQLite's read-only mode and writes
nothing, but a copy keeps the live WAL files out of it).

For every `hybrid_shadow` row with status 'ok' (the server recorded the hybrid's top ranking
for a /next request, next to the `served_ids` it really returned), the target is the first
KEPT play (listen_ratio >= 0.5, `quality` empty, a finished play of this session) that
started at or after the request. A row is scored when such a play exists within
`--max-gap-min` minutes. HR@10: the target is among the first 10 song ids of the ranking.
Rows are scored the same way for the hybrid and for what was served, on the same target.

Intervals: 95 % cluster bootstrap over sessions (1,000 resamples, fixed seed), paired.
Groups: owner / others  x  opener / next.

The flip criterion: see CRITERIA below. It is the research session's rule once
docs/hybrid-shadow-spec.md exists; until then these are the numbers written in
docs/smart-shuffle-research-opus.md (at least 40 queues and fewer skips than the served order)
plus a paired HR@10 interval that excludes zero. Change CRITERIA to match the spec, nothing
else needs to move.
"""
import argparse
import glob
import json
import os
import sqlite3
import sys

import numpy as np

KEPT_RATIO = 0.5
BAD_QUALITY = ("suspect_burst", "synthetic_time", "impossible", "clock_clamped")
BOOTSTRAP = 1000
SEED = 7

# Provisional flip criterion (owner, next-song positions). Edit to match docs/hybrid-shadow-spec.md.
CRITERIA = {
    "group": ("owner", "next"),
    "min_scored_rows": 150,       # next-song requests that could be scored
    "min_sessions": 40,           # the "at least 40 queues" bar of ai_order_eval / the research doc
    "delta_hr10_lower_bound_gt": 0.0,   # paired hybrid - served HR@10, lower end of the 95 % interval
    "max_error_rate": 0.05,       # rows with status 'error' / all rows
    "max_p90_latency_ms": 1500,
}


def connect_ro(path):
    conn = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


def _has(conn, table):
    return conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone() is not None


def load_user(path, max_gap_s):
    """(scored rows, row stats) for one database."""
    conn = connect_ro(path)
    try:
        if not _has(conn, "hybrid_shadow") or not _has(conn, "play_events"):
            return [], {"rows": 0, "errors": 0, "error_reasons": {}, "latencies": [], "models": {}}
        cols = {r[1] for r in conn.execute("PRAGMA table_info(play_events)")}
        qual = "AND COALESCE(quality,'') NOT IN (%s)" % ",".join("'%s'" % q for q in BAD_QUALITY) if "quality" in cols else ""
        plays = conn.execute(
            "SELECT file_path, session_id, played_at FROM play_events WHERE listen_ratio >= ? %s "
            "AND file_path IS NOT NULL ORDER BY played_at" % qual, (KEPT_RATIO,)).fetchall()
        by_session = {}
        for p in plays:
            by_session.setdefault(p["session_id"] or "", []).append((p["played_at"], p["file_path"]))
        stats = {"rows": 0, "errors": 0, "error_reasons": {}, "latencies": [], "models": {}}
        out = []
        for r in conn.execute("SELECT * FROM hybrid_shadow ORDER BY id"):
            stats["rows"] += 1
            if r["status"] != "ok":
                stats["errors"] += 1
                reason = (r["error"] or "unknown").split(":")[0]
                stats["error_reasons"][reason] = stats["error_reasons"].get(reason, 0) + 1
                continue
            if r["latency_ms"] is not None:
                stats["latencies"].append(r["latency_ms"])
            stats["models"][r["model_version"]] = stats["models"].get(r["model_version"], 0) + 1
            target = None
            for t, song in by_session.get(r["session_id"] or "", ()):
                if t >= r["created_at"] and t - r["created_at"] <= max_gap_s:
                    target = song
                    break
            if target is None:
                continue
            top = json.loads(r["top_ids"] or "[]")[:10]
            served = json.loads(r["served_ids"] or "[]")[:10]
            out.append({"user": r["user"], "kind": r["position_kind"], "session": "%s|%s" % (r["user"], r["session_id"]),
                        "hyb": int(target in top), "srv": int(target in served), "model": r["model_version"]})
        return out, stats
    finally:
        conn.close()


def cluster_bootstrap(rows, key="delta", n=BOOTSTRAP, seed=SEED):
    """(mean, lo, hi) of the per-row value in `key`, resampling whole sessions."""
    by = {}
    for r in rows:
        by.setdefault(r["session"], []).append(r[key])
    sums = np.array([sum(v) for v in by.values()], float)
    cnts = np.array([len(v) for v in by.values()], float)
    if len(sums) == 0:
        return None
    rng = np.random.default_rng(seed)
    idx = rng.integers(0, len(sums), size=(n, len(sums)))
    est = sums[idx].sum(axis=1) / cnts[idx].sum(axis=1)
    return float(sums.sum() / cnts.sum()), float(np.percentile(est, 2.5)), float(np.percentile(est, 97.5))


def summarise(rows):
    if not rows:
        return None
    for r in rows:
        r["delta"] = r["hyb"] - r["srv"]
    hyb = cluster_bootstrap(rows, "hyb")
    srv = cluster_bootstrap(rows, "srv")
    dlt = cluster_bootstrap(rows, "delta")
    return {"n": len(rows), "sessions": len({r["session"] for r in rows}),
            "hybrid_hr10": hyb, "served_hr10": srv, "delta": dlt}


def percentile(values, q):
    return float(np.percentile(values, q)) if values else None


def evaluate(paths, owner="admin", max_gap_min=120):
    rows, stats = [], {"rows": 0, "errors": 0, "error_reasons": {}, "latencies": [], "models": {}}
    for p in paths:
        r, s = load_user(p, max_gap_min * 60)
        rows += r
        stats["rows"] += s["rows"]
        stats["errors"] += s["errors"]
        stats["latencies"] += s["latencies"]
        for k, v in s["error_reasons"].items():
            stats["error_reasons"][k] = stats["error_reasons"].get(k, 0) + v
        for k, v in s["models"].items():
            stats["models"][k] = stats["models"].get(k, 0) + v
    groups = {}
    for who in ("owner", "others"):
        for kind in ("opener", "next"):
            sel = [r for r in rows if (r["user"] == owner) == (who == "owner") and r["kind"] == kind]
            groups["%s/%s" % (who, kind)] = summarise(sel)
    return {"owner": owner, "shadow_rows": stats["rows"], "error_rows": stats["errors"],
            "error_reasons": stats["error_reasons"], "latency_ms": {"p50": percentile(stats["latencies"], 50),
                                                                     "p90": percentile(stats["latencies"], 90),
                                                                     "max": max(stats["latencies"], default=None)},
            "models": stats["models"], "groups": groups}


def check_criteria(report, criteria=None):
    """[(name, passed, detail)] and the overall verdict."""
    c = criteria or CRITERIA
    g = report["groups"].get("%s/%s" % c["group"])
    checks = []
    n = g["n"] if g else 0
    sess = g["sessions"] if g else 0
    checks.append(("scored %s rows >= %d" % ("/".join(c["group"]), c["min_scored_rows"]), n >= c["min_scored_rows"], "n=%d" % n))
    checks.append(("sessions >= %d" % c["min_sessions"], sess >= c["min_sessions"], "sessions=%d" % sess))
    lo = g["delta"][1] if g and g["delta"] else None
    checks.append(("paired HR@10 delta, lower 95%% bound > %.3f" % c["delta_hr10_lower_bound_gt"],
                   lo is not None and lo > c["delta_hr10_lower_bound_gt"],
                   "lower bound=%s" % ("n/a" if lo is None else "%+.1f pts" % (100 * lo))))
    err = report["error_rows"] / report["shadow_rows"] if report["shadow_rows"] else 1.0
    checks.append(("error rate <= %.0f%%" % (100 * c["max_error_rate"]), err <= c["max_error_rate"], "%.1f%%" % (100 * err)))
    p90 = report["latency_ms"]["p90"]
    checks.append(("p90 latency <= %d ms" % c["max_p90_latency_ms"], p90 is not None and p90 <= c["max_p90_latency_ms"],
                   "p90=%s" % ("n/a" if p90 is None else "%d ms" % p90)))
    return checks, all(ok for _, ok, _ in checks)


def _pct(t):
    return "n/a" if not t else "%.1f%% [%.1f, %.1f]" % (100 * t[0], 100 * t[1], 100 * t[2])


def render(report):
    out = ["Hybrid shadow report  (owner = %s)" % report["owner"], ""]
    out.append("shadow rows: %d   errors: %d %s" % (report["shadow_rows"], report["error_rows"], report["error_reasons"] or ""))
    lat = report["latency_ms"]
    out.append("latency ms: p50 %s  p90 %s  max %s" % (lat["p50"], lat["p90"], lat["max"]))
    out.append("models: %s" % (report["models"] or "none"))
    out.append("")
    out.append("%-16s %6s %9s  %-22s %-22s %s" % ("group", "n", "sessions", "hybrid HR@10", "served HR@10", "hybrid - served"))
    for name, g in report["groups"].items():
        if g is None:
            out.append("%-16s %6d" % (name, 0))
            continue
        d = g["delta"]
        out.append("%-16s %6d %9d  %-22s %-22s %s" % (
            name, g["n"], g["sessions"], _pct(g["hybrid_hr10"]), _pct(g["served_hr10"]),
            "n/a" if not d else "%+.1f pts [%+.1f, %+.1f]" % (100 * d[0], 100 * d[1], 100 * d[2])))
    checks, ok = check_criteria(report)
    out += ["", "Flip criterion (provisional, see CRITERIA in this file):"]
    for name, passed, detail in checks:
        out.append("  [%s] %s  (%s)" % ("PASS" if passed else "FAIL", name, detail))
    out.append("")
    out.append("FLIP CRITERION %s" % ("MET" if ok else "NOT MET"))
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", action="append", default=[])
    ap.add_argument("--dir")
    ap.add_argument("--owner", default="admin", help="user name of the owner (default admin)")
    ap.add_argument("--max-gap-min", type=int, default=120)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    paths = list(a.db)
    if a.dir:
        paths += sorted(glob.glob(os.path.join(a.dir, "*_listening_log.db")))
    if not paths:
        ap.error("give --db FILE or --dir FOLDER")
    report = evaluate(paths, a.owner, a.max_gap_min)
    checks, ok = check_criteria(report)
    if a.json:
        report["criteria"] = [{"name": n, "pass": p, "detail": d} for n, p, d in checks]
        report["flip_met"] = ok
        print(json.dumps(report, indent=2, default=str))
    else:
        print(render(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
