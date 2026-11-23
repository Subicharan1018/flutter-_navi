"""flow-v2: Flow chooses and orders songs by their sound (real Spotify numbers where there are any).

FLOW_V2=off  -> the answers are exactly flow.py's old answers (golden file made from the unpatched live flow.py)
FLOW_V2=shadow -> the same answers, plus a log line with the order v2 would have used
FLOW_V2=on   -> chip fit, one artist at most two in eight, sequenced by sound, `flow` on every song
"""

import json
import logging
import os
import sqlite3
from types import SimpleNamespace

import numpy as np
import pytest

from navivibe import discover, explore, flow, spotify_details, taste_exclusions
from navivibe.catalog import mood_tags
from navivibe.tests.test_discover import NOW, _plays, _row, _world

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "flow_v2_golden.json")

FAMILIAR = [f"f{i}" for i in range(70)]
FRESH = [f"n{i}" for i in range(60)]
MOODS = ["sad", "calm", "energetic", "happy"]


def _artist(i):
    return f"Artist{i % 9}"


def _sound(s, i):
    """A made-up sound per song, spread over the whole range; mood label follows it loosely."""
    rng = np.random.default_rng(i * 7919 + 13)
    return float(rng.uniform(0.1, 0.95)), float(rng.uniform(0.1, 0.95)), float(rng.uniform(70, 170))


def _label(e, v):
    return "energetic" if e > 0.7 else "calm" if e < 0.35 else "happy" if v > 0.55 else "sad"


@pytest.fixture
def world(tmp_path, monkeypatch):
    monkeypatch.setattr(taste_exclusions, "DIR", str(tmp_path / "taste"))
    songs = FAMILIAR + FRESH
    rows, tags, real = [], {}, []
    for i, s in enumerate(songs):
        e, v, b = _sound(s, i)
        rows.append(_row(s, f"C{i % 5}", film=f"F{s}", energy=e, valence=v, bpm=b, artist=_artist(i), duration=200))
        tags[s] = [_label(e, v)]
        if i % 4:                                               # three songs in four have real Spotify numbers
            real.append((s, e, v, b))
    path = tmp_path / "moods.json"
    path.write_text(json.dumps(tags))
    monkeypatch.setattr(mood_tags, "PATH", str(path))
    db = tmp_path / "sd.db"
    c = sqlite3.connect(db)
    c.execute("CREATE TABLE spotify_details (song_id TEXT PRIMARY KEY, energy REAL, valence REAL, tempo REAL, key INTEGER, mode INTEGER, genres TEXT)")
    c.executemany("INSERT INTO spotify_details VALUES (?,?,?,?,?,?,?)", [(s, e, v, b, 5, 1, "[]") for s, e, v, b in real])
    c.commit(); c.close()
    monkeypatch.setattr(spotify_details, "PATH", str(db))
    ids, index, meta, emb = _world(rows)
    discover._events.update(at=NOW, events=sum([_plays("me", [s], days_ago=len(FAMILIAR) - i + 3, n=4)
                                               for i, s in enumerate(FAMILIAR)], []))
    monkeypatch.setenv("NAVIVIBE_LOG_DIR", str(tmp_path / "logs"))
    from navivibe import feedback
    monkeypatch.setattr(feedback, "DB_DIR", str(tmp_path / "logs"))
    from navivibe import flow_v2
    flow_v2._sound_cache.update(key=None, meta=None)
    flow_v2._profile_cache.update(at=0.0, key=None, p={})
    flow_v2._warned.clear()
    return SimpleNamespace(cat=SimpleNamespace(ids=ids, index=index, meta=meta),
                           fb=SimpleNamespace(au=emb["audio"].astype(np.float32), tx=emb["words"].astype(np.float32)))


def run(world, seed=0, **kw):
    return flow.next_batch(world, "me", now=NOW, rng=np.random.default_rng(seed), **kw)


CASES = [(0, None, 8), (1, "calm", 8), (2, "energetic", 10), (3, None, 20), (4, "sad", 6)]


def golden_ids(world, tmp_path):
    """The songs of a few batches, in order. flow_v2_golden.json was made by running this on the live flow.py BEFORE
    this package touched it; FLOW_V2=off must still give exactly that."""
    out = []
    for seed, mood, count in CASES:
        r = run(world, seed, count=count, mood=mood, session=f"g{seed}", store=explore.Store(str(tmp_path / f"s{seed}.db")))
        assert "flow_v2" not in r and all("flow" not in i for i in r["items"])
        out.append([i["navidrome_id"] for i in r["items"]])
    return out


# ── off ──────────────────────────────────────────────────────────────────────

def test_off_is_the_old_flow_to_the_song(world, monkeypatch, tmp_path):
    monkeypatch.delenv("FLOW_V2", raising=False)
    with open(GOLDEN, encoding="utf-8") as f:
        assert golden_ids(world, tmp_path) == json.load(f)


# ── the flag ─────────────────────────────────────────────────────────────────

def test_the_flag_is_read_on_every_call_and_an_unknown_value_is_off_and_logged(monkeypatch, caplog):
    from navivibe import flow_v2
    flow_v2._warned.clear()
    monkeypatch.delenv("FLOW_V2", raising=False)
    assert flow_v2.mode() == "off"
    for v, want in [("on", "on"), (" ON ", "on"), ("shadow", "shadow"), ("off", "off"), ("", "off")]:
        monkeypatch.setenv("FLOW_V2", v)
        assert flow_v2.mode() == want
    with caplog.at_level(logging.ERROR, logger="navivibe.flow_v2"):
        monkeypatch.setenv("FLOW_V2", "enabled")
        assert flow_v2.mode() == "off"
        assert flow_v2.mode() == "off"
    assert sum("not one of" in r.message for r in caplog.records) == 1, "said once, not on every request"


# ── shadow ───────────────────────────────────────────────────────────────────

def test_shadow_serves_what_off_serves_and_logs_both_orders(world, monkeypatch, tmp_path):
    from navivibe import flow_v2
    monkeypatch.delenv("FLOW_V2", raising=False)
    off = run(world, 5, count=8, mood="calm", session="s", store=explore.Store(str(tmp_path / "a.db")))
    monkeypatch.setenv("FLOW_V2", "shadow")
    sh = run(world, 5, count=8, mood="calm", session="s", store=explore.Store(str(tmp_path / "b.db")), seen=["f3"])
    assert [i["navidrome_id"] for i in sh["items"]] == [i["navidrome_id"] for i in off["items"]]
    assert all("flow" not in i for i in sh["items"])
    assert sh["flow_v2"]["mode"] == "shadow"
    lines = [json.loads(x) for x in open(flow_v2.log_path(), encoding="utf-8")]
    assert len(lines) == 1
    assert lines[0]["mode"] == "shadow" and lines[0]["old"] == [i["navidrome_id"] for i in sh["items"]]
    assert sorted(lines[0]["new"]) == sorted(lines[0]["old"]) and lines[0]["tail"] == "f3"
    assert lines[0]["cost_new"] <= lines[0]["cost_old"] + 1e-9


def test_an_unwritable_log_is_reported_not_swallowed_and_does_not_break_flow(world, monkeypatch, tmp_path, caplog):
    from navivibe import flow_v2
    monkeypatch.setenv("FLOW_V2", "shadow")
    monkeypatch.setattr(flow_v2, "log_path", lambda: str(tmp_path / "file" / "x" / "shadow.jsonl"))
    (tmp_path / "file").write_text("a file where a folder should be")
    with caplog.at_level(logging.ERROR, logger="navivibe.flow_v2"):
        r = run(world, 1, count=8, session="s", store=explore.Store(str(tmp_path / "c.db")))
    assert r["count"] == 8
    assert any("could not write the shadow log" in x.message for x in caplog.records)


# ── on ───────────────────────────────────────────────────────────────────────

def test_on_adds_the_sound_to_every_song_and_says_where_it_came_from(world, monkeypatch, tmp_path):
    monkeypatch.setenv("FLOW_V2", "on")
    r = run(world, 2, count=10, mood="energetic", session="s", store=explore.Store(str(tmp_path / "d.db")))
    assert r["flow_v2"]["mode"] == "on" and r["flow_v2"]["chip_profile"] and not r["flow_v2"].get("error")
    sources = {i["flow"]["sound"] for i in r["items"]}
    assert sources <= {"real", "predicted"} and "real" in sources
    for n, i in enumerate(r["items"], 1):
        assert i["flow"]["step"] == n and 0 <= i["flow"]["energy"] <= 1 and "fit" in i["flow"]
    assert [i["rank"] for i in r["items"]] == list(range(1, r["count"] + 1))


def test_real_numbers_replace_the_guesses(world, monkeypatch):
    from navivibe import flow_v2
    sound, overlay = flow_v2.tables(world.cat.meta)
    assert sound["f1"]["real"] and not sound["f0"]["real"]          # every fourth song has no Spotify row
    world.cat.meta["f1"]["energy"] = 0.01                           # a wrong guess in the catalog
    flow_v2._sound_cache.update(key=None, meta=None)
    sound, overlay = flow_v2.tables(world.cat.meta)
    assert overlay["f1"]["energy"] != 0.01 and sound["f1"]["energy"] == overlay["f1"]["energy"]


def test_the_chip_drops_songs_that_sound_nothing_like_it(world, monkeypatch, tmp_path):
    monkeypatch.setenv("FLOW_V2", "on")
    from navivibe import flow_v2
    # a song labelled calm whose REAL numbers are loud and fast must not be offered for the calm chip
    world.cat.meta["n1"].update(energy=0.2, valence=0.5)
    tags = mood_tags.load_raw()
    tags["n1"] = ["calm"]
    open(mood_tags.PATH, "w").write(json.dumps(tags))
    c = sqlite3.connect(spotify_details.PATH)
    c.execute("INSERT OR REPLACE INTO spotify_details VALUES ('n1', 0.97, 0.9, 175, 5, 1, '[]')")
    c.commit(); c.close()
    flow_v2._sound_cache.update(key=None, meta=None)
    seen = set()
    for seed in range(12):
        r = run(world, seed, count=8, mood="calm", session=f"z{seed}", store=explore.Store(str(tmp_path / f"e{seed}.db")))
        seen |= {i["navidrome_id"] for i in r["items"]}
    assert "n1" not in seen


def test_a_chip_too_narrow_to_fill_batches_is_relaxed_and_says_so(world, monkeypatch, caplog):
    from navivibe import flow_v2
    monkeypatch.setenv("FLOW_V2", "on")
    taste = SimpleNamespace(skip={}, play={})
    run_ = flow_v2.begin("me", "calm", taste, world.cat.meta, NOW, "s", [], 8)
    run_.start_labels(mood_tags.load(), NOW)
    ids = [s for s in FRESH]
    monkeypatch.setattr(flow_v2, "FIT_MAX", 0.0)                    # everything real is "far"
    with caplog.at_level(logging.WARNING, logger="navivibe.flow_v2"):
        kept = run_.keep(ids, 8)
    assert kept == ids and run_.relaxed
    assert any("relaxing" in x.message for x in caplog.records)
    assert run_.summary()["relaxed"] is True


def test_no_artist_fills_a_batch(world, monkeypatch, tmp_path):
    monkeypatch.setenv("FLOW_V2", "on")
    for seed in range(10):
        r = run(world, seed, count=8, session=f"a{seed}", store=explore.Store(str(tmp_path / f"f{seed}.db")))
        per = {}
        for i in r["items"]:
            a = world.cat.meta[i["navidrome_id"]]["artist"]
            per[a] = per.get(a, 0) + 1
        assert max(per.values()) <= 2, per


def test_neighbours_are_not_the_same_artist_or_film(world, monkeypatch, tmp_path):
    monkeypatch.setenv("FLOW_V2", "on")
    for seed in range(10):
        r = run(world, seed, count=20, session=f"b{seed}", store=explore.Store(str(tmp_path / f"g{seed}.db")))
        art = [world.cat.meta[i["navidrome_id"]]["artist"] for i in r["items"]]
        assert all(a != b for a, b in zip(art, art[1:])), art


def test_v2_orders_by_sound_better_than_the_old_order(world, monkeypatch, tmp_path):
    """Same songs, same batches: the v2 order has smaller jumps between neighbours than flow.py's order."""
    from navivibe import flow_v2
    old_t, new_t = [], []
    for seed in range(8):
        monkeypatch.setenv("FLOW_V2", "shadow")
        run(world, seed, count=10, mood=None, session=f"c{seed}", store=explore.Store(str(tmp_path / f"h{seed}.db")), seen=["f2"])
    for line in map(json.loads, open(flow_v2.log_path(), encoding="utf-8")):
        old_t.append(line["cost_old"]); new_t.append(line["cost_new"])
    assert len(old_t) == 8
    assert sum(new_t) < 0.8 * sum(old_t), (sum(new_t), sum(old_t))


def test_the_batch_opens_close_to_the_song_already_at_the_end_of_the_queue(world, monkeypatch):
    from navivibe import flow_v2
    monkeypatch.setenv("FLOW_V2", "on")
    sound, _ = flow_v2.tables(world.cat.meta)
    tail = "f1"
    taste = SimpleNamespace(skip={}, play={})
    pool = FRESH[:8]
    items = [{"navidrome_id": s, "kind": "familiar"} for s in pool]
    r = flow_v2.begin("me", None, taste, world.cat.meta, NOW, "s", [tail], 8)
    out = r.sequence(items, {s: "familiar" for s in pool}, None, None)
    first = out[0]["navidrome_id"]
    nearest = min(pool, key=lambda s: flow_v2.transition(r, tail, s))
    assert first == nearest or flow_v2.transition(r, tail, first) <= flow_v2.transition(r, tail, nearest) + 0.35


def test_new_songs_come_later_in_a_batch_and_it_opens_familiar(world, monkeypatch, tmp_path):
    monkeypatch.setenv("FLOW_V2", "on")
    pos, opens, n = [], 0, 0
    for seed in range(12):
        r = run(world, seed, count=10, session=f"k{seed}", store=explore.Store(str(tmp_path / f"k{seed}.db")))
        kinds = [i["kind"] for i in r["items"]]
        opens += kinds[0] == "familiar"; n += 1
        pos += [j / (len(kinds) - 1) for j, k in enumerate(kinds) if k != "familiar"]
    assert opens / n >= 0.9
    assert sum(pos) / len(pos) > 0.55


def test_a_familiar_song_the_listener_often_skipped_scores_lower(world, monkeypatch):
    from navivibe import flow_v2
    monkeypatch.setenv("FLOW_V2", "on")
    taste = SimpleNamespace(skip={"f1": 3.0}, play={"f1": 1.0, "f2": 4.0})
    r = flow_v2.begin("me", None, taste, world.cat.meta, NOW, "s", [], 8)
    b = r.bonus(["f1", "f2", "f3"], True)
    assert b[0] == pytest.approx(-0.75) and b[1] == 0 and b[2] == 0
    assert (r.bonus(["f1"], False) == 0).all()


def test_a_failure_in_the_ordering_serves_the_old_order_and_reports_it(world, monkeypatch, tmp_path, caplog):
    from navivibe import flow_v2
    monkeypatch.setenv("FLOW_V2", "on")
    monkeypatch.setattr(flow_v2.Run, "sequence", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom")))
    with caplog.at_level(logging.ERROR, logger="navivibe.flow"):
        r = run(world, 3, count=8, session="s", store=explore.Store(str(tmp_path / "m.db")))
    assert r["count"] == 8 and "boom" in r["flow_v2"]["error"]
    assert any("ordering failed" in x.message for x in caplog.records)


def test_no_spotify_file_means_every_song_is_predicted_not_an_error(world, monkeypatch, tmp_path):
    from navivibe import flow_v2
    monkeypatch.setattr(spotify_details, "PATH", str(tmp_path / "missing.db"))
    spotify_details._cache.update(path=None, stamp=None, rows={})
    flow_v2._sound_cache.update(key=None, meta=None)
    monkeypatch.setenv("FLOW_V2", "on")
    r = run(world, 1, count=8, mood="calm", session="s", store=explore.Store(str(tmp_path / "n.db")))
    assert r["count"] == 8 and {i["flow"]["sound"] for i in r["items"]} == {"predicted"}


def test_the_chip_profile_comes_from_the_librarys_own_labelled_songs(world):
    from navivibe import flow_v2
    sound, overlay = flow_v2.tables(world.cat.meta)
    p = flow_v2.profiles(overlay, sound, mood_tags.load(), NOW)
    assert p["energetic"][0] > p["calm"][0]                          # louder than calm, from the labels alone
    assert flow_v2.distance(p["calm"], {"energy": p["calm"][0], "valence": p["calm"][1]}) == pytest.approx(0)
    assert flow_v2.distance(None, {"energy": 0.5, "valence": 0.5}) is None


# ── the patch ────────────────────────────────────────────────────────────────

def test_the_patch_is_idempotent_and_refuses_a_different_flow_py(tmp_path):
    import importlib.util
    here = os.path.join(HERE, "flow_v2_patch.py")                      # installed next to the test
    here = here if os.path.exists(here) else os.path.join(os.path.dirname(HERE), "patch_flow.py")   # in the repo
    spec = importlib.util.spec_from_file_location("patch_flow", here)
    pf = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pf)
    src = open(flow.__file__, encoding="utf-8").read()
    assert pf.apply(src) == src                                       # already patched here: same text back
    odd = tmp_path / "flow.py"
    odd.write_text("def next_batch(engine, user):\n    return 1\n")
    assert pf.main(["patch_flow.py", str(odd)]) == 2
    assert odd.read_text() == "def next_batch(engine, user):\n    return 1\n"
    with pytest.raises(ValueError):
        pf.apply("x = 1\n")
