"""python -m pytest tool/shuffle_eval/tests -q"""
import json
import os
import sqlite3
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import shadow_report as sr  # noqa: E402

PLAYS = """CREATE TABLE hybrid_shadow_plays (id INTEGER PRIMARY KEY, created_at INTEGER, played_at INTEGER, user TEXT,
session_id TEXT, song_id TEXT, depth INTEGER, rank_v3 REAL, rank_blend REAL, rank_hybrid REAL, in_top100 INTEGER,
model_version TEXT, mode TEXT, status TEXT, error TEXT, extra_ms REAL, inline_ms REAL, queue_wait_ms INTEGER)"""
REQ = """CREATE TABLE hybrid_shadow (id INTEGER PRIMARY KEY, created_at INTEGER, served_id TEXT, user TEXT,
session_id TEXT, position_kind TEXT, mode TEXT, model_version TEXT, status TEXT, error TEXT, top_ids TEXT,
top_scores TEXT, n_allowed INTEGER, served_ids TEXT, latency_ms INTEGER, queue_wait_ms INTEGER)"""
PE = "CREATE TABLE play_events (id INTEGER PRIMARY KEY, file_path TEXT, played_at INTEGER, listen_ratio REAL, session_id TEXT, quality TEXT)"


def make(path, user, plays, requests=(), extra_ms=2.0):
    """plays: list of (session, rank_v3, rank_blend, rank_hybrid, status, in_top100, error)"""
    c = sqlite3.connect(path)
    c.execute(PLAYS)
    c.execute(REQ)
    c.execute(PE)
    for i, (sess, v3, bl, hy, status, top, err) in enumerate(plays):
        c.execute("INSERT INTO hybrid_shadow_plays(created_at, played_at, user, session_id, song_id, depth, rank_v3, "
                  "rank_blend, rank_hybrid, in_top100, status, error, extra_ms) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                  (i, i, user, sess, "s%d" % i, 2, v3, bl, hy, top, status, err, extra_ms))
    t = 1000
    for i, (sess, kind, hh, sh) in enumerate(requests):
        t += 100
        target = "song%d" % i
        top = [target] + ["x%d" % k for k in range(19)] if hh else ["a%d" % k for k in range(20)]
        srv = [target] + ["y%d" % k for k in range(19)] if sh else ["b%d" % k for k in range(20)]
        c.execute("INSERT INTO hybrid_shadow(created_at, served_id, user, session_id, position_kind, status, top_ids, "
                  "served_ids) VALUES (?,?,?,?,?,?,?,?)", (t, "sv%d" % i, user, sess, kind, "ok", json.dumps(top), json.dumps(srv)))
        c.execute("INSERT INTO play_events(file_path, played_at, listen_ratio, session_id) VALUES (?,?,?,?)",
                  (target, t + 10, 1.0, sess))
    c.commit()
    c.close()


def plays(n, per, hy, v3, bl=lambda i: 30.0, status="ok", top=1):
    return [("s%d" % (i // per), v3(i), bl(i), hy(i), status, top, None) for i in range(n)]


GOOD = dict(hy=lambda i: 3.0, v3=lambda i: 3.0 if i % 5 == 0 else 40.0)      # hybrid hits 100 %, v3 20 %


def test_hit_rates_and_paired_deltas(tmp_path):
    p = str(tmp_path / "admin_listening_log.db")
    make(p, "admin", plays(600, 8, **GOOD))
    q = str(tmp_path / "bob_listening_log.db")
    make(q, "bob", plays(40, 4, hy=lambda i: 2.0, v3=lambda i: 50.0))
    rep = sr.evaluate([p, q])
    g = rep["plays"]["owner"]
    assert g["n"] == 600 and g["sessions"] == 75
    assert g["hr10"]["hyb"][0] == 1.0 and g["hr10"]["v3"][0] == pytest.approx(0.2)
    assert g["hyb_minus_v3"][0] == pytest.approx(0.8) and g["hyb_minus_v3"][1] > 0.5
    assert rep["plays"]["others"]["n"] == 40
    assert sr.evaluate([p, q]) == rep                                   # reproducible


def test_flip_met_at_the_first_look(tmp_path):
    p = str(tmp_path / "admin_listening_log.db")
    make(p, "admin", plays(600, 8, **GOOD))
    checks, d = sr.decide(sr.evaluate([p]))
    assert d["verdict"] == "ON" and all(ok for _, ok, _ in checks)
    assert d["serve"].startswith("undecided")                           # the blend question needs 1,200 plays
    assert "FLIP CRITERION MET" in sr.render(sr.evaluate([p]))


def test_blend_or_hybrid_is_decided_at_1200(tmp_path):
    p = str(tmp_path / "admin_listening_log.db")
    make(p, "admin", plays(1300, 10, hy=lambda i: 3.0, v3=lambda i: 40.0, bl=lambda i: 3.0))     # blend as good
    assert sr.decide(sr.evaluate([p]))[1] == {"verdict": "ON", "serve": "blend"}
    q = str(tmp_path / "z" / "admin_listening_log.db")
    os.makedirs(os.path.dirname(q))
    make(q, "admin", plays(1300, 10, hy=lambda i: 3.0, v3=lambda i: 40.0, bl=lambda i: 40.0))    # blend worse
    assert sr.decide(sr.evaluate([q]))[1] == {"verdict": "ON", "serve": "hybrid"}


def test_wait_then_keep_v3(tmp_path):
    few = str(tmp_path / "a" / "admin_listening_log.db")
    os.makedirs(os.path.dirname(few))
    make(few, "admin", plays(100, 4, **GOOD))
    assert sr.decide(sr.evaluate([few]))[1]["verdict"] == "WAIT"
    same = str(tmp_path / "b" / "admin_listening_log.db")
    os.makedirs(os.path.dirname(same))
    make(same, "admin", plays(500, 8, hy=lambda i: 3.0, v3=lambda i: 3.0))      # no better: first look fails
    assert sr.decide(sr.evaluate([same]))[1]["verdict"] == "WAIT"               # look again at 1,200
    long = str(tmp_path / "c" / "admin_listening_log.db")
    os.makedirs(os.path.dirname(long))
    make(long, "admin", plays(1300, 10, hy=lambda i: 3.0, v3=lambda i: 3.0))
    assert sr.decide(sr.evaluate([long]))[1]["verdict"] == "KEEP_V3"


def test_required_checks_block_the_flip(tmp_path):
    def verdict(tag, **kw):
        d = tmp_path / tag
        d.mkdir()
        p = str(d / "admin_listening_log.db")
        make(p, "admin", kw.pop("rows", plays(600, 8, **GOOD)), **kw)
        return dict((n.split(" ")[0] + n.split(" ")[1], ok) for n, ok, _ in sr.decide(sr.evaluate([p]))[0]), sr.decide(sr.evaluate([p]))[1]["verdict"]

    slow, v = verdict("slow", extra_ms=25.0)
    assert not slow["p95extra"] and v != "ON"
    rows = plays(600, 8, **GOOD) + [("s1", 1, 1, 1, "error", 0, "budget: slow")] * 12
    err, v = verdict("err", rows=rows)
    assert not err["errors<"] and v != "ON"
    rows = plays(600, 8, **GOOD) + [("s1", 1, 1, 1, "error", 0, "KeyError: 'energy' column")]
    nan, v = verdict("nan", rows=rows)
    assert not nan["noNaN"] and v != "ON"
    low, v = verdict("top", rows=plays(600, 8, hy=lambda i: 3.0, v3=lambda i: 40.0, top=0))
    assert not low["playedsong"] and v != "ON"


def test_other_listeners_cannot_make_the_decision(tmp_path):
    p = str(tmp_path / "bob_listening_log.db")
    make(p, "bob", plays(900, 8, **GOOD))
    rep = sr.evaluate([p], owner="admin")
    assert rep["plays"]["owner"] is None and sr.decide(rep)[1]["verdict"] == "WAIT"


def test_request_rows_are_scored_informationally(tmp_path):
    p = str(tmp_path / "admin_listening_log.db")
    make(p, "admin", [], requests=[("s%d" % (i // 2), "next", i % 2 == 0, i % 4 == 0) for i in range(80)])
    g = sr.evaluate([p])["requests"]["owner/next"]
    assert g["n"] == 80 and g["hybrid"][0] == pytest.approx(0.5) and g["served"][0] == pytest.approx(0.25)
    assert sr.evaluate([p])["requests"]["owner/opener"] is None


def test_old_logs_without_the_tables_are_tolerated_and_nothing_is_written(tmp_path):
    p = str(tmp_path / "old_listening_log.db")
    c = sqlite3.connect(p)
    c.execute("CREATE TABLE play_events (id INTEGER PRIMARY KEY, track_title TEXT)")
    c.commit()
    c.close()
    q = str(tmp_path / "admin_listening_log.db")
    make(q, "admin", plays(20, 4, **GOOD))
    before = open(q, "rb").read()
    rep = sr.evaluate([p, q])
    assert rep["plays"]["owner"]["n"] == 20
    sr.main(["--db", q])
    sr.main(["--db", q, "--json"])
    assert open(q, "rb").read() == before
    assert not [f for f in os.listdir(tmp_path) if f.endswith(("-wal", "-shm", "-journal"))]
