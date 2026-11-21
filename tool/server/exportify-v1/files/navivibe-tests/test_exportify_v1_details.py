"""exportify-v1: spotify_details (reader, /catalog/songs extras) and the mood second opinion.
Made-up songs and numbers only.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_exportify_v1_details.py -q
"""

import json
import random
import sqlite3

import pytest

from navivibe import spotify_details as sd
from navivibe.catalog import api as catalog_api, mood_quality as mq, spotify_evidence as ev

COLS = ("song_id TEXT PRIMARY KEY, isrc TEXT, popularity INTEGER, genres TEXT, label TEXT, release_date TEXT, "
        "explicit INTEGER, duration_s REAL, matched_by TEXT, danceability REAL, energy REAL, key INTEGER, loudness REAL, "
        "mode INTEGER, speechiness REAL, acousticness REAL, instrumentalness REAL, liveness REAL, valence REAL, "
        "tempo REAL, time_signature INTEGER, updated_at REAL")


@pytest.fixture
def details(tmp_path, monkeypatch):
    """A spotify_details.db like the one tg-fetcher writes; the module reads this one."""
    p = tmp_path / "spotify_details.db"
    c = sqlite3.connect(p)
    c.execute(f"CREATE TABLE spotify_details ({COLS})")
    rows = [("a", "INA010000001", 61, json.dumps(["tamil pop", "filmi"]), "Sample Records", "2019-05-01", 1, 250.0, "isrc",
             0.6, 0.8, 7, -6.5, 1, 0.05, 0.2, 0.0, 0.1, 0.9, 128.0, 4, 1.0),
            ("b", "INA010000002", None, "[]", None, None, 0, None, "title",
             None, None, None, None, None, None, None, None, None, None, None, None, 1.0)]
    c.executemany(f"INSERT INTO spotify_details VALUES ({','.join('?' * 22)})", rows)
    c.commit()
    c.close()
    monkeypatch.setattr(sd, "PATH", str(p))
    return p


def test_reads_rows_and_decodes_genres(details):
    d = sd.get("a")
    assert d["isrc"] == "INA010000001" and d["genres"] == ["tamil pop", "filmi"] and d["valence"] == 0.9
    assert sd.get("nope") is None and set(sd.rows()) == {"a", "b"}


def test_isrc_fill_for_the_lyrics_proxy(details):
    assert sd.isrc_of("b") == "INA010000002"                       # the library has none: the CSV's
    assert sd.isrc_of("b", "XXX000000001") == "XXX000000001"       # the catalog's wins when it has one
    assert sd.isrc_of("zzz") == ""


def test_no_file_no_table_no_error(tmp_path, monkeypatch):
    monkeypatch.setattr(sd, "PATH", str(tmp_path / "missing.db"))
    assert sd.rows() == {} and sd.get("a") is None and sd.isrc_of("a") == "" and sd.stamp() is None
    p = tmp_path / "empty.db"
    sqlite3.connect(p).close()
    monkeypatch.setattr(sd, "PATH", str(p))
    assert sd.rows() == {}


def test_the_cache_follows_the_file(details):
    assert sd.get("a")["popularity"] == 61
    c = sqlite3.connect(details)
    c.execute("UPDATE spotify_details SET popularity=70, updated_at=2 WHERE song_id='a'")
    c.execute("INSERT INTO spotify_details (song_id, isrc, genres, updated_at) VALUES ('c', 'INA010000003', '[]', 3)")
    c.commit()
    c.close()
    assert sd.get("a")["popularity"] == 70 and sd.get("c")["isrc"] == "INA010000003"


# ── GET /catalog/songs ────────────────────────────────────────────────────────

def test_catalog_entry_gets_optional_keys_and_loses_nothing(details):
    s = {"id": "a", "year": 2018, "genre_display": "Melody", "bpm": 120.2, "energy": 0.7, "valence": 0.5}
    e = catalog_api._song_entry(s, ["happy"])
    assert e["year"] == 2018                                        # the catalog's own year is kept
    assert (e["pop"], e["released"], e["sp_genres"], e["label"]) == (61, "2019-05-01", ["tamil pop", "filmi"], "Sample Records")
    assert e["genre"] == "Melody" and e["moods"] == ["happy"] and e["bpm"] == 120 and e["energy"] == 0.7


def test_year_is_filled_only_where_the_catalog_has_none(details):
    assert catalog_api._song_entry({"id": "a"})["year"] == 2019
    assert "year" not in catalog_api._song_entry({"id": "b"})       # no release date either: stays absent


def test_a_song_with_no_row_is_exactly_as_before(details):
    e = catalog_api._song_entry({"id": "zzz", "year": 2001, "genre_display": "Rock"})
    assert e == {"id": "zzz", "genre": "Rock", "year": 2001}


# ── the mood second opinion ───────────────────────────────────────────────────

def base_rule(mood, f):
    return mq._ruled_out(mood, f)


def facts(**kw):
    f = {"energy": 0.6, "valence": 0.6, "bpm": 100, "audio": {"happy": 0.7, "sad": 0.3, "relaxed": 0.5, "aggressive": 0.2},
         "has_lyrics": True, "sad_words": 0, "anger_words": 0, "devotional_lyrics": False, "devotional_title": False,
         "devotional_other": False}
    f.update(kw)
    return f


def test_without_spotify_numbers_nothing_changes():
    rnd = random.Random(5)
    for _ in range(400):
        f = facts(energy=rnd.random(), valence=rnd.random(), bpm=rnd.choice([80, 120, 150]),
                  audio={"happy": rnd.random(), "sad": rnd.random(), "relaxed": rnd.random(), "aggressive": rnd.random()},
                  sad_words=rnd.choice([0, 3]), has_lyrics=rnd.random() < 0.8)
        for mood in ("sad", "happy", "angry", "calm", "romantic", "energetic", "devotional"):
            assert ev.second_opinion(mood, f, base_rule) == base_rule(mood, f) == mq.ruled_out(mood, f)


def test_veto_keeps_a_sad_song_spotify_hears_as_sad():
    f = facts(valence=0.7, audio={"happy": 0.8, "sad": 0.2})            # the audio model says happy: "sad" would go
    assert mq.ruled_out("sad", f)
    assert mq.ruled_out("sad", {**f, "sp_valence": 0.2, "sp_energy": 0.4}) is None


def test_veto_keeps_calm_when_spotify_energy_is_low():
    f = facts(energy=0.8)
    assert mq.ruled_out("calm", f) == "too loud for calm"
    assert mq.ruled_out("calm", {**f, "sp_valence": 0.5, "sp_energy": 0.3}) is None
    assert mq.ruled_out("calm", {**f, "sp_valence": 0.5, "sp_energy": 0.6}) == "too loud for calm"


def test_tie_break_drops_sad_when_spotify_agrees_with_a_nearly_happy_sound():
    f = facts(valence=0.55, audio={"happy": 0.6, "sad": 0.45})          # one step short: valence < 0.6
    assert mq.ruled_out("sad", f) is None
    assert "Spotify agrees" in mq.ruled_out("sad", {**f, "sp_valence": 0.8, "sp_energy": 0.7})
    assert mq.ruled_out("sad", {**f, "sp_valence": 0.5, "sp_energy": 0.7}) is None      # Spotify not clear: keeps it
    assert mq.ruled_out("sad", {**f, "sad_words": 3, "sp_valence": 0.9, "sp_energy": 0.9}) is None   # the lyrics say sad


def test_tie_break_for_calm_needs_both_sources():
    f = facts(energy=0.58)
    assert mq.ruled_out("calm", f) is None
    assert "Spotify agrees" in mq.ruled_out("calm", {**f, "sp_valence": 0.6, "sp_energy": 0.8})
    assert mq.ruled_out("calm", {**f, "energy": 0.4, "sp_valence": 0.6, "sp_energy": 0.8}) is None


def test_spotify_never_creates_a_label():
    raw = ["sad", "calm"]
    out = mq.sanity(raw, facts(energy=0.8, sp_valence=0.9, sp_energy=0.9))
    assert set(out) <= set(raw)
    assert mq.sanity([], facts(sp_valence=0.9, sp_energy=0.9)) == []


def test_switch_off(monkeypatch):
    f = {**facts(valence=0.7, audio={"happy": 0.8, "sad": 0.2}), "sp_valence": 0.2, "sp_energy": 0.4}
    assert mq.ruled_out("sad", f) is None
    monkeypatch.setenv("NAVIVIBE_SPOTIFY_MOODS", "0")
    assert mq.ruled_out("sad", f)


def test_admin_labels_beat_the_second_opinion(tmp_path):
    fx = {"a": {**facts(energy=0.8), "sp_valence": 0.9, "sp_energy": 0.9}}
    path = str(tmp_path / "mood_tags.json")
    mq.set_admin("a", ["calm"], "admin", path)
    assert mq.effective({"a": ["calm"]}, path, fx)["a"] == ["calm"]      # the rules would drop calm; the admin said calm
    mq.clear_admin("a", path)
    assert mq.effective({"a": ["calm"]}, path, fx)["a"] == []


def test_song_facts_carry_spotify_only_for_songs_with_a_row(details):
    row = {"id": "a", "energy": 0.5, "valence": 0.5, "title": "x"}
    assert mq.song_facts(row)["sp_valence"] == 0.9 and mq.song_facts(row)["sp_energy"] == 0.8
    assert "sp_valence" not in mq.song_facts({**row, "id": "b"})         # a row, but no audio features
    assert "sp_valence" not in mq.song_facts({**row, "id": "zzz"})
