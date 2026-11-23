"""python -m pytest tool/shuffle_eval/tests -q"""
import json
import os
import sqlite3
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import shadow_report as sr  # noqa: E402

PLAYS = """CREATE TABLE play_events (id INTEGER PRIMARY KEY, track_title TEXT, file_path TEXT, played_at INTEGER,
listen_ratio REAL, session_id TEXT, quality TEXT)"""
SHADOW = """CREATE TABLE hybrid_shadow (id INTEGER PRIMARY KEY, created_at INTEGER, served_id TEXT, user TEXT,
session_id TEXT, position_kind TEXT, mode TEXT, model_version TEXT, blend_version TEXT, status TEXT, error TEXT,
top_ids TEXT, top_scores TEXT, n_allowed INTEGER, served_ids TEXT, latency_ms INTEGER, queue_wait_ms INTEGER)"""


def make(path, user, cases, with_quality=True):
    """cases: list of (session, kind, hybrid_hit, served_hit, status)"""
    c = sqlite3.connect(path)
    c.execute(PLAYS if with_quality else PLAYS.replace(", quality TEXT", ""))
    c.execute(SHADOW)
    t = 1000
    for i, (sess, kind, hh, sh, status) in enumerate(cases):
        t += 100
        target = "song%d" % i
        top = [target] + ["x%d" % k for k in range(19)] if hh else ["a%d" % k for k in range(20)]
        srv = [target] + ["y%d" % k for k in range(19)] if sh else ["b%d" % k for k in range(20)]
        c.execute("INSERT INTO hybrid_shadow(created_at, served_id, user, session_id, position_kind, mode, model_version,"
                  "status, error, top_ids, served_ids, latency_ms) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                  (t, "sv%d" % i, user, sess, kind, "shadow", "m1", status, None if status == "ok" else "budget: slow",
                   json.dumps(top), json.dumps(srv), 40))
        cols = "(track_title, file_path, played_at, listen_ratio, session_id%s)" % (", quality" if with_quality else "")
        c.execute("INSERT INTO play_events%s VALUES (?,?,?,?,?%s)" % (cols, ",?" if with_quality else ""),
                  ("t", target, t + 10, 1.0, sess) + ((None,) if with_quality else ()))
    c.commit()
    c.close()


def many(n_sessions, per, hh, sh, kind="next"):
    return [("s%d" % (i // per), kind, hh(i), sh(i), "ok") for i in range(n_sessions * per)]


def test_hits_are_scored_per_group_and_the_delta_is_paired(tmp_path):
    p = str(tmp_path / "admin_listening_log.db")
    make(p, "admin", many(60, 3, lambda i: i % 2 == 0, lambda i: i % 4 == 0))
    q = str(tmp_path / "bob_listening_log.db")
    make(q, "bob", many(10, 2, lambda i: True, lambda i: False, kind="opener"))
    rep = sr.evaluate([p, q], owner="admin")
    g = rep["groups"]["owner/next"]
    assert g["n"] == 180 and g["sessions"] == 60
    assert g["hybrid_hr10"][0] == pytest.approx(0.5) and g["served_hr10"][0] == pytest.approx(0.25)
    assert g["delta"][0] == pytest.approx(0.25) and g["delta"][1] < 0.25 < g["delta"][2]
    o = rep["groups"]["others/opener"]
    assert o["n"] == 20 and o["delta"][0] == pytest.approx(1.0)
    assert rep["groups"]["owner/opener"] is None and rep["groups"]["others/next"] is None


def test_the_bootstrap_is_reproducible(tmp_path):
    p = str(tmp_path / "admin_listening_log.db")
    make(p, "admin", many(30, 2, lambda i: i % 3 == 0, lambda i: i % 5 == 0))
    a = sr.evaluate([p])["groups"]["owner/next"]["delta"]
    b = sr.evaluate([p])["groups"]["owner/next"]["delta"]
    assert a == b


def test_criterion_met_and_not_met(tmp_path):
    good = str(tmp_path / "admin_listening_log.db")
    make(good, "admin", many(60, 3, lambda i: True, lambda i: i % 3 == 0))
    checks, ok = sr.check_criteria(sr.evaluate([good]))
    assert ok and all(p for _, p, _ in checks)
    assert "FLIP CRITERION MET" in sr.render(sr.evaluate([good]))
    bad = str(tmp_path / "x" / "admin_listening_log.db")
    os.makedirs(os.path.dirname(bad))
    make(bad, "admin", many(60, 3, lambda i: i % 3 == 0, lambda i: i % 3 == 0))   # no better than served
    checks, ok = sr.check_criteria(sr.evaluate([bad]))
    assert not ok and not dict((n, p) for n, p, _ in checks)["paired HR@10 delta, lower 95% bound > 0.000"]
    few = str(tmp_path / "y" / "admin_listening_log.db")
    os.makedirs(os.path.dirname(few))
    make(few, "admin", many(5, 2, lambda i: True, lambda i: False))
    assert sr.check_criteria(sr.evaluate([few]))[1] is False


def test_error_rows_are_counted_not_scored(tmp_path):
    p = str(tmp_path / "admin_listening_log.db")
    make(p, "admin", [("s1", "next", True, False, "ok"), ("s1", "next", True, False, "error")] * 3)
    rep = sr.evaluate([p])
    assert rep["error_rows"] == 3 and rep["error_reasons"] == {"budget": 3} and rep["groups"]["owner/next"]["n"] == 3


def test_skipped_and_flagged_plays_are_not_targets(tmp_path):
    p = str(tmp_path / "admin_listening_log.db")
    make(p, "admin", [("s1", "next", True, True, "ok")])
    c = sqlite3.connect(p)
    c.execute("UPDATE play_events SET listen_ratio = 0.1")
    c.commit()
    c.close()
    assert sr.evaluate([p])["groups"]["owner/next"] is None
    c = sqlite3.connect(p)
    c.execute("UPDATE play_events SET listen_ratio = 1.0, quality = 'suspect_burst'")
    c.commit()
    c.close()
    assert sr.evaluate([p])["groups"]["owner/next"] is None


def test_old_logs_without_the_new_tables_or_columns_are_tolerated(tmp_path):
    p = str(tmp_path / "old_listening_log.db")
    c = sqlite3.connect(p)
    c.execute("CREATE TABLE play_events (id INTEGER PRIMARY KEY, track_title TEXT)")
    c.commit()
    c.close()
    q = str(tmp_path / "noquality_listening_log.db")
    make(q, "u", [("s", "next", True, False, "ok")], with_quality=False)
    rep = sr.evaluate([p, q])
    assert rep["groups"]["others/next"]["n"] == 1


def test_it_never_writes(tmp_path):
    p = str(tmp_path / "admin_listening_log.db")
    make(p, "admin", many(5, 2, lambda i: True, lambda i: False))
    before = open(p, "rb").read()
    sr.evaluate([p])
    sr.main(["--db", p])
    assert open(p, "rb").read() == before
    assert not [f for f in os.listdir(tmp_path) if f.endswith(("-wal", "-shm", "-journal"))]
