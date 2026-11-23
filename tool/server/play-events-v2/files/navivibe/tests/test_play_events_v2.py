"""play-events-v2 tests. Run from the shuffle-server root:
    PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_play_events_v2.py -q
Uses a temp log folder; never touches the real listening logs."""
import json
import sqlite3
import threading
from datetime import datetime, timedelta, timezone

import pytest

from navivibe import feedback, play_events as pe

NOW = datetime(2026, 11, 23, 12, 0, 0, tzinfo=timezone.utc)


@pytest.fixture(autouse=True)
def tmp_logs(tmp_path, monkeypatch):
    monkeypatch.setattr(feedback, "DB_DIR", str(tmp_path))
    pe.reset_ready_cache()
    yield tmp_path
    pe.reset_ready_cache()


def ms(dt):
    return int(dt.timestamp() * 1000)


def finish(**kw):
    e = {"schema_version": 2, "event_type": "complete", "play_id": "p1", "title": "Song A",
         "file_path": "nd1", "listen_ratio": 1.0, "seconds_played": 200.0, "duration_s": 200,
         "played_at": ms(NOW - timedelta(minutes=4)), "tz_offset_min": 330, "session_id": "s1",
         "play_source": "smart_shuffle", "slot": 3, "score": 0.42, "served_by": "v3", "holdout": False,
         "client_version": "1.9.0"}
    e.update(kw)
    return e


def rows(user="u", sql="SELECT * FROM play_events"):
    c = sqlite3.connect(feedback.get_db_path(user))
    c.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in c.execute(sql)]
    finally:
        c.close()


# ── idempotency ──────────────────────────────────────────────────────────────

def test_repeat_of_a_finish_event_is_stored_once():
    assert pe.ingest("u", finish(), NOW)["status"] == "recorded"
    assert pe.ingest("u", finish(), NOW)["status"] == "duplicate"
    assert len(rows()) == 1


def test_repeat_of_an_aux_event_is_stored_once():
    ev = {"schema_version": 2, "event_type": "queue_edit", "event_id": "q1", "title": "Song A",
          "queue_edit": {"kind": "play_next", "from_index": 4, "to_index": 1}}
    assert pe.ingest("u", ev, NOW)["status"] == "recorded"
    assert pe.ingest("u", ev, NOW)["status"] == "duplicate"
    aux = rows(sql="SELECT * FROM play_aux_events")
    assert len(aux) == 1 and json.loads(aux[0]["payload"])["kind"] == "play_next"
    assert rows() == []  # an aux event never lands in play_events


def test_old_payload_without_play_id_dedupes_in_the_same_second():
    old = {"title": "Old", "listen_ratio": 0.8, "end_reason": "fwdbtn", "session_id": "s"}
    assert pe.ingest("u", old, NOW)["status"] == "recorded"
    assert pe.ingest("u", old, NOW)["status"] == "duplicate"
    later = pe.ingest("u", old, NOW + timedelta(seconds=30))
    assert later["status"] == "recorded"


def test_concurrent_deliveries_of_one_play_store_one_row():
    out = []

    def go():
        out.append(pe.ingest("u", finish(play_id="same"), NOW)["status"])

    ts = [threading.Thread(target=go) for _ in range(6)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    assert sorted(out).count("recorded") == 1
    assert len(rows()) == 1


# ── validation ───────────────────────────────────────────────────────────────

@pytest.mark.parametrize("patch,reason", [
    ({"title": ""}, "missing_title"),
    ({"listen_ratio": "abc"}, "bad_listen_ratio"),
    ({"listen_ratio": float("nan")}, "bad_listen_ratio"),
    ({"listen_ratio": -0.2}, "listen_ratio_out_of_range"),
    ({"listen_ratio": 7}, "listen_ratio_out_of_range"),
    ({"seconds_played": -3}, "bad_seconds_played"),
    ({"seconds_played": 900.0}, "seconds_gt_duration"),
    ({"duration_s": -5}, "bad_duration"),
    ({"duration_s": 10 ** 7}, "bad_duration"),
    ({"event_type": "teleport"}, "unknown_event_type"),
    ({"play_id": None}, "missing_play_id"),
    ({"play_id": "x" * 80}, "bad_play_id"),
    ({"listen_ratio": 0.1}, "complete_with_low_ratio"),
])
def test_malformed_events_are_refused_and_counted(patch, reason):
    r = pe.ingest("u", finish(**patch), NOW)
    assert r["status"] == "rejected"
    assert reason in r["reasons"]
    counts = {x["reason"]: x["n"] for x in rows(sql="SELECT * FROM rejected_counts")}
    assert counts[reason] == 1
    assert rows() == []


def test_a_body_that_is_not_an_object_is_refused_not_a_crash():
    for body in ([], "x", 5, None):
        assert pe.ingest("u", body, NOW)["status"] == "rejected"
    counts = {x["reason"]: x["n"] for x in rows(sql="SELECT * FROM rejected_counts")}
    assert counts["not_object"] == 4


def test_old_payload_is_still_accepted_with_missing_fields():
    r = pe.ingest("u", {"title": "Old", "end_reason": "natural", "listen_ratio": 1.0}, NOW)
    assert r["status"] == "recorded"
    row = rows()[0]
    assert row["schema_version"] == 1 and row["event_type"] == "complete"
    assert row["origin"] == "app" and row["tz_offset_min"] is None


def test_old_app_fake_burst_row_is_kept_but_flagged_and_not_folded():
    r = pe.ingest("u", {"title": "Burst", "end_reason": "natural", "listen_ratio": 0.0,
                        "session_id": "s", "play_id": "b1"}, NOW)
    assert r["status"] == "recorded"
    assert r["fold"] is False
    assert rows()[0]["quality"] == "suspect_burst"


def test_a_real_skip_at_zero_is_not_a_burst():
    r = pe.ingest("u", {"title": "Skipped", "end_reason": "fwdbtn", "listen_ratio": 0.0}, NOW)
    assert r["fold"] is True
    assert rows()[0]["quality"] is None


# ── time ─────────────────────────────────────────────────────────────────────

def test_played_at_is_the_start_not_the_arrival():
    pe.ingest("u", finish(played_at=ms(NOW - timedelta(hours=3))), NOW)
    assert rows()[0]["played_at"] == int((NOW - timedelta(hours=3)).timestamp())


def test_future_and_ancient_timestamps_are_clamped_and_flagged():
    pe.ingest("u", finish(play_id="f", played_at=ms(NOW + timedelta(days=2))), NOW)
    pe.ingest("u", finish(play_id="o", played_at=ms(NOW - timedelta(days=400))), NOW)
    got = rows()
    assert all(r["played_at"] == int(NOW.timestamp()) for r in got)
    assert all(r["quality"] == "clock_clamped" for r in got)
    counts = {x["reason"]: x["n"] for x in rows(sql="SELECT * FROM rejected_counts")}
    assert counts["flag:clock_clamped"] == 2


def test_local_hour_uses_the_phones_offset_not_ist():
    when = datetime(2026, 11, 23, 5, 0, tzinfo=timezone.utc)  # 10:30 IST
    pe.ingest("u", finish(played_at=ms(when), tz_offset_min=-300), when + timedelta(minutes=1))  # New York
    row = rows()[0]
    assert row["ist_hour"] == 10
    assert row["local_hour"] == 0
    assert row["tz_offset_min"] == -300


def test_missing_offset_means_ist():
    when = datetime(2026, 11, 23, 5, 0, tzinfo=timezone.utc)
    pe.ingest("u", finish(played_at=ms(when), tz_offset_min=None), when + timedelta(minutes=1))
    assert rows()[0]["local_hour"] == 10


def test_absurd_offset_is_dropped_and_flagged():
    pe.ingest("u", finish(tz_offset_min=99999), NOW)
    assert rows()[0]["tz_offset_min"] is None


# ── weather is the server's ──────────────────────────────────────────────────

def test_weather_comes_from_the_server_cache_never_the_client(tmp_path):
    cache = tmp_path / "w.json"
    cache.write_text(json.dumps({"code": 61, "temperature_c": 27.5,
                                 "fetched_at": (NOW - timedelta(minutes=10)).isoformat()}))
    assert pe.weather_at(int(NOW.timestamp()), str(cache)) == (61, 27.5)
    # a reading from 5 hours ago is not used
    assert pe.weather_at(int((NOW + timedelta(hours=5)).timestamp()), str(cache)) == (None, None)
    pe.ingest("u", finish(weather_code=800, temperature_c=25.0), NOW, weather=(None, None))
    row = rows()[0]
    assert row["weather_code"] is None and row["temperature_c"] is None


# ── what was served ──────────────────────────────────────────────────────────

def test_served_batch_is_recorded_and_joined_by_id():
    q = [{"rank": 1, "title": "A", "navidrome_id": "n1", "scores": {"final": 0.9}},
         {"rank": 2, "title": "B", "navidrome_id": "n2", "scores": {"final": 0.5}}]
    sid = pe.log_served("u", "s1", q, "smart", "v3+ai", depth=2, now=NOW)
    pe.ingest("u", finish(served_id=sid, slot=1, title="B"), NOW)
    j = rows(sql="SELECT e.track_title, i.score FROM play_events e JOIN served_items i "
                 "ON i.served_id = e.served_id AND i.rank = e.slot + 1")
    assert j == [{"track_title": "B", "score": 0.5}]


def test_served_logging_failure_never_raises(monkeypatch):
    monkeypatch.setattr(pe, "ensure_schema", lambda u: (_ for _ in ()).throw(RuntimeError("disk")))
    assert len(pe.log_served("u", "s", [{"title": "A"}], "smart", "v3")) == 16


def test_impression_batch_is_counted_once():
    assert pe.record_impressions_once("u", "b1", ["A", "B"], ["A"]) == 2
    assert pe.record_impressions_once("u", "b1", ["A", "B"], ["A"]) == 0
    got = {r["track_title"]: (r["shown_count"], r["played_count"]) for r in rows(sql="SELECT * FROM impressions")}
    assert got == {"A": (1, 1), "B": (1, 0)}
    assert pe.record_impressions_once("u", None, ["A"], []) == 1  # old app: no id, always counted


class _Engine:
    def __init__(self):
        self.seen = []

    def on_feedback(self, user, data):
        self.seen.append(data)


def test_handle_feedback_statuses_and_learning():
    cache, lock, eng = {}, threading.Lock(), _Engine()
    body, code = pe.handle_feedback("u", finish(), cache, lock, 500, eng, NOW)
    assert (code, body) == (200, {"ok": True})
    assert cache[("u", "s1")] == ["Song A"]
    assert eng.seen[0]["_played_at"] == int((NOW - timedelta(minutes=4)).timestamp())
    assert eng.seen[0]["_local_hour"] == 17
    body, code = pe.handle_feedback("u", finish(), cache, lock, 500, eng, NOW)
    assert (code, body["duplicate"]) == (200, True) and len(eng.seen) == 1
    body, code = pe.handle_feedback("u", finish(play_id="z", title=""), cache, lock, 500, eng, NOW)
    assert code == 422 and body["rejected"] == ["missing_title"]
    body, code = pe.handle_feedback("u", ["not", "a", "dict"], cache, lock, 500, eng, NOW)
    assert code == 422


def test_burst_row_is_stored_but_not_taught_to_the_model():
    cache, lock, eng = {}, threading.Lock(), _Engine()
    burst = {"title": "B", "end_reason": "natural", "listen_ratio": 0.0, "session_id": "s", "play_id": "bb"}
    body, code = pe.handle_feedback("u", burst, cache, lock, 500, eng, NOW)
    assert code == 200 and eng.seen == [] and cache == {}
    assert len(rows()) == 1


def test_engine_failure_does_not_fail_the_request():
    class Boom:
        def on_feedback(self, *a):
            raise RuntimeError("x")
    body, code = pe.handle_feedback("u", finish(), {}, threading.Lock(), 500, Boom(), NOW)
    assert code == 200


def test_session_cache_stays_bounded_under_many_sessions():
    cache, lock = {}, threading.Lock()
    for i in range(50):
        pe.handle_feedback("u", finish(play_id="p%d" % i, session_id="s%d" % i), cache, lock, 10, None, NOW)
    assert len(cache) <= 10


def test_history_erase_clears_every_v2_table():
    pe.ingest("u", finish(), NOW)
    pe.ingest("u", {"schema_version": 2, "event_type": "seek", "event_id": "k1", "title": "A",
                    "from_ms": 1000, "to_ms": 9000}, NOW)
    pe.log_served("u", "s", [{"title": "A", "rank": 1}], "smart", "v3", now=NOW)
    pe.ingest("u", finish(play_id="bad", title=""), NOW)
    pe.record_impressions_once("u", "b", ["A"], [])
    c = sqlite3.connect(feedback.get_db_path("u"))
    c.execute("DELETE FROM play_events")
    assert pe.erase_extra_tables(c) >= 5
    c.commit()
    for t in ("play_aux_events", "served_items", "served_batches", "rejected_events", "rejected_counts", "impressions"):
        assert c.execute("SELECT COUNT(*) FROM %s" % t).fetchone()[0] == 0, t
    c.close()


def test_seek_event_is_stored_with_positions():
    r = pe.ingest("u", {"schema_version": 2, "event_type": "seek", "event_id": "k2", "play_id": "p1", "title": "A",
                        "from_ms": 1000, "to_ms": 9000}, NOW)
    assert r["status"] == "recorded"
    aux = rows(sql="SELECT * FROM play_aux_events")[0]
    assert json.loads(aux["payload"]) == {"from_ms": 1000, "to_ms": 9000}
    assert aux["play_id"] == "p1" and aux["event_id"] == "k2"
    assert pe.ingest("u", {"schema_version": 2, "event_type": "seek", "event_id": "k3", "title": "A",
                           "from_ms": -5, "to_ms": 3}, NOW)["reasons"] == ["bad_seek"]


# ── route helpers ────────────────────────────────────────────────────────────

def test_safe_int_never_raises():
    assert pe.safe_int("12") == 12
    assert pe.safe_int("1.9") == 1
    assert pe.safe_int("abc", 7) == 7
    assert pe.safe_int(None, 3) == 3
    assert pe.safe_int(float("inf"), 4) == 4
    assert pe.safe_int(10 ** 12, 0, 0, 100) == 100
    assert pe.safe_int(True, 9) == 9


def test_bound_session_cache_drops_oldest_but_keeps_the_live_key():
    cache = {("u", str(i)): [i] for i in range(10)}
    pe.bound_session_cache(cache, 4, keep_key=("u", "0"))
    assert len(cache) == 4 and ("u", "0") in cache
