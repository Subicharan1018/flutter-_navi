"""matcher-v2: the one song matcher (tgfetch/song_match.py) and how the importers use it.

Runs in tg-fetcher's tests/ (install.sh --check runs it on a scratch copy) and from the repo
(`python -m pytest tool/server/matcher-v2/files/tests -q`, with tgfetch/ on the path).
The data is made up: tests/fixtures/matcher_gold.json has no real library or listening data.
"""
import json
import os
import sqlite3
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
for cand in (os.path.join(HERE, "..", "tgfetch"), os.path.join(HERE, "..")):
    if os.path.exists(os.path.join(cand, "song_match.py")):
        sys.path.insert(0, cand)
        break

import song_match as sm  # noqa: E402

GOLD = json.load(open(os.path.join(HERE, "fixtures", "matcher_gold.json"), encoding="utf-8"))["pairs"]


def _song(d, i="x"):
    return {"id": i, "isrc": "", "composer": "", "lyricist": "", "album_artist": "", "film": "", "album": "", **d}


def _match(p):
    q, lib = p["q"], _song(p["lib"])
    return sm.Index([lib]).match(q["title"], q.get("artist") or "", q.get("duration"), 5, album=q.get("album"))


@pytest.mark.parametrize("p", GOLD, ids=[p["id"] for p in GOLD])
def test_gold_pair(p):
    m = _match(p)
    assert (m.confidence if m else None) == p["expect"], (p["note"], m and m.rule)


def test_gold_totals_nothing_wrong_is_accepted_and_nothing_right_is_lost():
    res = [(p, _match(p)) for p in GOLD]
    assert not [p["id"] for p, m in res if p["label"] == 0 and m]
    assert not [p["id"] for p, m in res if p["label"] == 1 and not m]
    assert sum(1 for p, _ in res if p["label"] == 1) >= 15 and sum(1 for p, _ in res if p["label"] == 0) >= 15


# ── the contract ────────────────────────────────────────────────────────────────────────────────────

LIB = [_song({"title": "Oru Kanavu", "artist": "R. K. Selvam", "film": "Sivappu Ratham", "album": "Sivappu Ratham",
              "duration": 347, "isrc": "INA010000001"}, "a"),
       _song({"title": "Raathiri Pookal", "artist": "Maya Devi", "composer": "A. Rajan", "duration": 200}, "b")]


def test_find_hides_fuzzy_unless_asked():
    idx = sm.Index(LIB)
    assert idx.find("Raathiri Pookal", "A. Rajan", None, 5) is None
    assert idx.find("Raathiri Pookal", "A. Rajan", None, 5, fuzzy=True)["id"] == "b"
    m = idx.match("Raathiri Pookal", "A. Rajan", None, 5)
    assert (m.confidence, m.rule, m.song["id"]) == ("fuzzy", "composer", "b")


def test_isrc_is_exact_and_first():
    idx = sm.Index(LIB)
    m = idx.match("A totally different title", "Nobody", 10, 5, isrc="ina01-0000001")
    assert (m.confidence, m.song["id"]) == ("isrc", "a")
    assert idx.find("A totally different title", "Nobody", 10, 5, isrc="INA010000001")["id"] == "a"


def test_old_call_still_works_with_four_arguments():
    idx = sm.Index(LIB)
    assert idx.find("Oru Kanavu", "R.K. Selvam", 349, 5)["id"] == "a"
    assert idx.find("Oru Kanavu", "Somebody Else", 349, 5) is None


def test_with_no_rules_it_is_the_old_matcher():
    """rules=∅: exactly title (or phonetic) + same version words + a name in common + length within the slack."""
    idx = sm.Index(LIB, rules=set())
    assert idx.match("Oru Kanavu", "R. K. Selvam", 349, 5).confidence == "strong"
    assert idx.match("Oru Kanavu", "R. K. Selvam", 355, 5) is None            # 8 s: only the len rule buys it
    assert idx.match("Raathiri Pookal", "A. Rajan", None, 5) is None          # composer: only the role rule
    assert sm.Index(LIB).match("Oru Kanavu", "R. K. Selvam", 355, 5).confidence == "fuzzy"


def test_slack_of_the_caller_is_kept():
    idx = sm.Index(LIB)
    assert idx.find("Oru Kanavu", "R. K. Selvam", 365, 25)["id"] == "a"       # exportify's "maybe" (25 s) as before
    assert idx.find("Oru Kanavu", "R. K. Selvam", 365, 5) is None


def test_ties_prefer_the_closest_length_then_the_film():
    lib = [_song({"title": "Same Name", "artist": "Ilan", "duration": 200, "film": "Film One"}, "1"),
           _song({"title": "Same Name", "artist": "Ilan", "duration": 204, "film": "Film Two"}, "2"),
           _song({"title": "Same Name", "artist": "Ilan", "duration": 400, "film": "Film Three"}, "3")]
    idx = sm.Index(lib)
    assert idx.match("Same Name", "Ilan", 203, 5).song["id"] == "2"
    assert idx.match("Same Name", "Ilan", None, 5, album="Film One (Original Motion Picture Soundtrack)").song["id"] == "1"


def test_every_old_version_word_still_blocks():
    plain = sm.Index([_song({"title": "Tune", "artist": "Ilan", "duration": 200})])
    for w in ("Remix", "Reprise", "Unplugged", "Lofi", "Sped Up", "Live", "Karaoke", "Cover", "Female", "Duet", "Revival",
              "Instrumental", "Acoustic", "Slowed", "Reverb", "Mashup"):
        assert plain.match(f"Tune ({w})", "Ilan", 200, 5) is None, w


# ── one place: the shared helpers equal the shuffle server's ─────────────────────────────────────────

def test_title_helpers_equal_the_servers_when_it_is_there():
    enrich = pytest.importorskip("navivibe.catalog.enrich")
    data = pytest.importorskip("navivibe.recsys.data")
    for t in ("Kaadhal Kanmani (From \"Bachelor\")", "Vilayadu Mankatha", "Naan Un - Tamil Version", "A / B (feat. C)",
              "Rowdy Baby [Telugu]", "  Hello,   World!  ", "காதல் கண் கட்டுதே"):
        assert sm.norm_title(t) == enrich.norm_title(t), t
        assert sm.phonetic_key(t) == data.phonetic_key(t), t


def test_name_ratio_equals_rapidfuzz_when_it_is_there():
    fuzz = pytest.importorskip("rapidfuzz.fuzz")
    for a, b in (("anirudh", "anirudh ravichander"), ("ar rahman", "a r rahman"), ("yuvan shankar raja", "yuvanshankar raja"),
                 ("", "x"), ("same", "same"), ("hariharan", "harihara")):
        assert abs(sm._ratio(a, b) * 100 - fuzz.ratio(a, b)) < 1e-6, (a, b)


def test_library_sweep_uses_the_shared_index():
    ls = pytest.importorskip("tgfetch.library_sweep")
    if not hasattr(ls.Index, "match"):
        pytest.skip("library_sweep is not patched (running from the repo)")
    assert ls.Index is sm.Index or ls.Index.__module__.endswith("song_match")
    assert ls.versions("Tune (Remix)") == frozenset({"remix"})        # stored song keys are built from these: unchanged


# ── the importers ───────────────────────────────────────────────────────────────────────────────────

def test_exportify_lists_a_fuzzy_match_as_maybe_never_owned():
    ex = pytest.importorskip("tgfetch.exportify")
    ls = pytest.importorskip("tgfetch.library_sweep")
    if not hasattr(ls.Index, "match"):
        pytest.skip("not patched")
    lib = [_song({"title": "Every Dawn", "artist": "The Marlows", "duration": 247}, "m")]
    r = {"isrc": "", "title": "Every Dawn", "artist": "The Marlows", "album": "Dawn", "duration_s": 254.0}
    out = ex.match_one(r, {}, ls.Index(lib))
    assert out["state"] == "wishlist" and out["similar_id"] == "m"
    r["duration_s"] = 248.0
    assert ex.match_one(r, {}, ls.Index(lib))["state"] == "owned"


def test_load_library_returns_the_credits(tmp_path):
    lib = pytest.importorskip("tgfetch.library")
    if not hasattr(lib, "_credits"):
        pytest.skip("not patched")
    db = tmp_path / "nd.db"
    c = sqlite3.connect(db)
    c.execute("CREATE TABLE media_file (id TEXT, title TEXT, artist TEXT, album TEXT, album_artist TEXT, suffix TEXT, "
              "duration REAL, tags TEXT, participants TEXT, missing INT)")
    c.execute("INSERT INTO media_file VALUES ('1','T','A','Al','AA','flac',200,?,?,0)",
              (json.dumps({"isrc": [{"value": "x1"}]}),
               json.dumps({"composer": [{"id": "c", "name": "R. K. Selvam"}, {"id": "d", "name": "Other"}],
                           "lyricist": [{"id": "e", "name": "Kavi Nila"}]})))
    c.execute("INSERT INTO media_file VALUES ('2','T2','A','Al','AA','flac',200,'{}','not json',0)")
    c.commit()
    c.close()
    songs = {s["id"]: s for s in lib.load_library(str(db))}
    assert songs["1"]["composer"] == "R. K. Selvam; Other" and songs["1"]["lyricist"] == "Kavi Nila"
    assert songs["1"]["album_artist"] == "AA" and songs["1"]["isrc"] == "X1"
    assert songs["2"]["composer"] == "" and "participants" not in songs["2"]


def test_load_library_on_an_older_schema_falls_back(tmp_path):
    lib = pytest.importorskip("tgfetch.library")
    db = tmp_path / "old.db"
    c = sqlite3.connect(db)
    c.execute("CREATE TABLE media_file (id TEXT, title TEXT, artist TEXT, album TEXT, suffix TEXT, duration REAL, tags TEXT, "
              "missing INT)")
    c.execute("INSERT INTO media_file VALUES ('1','T','A','Al','flac',200,'{}',0)")
    c.commit()
    c.close()
    assert [s["id"] for s in lib.load_library(str(db))] == ["1"]
