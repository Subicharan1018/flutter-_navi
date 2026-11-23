#!/usr/bin/env python3
"""Scores the hybrid's shadow rankings. Read-only: run it on a COPY of the listening logs.

    python3 shadow_report.py --dir /path/to/COPIES/of/listening_logs --owner admin
    python3 shadow_report.py --db admin_listening_log.db --json

Two sources, written by the hybrid-shadow-v1 server package:

  hybrid_shadow_plays   one row per kept next-song play, ranked BEFORE the state learned the play:
                        the rank v3, the blend and the hybrid gave the song really played.
                        THIS decides the flip (docs/hybrid-shadow-spec.md): HR@10 = rank <= 10.
  hybrid_shadow         one row per /next request: the hybrid's top 20 beside the ids served.
                        Informational (latency, structure); the listener heard v3's order, which
                        favours v3, so it is not used for the decision.

Intervals: 95 % cluster bootstrap over sessions (1,000 resamples, fixed seed), paired.
Groups: owner / others. The flip is judged on the owner only (spec item 5).

The flip criterion is the spec's (docs/hybrid-shadow-spec.md, "Flip criterion"), in CRITERIA:
  1. first look at >= 400 scored owner next-song plays in >= 60 sessions: turn on when the lower
     95 % bound of (hybrid - v3) HR@10 is above +5 points
  2. not passed: look again at >= 1,200 plays; still not: keep v3 and stop
  3. required either way: errors < 1 % of rows, p95 extra latency <= 10 ms per ranking, at least
     60 % of played songs inside the top 100, no row with a NaN / missing-column error
  4. "hybrid or plain blend?" is separate: keep the model only if (hybrid - blend) has a lower
     bound above 0 at >= 1,200 plays; otherwise serve the blend
"""
import argparse
import glob
import json
import os
import re
import sqlite3
import sys

import numpy as np

KEPT_RATIO = 0.5
BAD_QUALITY = ("suspect_burst", "synthetic_time", "impossible", "clock_clamped")
BOOTSTRAP = 1000
SEED = 7

CRITERIA = {
    "first_look_plays": 400, "min_sessions": 60, "second_look_plays": 1200,
    "delta_vs_v3_lower_bound_gt": 0.05,       # +5 points
    "delta_vs_blend_lower_bound_gt": 0.0,
    "max_error_rate": 0.01, "max_p95_extra_ms": 10.0, "min_in_top100": 0.60,
}
NAN_ERROR = re.compile(r"nan|column|keyerror|indexerror", re.I)


def connect_ro(path):
    conn = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn


def _has(conn, table):
    return conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone() is not None


def load_plays(path):
    """(rows, stats) from hybrid_shadow_plays of one database."""
    conn = connect_ro(path)
    stats = {"rows": 0, "errors": 0, "nan_errors": 0, "extra_ms": [], "in_top": 0, "scored": 0}
    try:
        if not _has(conn, "hybrid_shadow_plays"):
            return [], stats
        out = []
        for r in conn.execute("SELECT * FROM hybrid_shadow_plays ORDER BY id"):
            stats["rows"] += 1
            if r["status"] != "ok":
                stats["errors"] += 1
                stats["nan_errors"] += int(bool(NAN_ERROR.search(r["error"] or "")))
                continue
            stats["scored"] += 1
            stats["in_top"] += int(bool(r["in_top100"]))
            if r["extra_ms"] is not None:
                stats["extra_ms"].append(r["extra_ms"])
            out.append({"user": r["user"], "session": "%s|%s" % (r["user"], r["session_id"]),
                        "v3": int(r["rank_v3"] <= 10), "blend": int(r["rank_blend"] <= 10),
                        "hyb": int(r["rank_hybrid"] <= 10)})
        return out, stats
    finally:
        conn.close()


def load_requests(path, max_gap_s):
    """Informational: per /next request, the hybrid's top 10 vs the served top 10 against the next kept play."""
    conn = connect_ro(path)
    try:
        if not _has(conn, "hybrid_shadow") or not _has(conn, "play_events"):
            return []
        cols = {r[1] for r in conn.execute("PRAGMA table_info(play_events)")}
        qual = ("AND COALESCE(quality,'') NOT IN (%s)" % ",".join("'%s'" % q for q in BAD_QUALITY)) if "quality" in cols else ""
        by_session = {}
        for p in conn.execute("SELECT file_path, session_id, played_at FROM play_events WHERE listen_ratio >= ? %s "
                              "AND file_path IS NOT NULL ORDER BY played_at" % qual, (KEPT_RATIO,)):
            by_session.setdefault(p["session_id"] or "", []).append((p["played_at"], p["file_path"]))
        out = []
        for r in conn.execute("SELECT * FROM hybrid_shadow WHERE status = 'ok' ORDER BY id"):
            target = next((song for t, song in by_session.get(r["session_id"] or "", ())
                           if t >= r["created_at"] and t - r["created_at"] <= max_gap_s), None)
            if target is None:
                continue
            out.append({"user": r["user"], "kind": r["position_kind"], "session": "%s|%s" % (r["user"], r["session_id"]),
                        "hyb": int(target in json.loads(r["top_ids"] or "[]")[:10]),
                        "srv": int(target in json.loads(r["served_ids"] or "[]")[:10])})
        return out
    finally:
        conn.close()


def cluster_bootstrap(rows, key, n=BOOTSTRAP, seed=SEED):
    """(mean, lo, hi) of rows' `key`, resampling whole sessions; `key` may be a callable."""
    f = key if callable(key) else (lambda r: r[key])
    by = {}
    for r in rows:
        by.setdefault(r["session"], []).append(f(r))
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
    return {"n": len(rows), "sessions": len({r["session"] for r in rows}),
            "hr10": {m: cluster_bootstrap(rows, m) for m in ("v3", "blend", "hyb")},
            "hyb_minus_v3": cluster_bootstrap(rows, lambda r: r["hyb"] - r["v3"]),
            "hyb_minus_blend": cluster_bootstrap(rows, lambda r: r["hyb"] - r["blend"])}


def _pct(values, q):
    return float(np.percentile(values, q)) if values else None


def evaluate(paths, owner="admin", max_gap_min=120):
    rows, st, reqs = [], {"rows": 0, "errors": 0, "nan_errors": 0, "extra_ms": [], "in_top": 0, "scored": 0}, []
    for p in paths:
        r, s = load_plays(p)
        rows += r
        for k in ("rows", "errors", "nan_errors", "in_top", "scored"):
            st[k] += s[k]
        st["extra_ms"] += s["extra_ms"]
        reqs += load_requests(p, max_gap_min * 60)
    mine = [r for r in rows if r["user"] == owner]
    others = [r for r in rows if r["user"] != owner]
    rep = {"owner": owner, "play_rows": st["rows"], "error_rows": st["errors"], "nan_error_rows": st["nan_errors"],
           "in_top100_share": (st["in_top"] / st["scored"]) if st["scored"] else None,
           "extra_ms": {"p50": _pct(st["extra_ms"], 50), "p95": _pct(st["extra_ms"], 95),
                        "max": max(st["extra_ms"], default=None)},
           "plays": {"owner": summarise(mine), "others": summarise(others)}, "requests": {}}
    for who, sel in (("owner", [r for r in reqs if r["user"] == owner]), ("others", [r for r in reqs if r["user"] != owner])):
        for kind in ("opener", "next"):
            rr = [r for r in sel if r["kind"] == kind]
            rep["requests"]["%s/%s" % (who, kind)] = None if not rr else {
                "n": len(rr), "sessions": len({r["session"] for r in rr}),
                "hybrid": cluster_bootstrap(rr, "hyb"), "served": cluster_bootstrap(rr, "srv"),
                "delta": cluster_bootstrap(rr, lambda r: r["hyb"] - r["srv"])}
    return rep


def decide(report, c=None):
    """(checks, decision). verdict: ON / WAIT / KEEP_V3; serve: hybrid / blend / undecided / n/a."""
    c = c or CRITERIA
    g = report["plays"]["owner"]
    n = g["n"] if g else 0
    sessions = g["sessions"] if g else 0
    lo_v3 = g["hyb_minus_v3"][1] if g else None
    lo_bl = g["hyb_minus_blend"][1] if g else None
    err = report["error_rows"] / report["play_rows"] if report["play_rows"] else 1.0
    p95 = report["extra_ms"]["p95"]
    share = report["in_top100_share"]
    checks = [
        ("owner next-song plays scored >= %d" % c["first_look_plays"], n >= c["first_look_plays"], "n=%d" % n),
        ("sessions >= %d" % c["min_sessions"], sessions >= c["min_sessions"], "sessions=%d" % sessions),
        ("hybrid - v3 HR@10, lower 95%% bound > +%.0f pts" % (100 * c["delta_vs_v3_lower_bound_gt"]),
         lo_v3 is not None and lo_v3 > c["delta_vs_v3_lower_bound_gt"],
         "lower bound=%s" % ("n/a" if lo_v3 is None else "%+.1f pts" % (100 * lo_v3))),
        ("errors < %.0f%% of rows" % (100 * c["max_error_rate"]), err < c["max_error_rate"], "%.2f%%" % (100 * err)),
        ("p95 extra latency <= %.0f ms" % c["max_p95_extra_ms"], p95 is not None and p95 <= c["max_p95_extra_ms"],
         "p95=%s" % ("n/a" if p95 is None else "%.2f ms" % p95)),
        ("played song inside the top 100 for >= %.0f%%" % (100 * c["min_in_top100"]),
         share is not None and share >= c["min_in_top100"], "n/a" if share is None else "%.0f%%" % (100 * share)),
        ("no NaN / missing-column errors", report["nan_error_rows"] == 0, "%d rows" % report["nan_error_rows"]),
    ]
    if all(p for _, p, _ in checks):
        verdict = "ON"
    elif n < c["second_look_plays"]:
        verdict = "WAIT"            # not at the first bar yet, or the first look failed: the second look is at 1,200
    else:
        verdict = "KEEP_V3"
    if verdict != "ON":
        serve = "n/a"
    elif n < c["second_look_plays"]:
        serve = "undecided (needs %d plays)" % c["second_look_plays"]
    else:
        serve = "hybrid" if (lo_bl is not None and lo_bl > c["delta_vs_blend_lower_bound_gt"]) else "blend"
    return checks, {"verdict": verdict, "serve": serve}


def _fmt(t):
    return "n/a" if not t else "%.1f%% [%.1f, %.1f]" % (100 * t[0], 100 * t[1], 100 * t[2])


def _fmt_d(t):
    return "n/a" if not t else "%+.1f pts [%+.1f, %+.1f]" % (100 * t[0], 100 * t[1], 100 * t[2])


def render(report):
    out = ["Hybrid shadow report  (owner = %s)" % report["owner"], ""]
    share = report["in_top100_share"]
    out.append("per-play rows: %d   errors: %d   NaN/column errors: %d   played song in top 100: %s" % (
        report["play_rows"], report["error_rows"], report["nan_error_rows"],
        "n/a" if share is None else "%.0f%%" % (100 * share)))
    e = report["extra_ms"]
    out.append("hybrid extra latency per ranking, ms: p50 %s  p95 %s  max %s" % tuple(
        "n/a" if v is None else "%.2f" % v for v in (e["p50"], e["p95"], e["max"])))
    out += ["", "Kept next-song plays (ranked before the state learned them)"]
    for who in ("owner", "others"):
        g = report["plays"][who]
        if g is None:
            out.append("  %-7s none yet" % who)
            continue
        out.append("  %-7s n=%d sessions=%d   HR@10 v3 %s | blend %s | hybrid %s" % (
            who, g["n"], g["sessions"], _fmt(g["hr10"]["v3"]), _fmt(g["hr10"]["blend"]), _fmt(g["hr10"]["hyb"])))
        out.append("          hybrid - v3 %s     hybrid - blend %s%s" % (
            _fmt_d(g["hyb_minus_v3"]), _fmt_d(g["hyb_minus_blend"]),
            "" if who == "owner" else "   (not used for the decision)"))
    out += ["", "Per /next request, hybrid top 10 vs what was served (informational: the listener heard v3's order)"]
    for name, g in report["requests"].items():
        out.append("  %-14s %s" % (name, "none yet" if g is None else "n=%d sessions=%d  hybrid %s  served %s  diff %s" % (
            g["n"], g["sessions"], _fmt(g["hybrid"]), _fmt(g["served"]), _fmt_d(g["delta"]))))
    checks, d = decide(report)
    out += ["", "Flip criterion (docs/hybrid-shadow-spec.md):"]
    for name, passed, detail in checks:
        out.append("  [%s] %s  (%s)" % ("PASS" if passed else "FAIL", name, detail))
    msg = {"ON": "FLIP CRITERION MET: HYBRID_ORDER=on is justified for next-song positions (serve: %s)" % d["serve"],
           "WAIT": "FLIP CRITERION NOT MET YET: keep collecting (looks at 400 and at 1,200 owner plays)",
           "KEEP_V3": "FLIP CRITERION NOT MET at 1,200 plays: keep v3 and stop"}[d["verdict"]]
    out += ["", msg]
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
    checks, d = decide(report)
    if a.json:
        report["criteria"] = [{"name": n, "pass": p, "detail": x} for n, p, x in checks]
        report["decision"] = d
        print(json.dumps(report, indent=2, default=str))
    else:
        print(render(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
