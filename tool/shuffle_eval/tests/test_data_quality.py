"""python -m pytest tool/shuffle_eval/tests -q   (no server, no network)"""
import os
import sqlite3
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import data_quality as dq  # noqa: E402
import flag_bad_rows as fl  # noqa: E402

NOW = 1795000000

SCHEMA = """CREATE TABLE play_events (id INTEGER PRIMARY KEY AUTOINCREMENT, track_title TEXT NOT NULL, file_path TEXT,
genre_bucket TEXT, composer TEXT, played_at INTEGER NOT NULL, ist_timestamp TEXT, ist_hour INTEGER, day_of_week INTEGER,
month INTEGER, weather_code INTEGER, temperature_c REAL, listen_ratio REAL, end_reason TEXT, session_id TEXT,
session_depth INTEGER, genre_streak_type TEXT, genre_streak_count INTEGER, volume REAL, processed INTEGER DEFAULT 0,
duration_s INTEGER, play_id TEXT)"""


def add(c, title, t, ratio, reason, sid="s", w=(800, 25.0), dur=200, hour=None, stamp=None):
    c.execute("INSERT INTO play_events (track_title, played_at, listen_ratio, end_reason, session_id, weather_code, "
              "temperature_c, duration_s, ist_hour, ist_timestamp) VALUES (?,?,?,?,?,?,?,?,?,?)",
              (title, t, ratio, reason, sid, w[0], w[1], dur, hour, stamp))


@pytest.fixture
def db(tmp_path):
    p = str(tmp_path / "u_listening_log.db")
    c = sqlite3.connect(p)
    c.execute(SCHEMA)
    add(c, "A", NOW - 1000, 1.0, "natural")
    add(c, "B", NOW - 900, 0.0, "natural")            # fake burst
    add(c, "C", NOW - 800, 0.0, "fwdbtn")             # a real skip
    add(c, "D", NOW - 700, 1.7, "natural")            # impossible ratio
    add(c, "E", NOW + 99999, 1.0, "natural")          # future
    add(c, "S", NOW - 500, 1.0, "natural", sid="navidrome_sync", w=(None, 33.0))
    add(c, "S", NOW - 500, 1.0, "natural", sid="navidrome_sync", w=(None, 33.0))
    add(c, "S", NOW - 500, 1.0, "natural", sid="navidrome_sync", w=(None, 33.0))
    add(c, "H", NOW - 400, 1.0, "natural", hour=3, stamp="2026-11-22T10:00:00+05:30")  # hour disagrees
    c.commit()
    c.close()
    return p


def test_report_counts_each_problem(db):
    r = dq.analyse_db(db, now=NOW)
    assert r["rows"] == 9
    assert r["by_origin"] == {"app": 6, "navidrome_sync": 3}
    assert r["fake_burst"]["rows"] == 1
    assert r["impossible_values"]["listen_ratio_outside_0_1"] == 1
    assert r["impossible_values"]["played_at_in_future"] == 1
    assert r["impossible_values"]["hour_disagrees_with_timestamp"] == 1
    assert r["duplicates"]["of_which_navidrome_sync_invented_timestamps"] == 2
    assert r["weather"]["constant_800_25_on_app_rows"] == 6
    assert r["missing_pct_by_client_version"]["(none)"]["play_id"] == 100.0
    assert dq.render([r], dq.merge([r]))  # renders without error


def test_report_is_read_only(db):
    before = os.path.getsize(db), open(db, "rb").read()
    dq.analyse_db(db, now=NOW)
    assert (os.path.getsize(db), open(db, "rb").read()) == before


def test_dry_run_changes_nothing(db):
    before = open(db, "rb").read()
    fl.process(db, apply=False, null_fake_weather=True, now=NOW)
    assert open(db, "rb").read() == before


def test_apply_tags_but_never_deletes_and_keeps_a_backup(db):
    fl.process(db, apply=True, null_fake_weather=False, now=NOW)
    c = sqlite3.connect(db)
    assert c.execute("SELECT COUNT(*) FROM play_events").fetchone()[0] == 9
    q = dict(c.execute("SELECT track_title || COALESCE(quality,''), 1 FROM play_events"))
    assert "Bsuspect_burst" in q and "Csuspect_burst" not in q  # a real skip is not a burst
    assert "Dimpossible" in q and "Eimpossible" in q
    assert c.execute("SELECT COUNT(*) FROM play_events WHERE quality='synthetic_time'").fetchone()[0] == 2
    assert c.execute("SELECT COUNT(*) FROM play_events WHERE weather_code = 800").fetchone()[0] == 6  # weather kept
    c.close()
    baks = [f for f in os.listdir(os.path.dirname(db)) if ".bak-" in f]
    assert len(baks) == 1
    assert sqlite3.connect(os.path.join(os.path.dirname(db), baks[0])).execute(
        "SELECT COUNT(*) FROM play_events").fetchone()[0] == 9


def test_fake_weather_nulling_is_opt_in(db):
    fl.process(db, apply=True, null_fake_weather=True, now=NOW)
    c = sqlite3.connect(db)
    assert c.execute("SELECT COUNT(*) FROM play_events WHERE weather_code = 800").fetchone()[0] == 0
    assert c.execute("SELECT COUNT(*) FROM play_events").fetchone()[0] == 9
