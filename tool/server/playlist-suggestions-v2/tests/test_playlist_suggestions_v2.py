"""
Suggested songs for a playlist, v2: close to the playlist's songs one by one
(not to their average), by its artists and moods, in its languages, never a
song already in it, never a song the listener blocked, and never a popularity
pick.

    cd /opt/shuffle-server
    venv/bin/python -m pytest navivibe/tests/test_playlist_suggestions_v2.py -q
"""

import time
from types import SimpleNamespace

import numpy as np

from navivibe import discover
from navivibe.recsys.data import Event

NOW = time.time()


def row(sid, artist="A", composer=None, lang="ta", film=None, **kw):
    base = dict(id=sid, title=f"Song {sid}", artist=artist, composer=composer or artist, film=film,
                language=lang, genre_display="Melody", energy=0.4, valence=0.5, has_lyrics=1)
    return {**base, **kw}


def world(rows, vectors):
    """Hand-placed embeddings: `vectors` maps a song id to a 2-D direction."""
    ids = [r["id"] for r in rows]
    index = {s: i for i, s in enumerate(ids)}
    v = np.array([vectors.get(s, (0.0, 0.0)) for s in ids], dtype=float)
    v = np.hstack([v, np.full((len(ids), 1), 0.01)])
    v /= np.linalg.norm(v, axis=1, keepdims=True)
    return ids, index, {r["id"]: r for r in rows}, {"audio": v, "words": v}


def fit(rows, vectors, inside, **kw):
    ids, index, meta, emb = world(rows, vectors)
    return discover.fit_playlist(inside, ids, index, meta, emb, **kw)


KUTHU, MELODY = (1.0, 0.0), (0.0, 1.0)
MIDDLE = (0.7, 0.7)


def test_a_two_cluster_playlist_is_served_from_both_clusters():
    rows = [row(f"k{i}", f"K{i}", film=f"FK{i}") for i in range(3)] + [row(f"m{i}", f"M{i}", film=f"FM{i}") for i in range(3)]
    rows += [row(f"ck{i}", f"CK{i}", film=f"F{i}") for i in range(3)] + [row(f"cm{i}", f"CM{i}", film=f"G{i}") for i in range(3)]
    rows += [row("mid", "Mid", film="FMID")]
    vec = {**{f"k{i}": KUTHU for i in range(3)}, **{f"m{i}": MELODY for i in range(3)},
           **{f"ck{i}": KUTHU for i in range(3)}, **{f"cm{i}": MELODY for i in range(3)}, "mid": MIDDLE}
    got = [r["id"] for r in fit(rows, vec, ["k0", "k1", "k2", "m0", "m1", "m2"], limit=6)]
    assert {i for i in got if i.startswith("ck")} and {i for i in got if i.startswith("cm")}
    assert got.index("mid") > 3 if "mid" in got else True         # the "average" song is not the favourite


def test_a_tamil_playlist_gets_no_english_songs():
    rows = [row("a", "X"), row("b", "X"), row("ta", "Y"), row("en", "Z", lang="en"), row("ko", "W", lang="ko")]
    got = [r["id"] for r in fit(rows, {}, ["a", "b"])]
    assert got == ["ta"]


def test_a_playlist_with_some_english_still_gets_some():
    rows = ([row(f"t{i}", f"T{i}") for i in range(6)] + [row(f"e{i}", f"E{i}", lang="en") for i in range(4)]
            + [row("en_new", "Q", lang="en"), row("ta_new", "R")])
    got = [r["id"] for r in fit(rows, {}, ["t0", "t1", "t2", "t3", "t4", "t5", "e0", "e1", "e2", "e3"])]
    assert {"en_new", "ta_new"} <= set(got)


def test_nothing_already_in_the_playlist_or_excluded_is_returned():
    rows = [row(s, "R") for s in "abcdef"]
    got = [r["id"] for r in fit(rows, {}, ["a", "b"], exclude={"c"})]
    assert set(got) == {"d", "e", "f"}


def test_it_needs_two_songs_to_learn_from():
    assert fit([row("a"), row("b")], {}, ["a"]) == []
    assert fit([row("a"), row("b")], {}, ["a", "a"]) == []


def test_the_playlists_artist_wins_over_a_stranger_even_when_the_stranger_sounds_closer():
    rows = [row("a", "Anirudh"), row("b", "Anirudh"), row("same", "Anirudh", film="F1"), row("other", "Nobody", film="F2")]
    vec = {"a": (1, 0), "b": (1, 0), "same": (0.8, 0.6), "other": (1, 0)}
    got = fit(rows, vec, ["a", "b"])
    assert got[0]["id"] == "same" and got[0]["why"].startswith("More Anirudh")


def test_singers_count_not_only_composers():
    rows = [row("a", "Sid Sriram, Anirudh", composer="X"), row("b", "Sid Sriram", composer="Y"),
            row("sid", "Sid Sriram", composer="Z", film="F1"), row("none", "Someone", composer="W", film="F2")]
    got = fit(rows, {}, ["a", "b"])
    assert got[0]["id"] == "sid"


def test_mood_lifts_a_song_and_is_the_reason_shown():
    rows = [row("a", "P"), row("b", "Q"), row("sad", "R", film="F1"), row("happy", "S", film="F2")]
    moods = {"a": ["sad"], "b": ["sad", "romantic"], "sad": ["sad"], "happy": ["happy"]}
    got = fit(rows, {}, ["a", "b"], moods=moods)
    assert got[0]["id"] == "sad" and got[0]["why"].startswith("Same mood: sad")
    assert not any(r["why"].startswith("Same mood") for r in got if r["id"] == "happy")


def test_the_listeners_own_plays_only_break_ties():
    rows = [row("a", "R"), row("b", "R"), row("far", "R", film="F1"), row("near", "R", film="F2")]
    vec = {"a": (1, 0), "b": (1, 0), "far": (0, 1), "near": (1, 0.1)}
    taste = discover.Taste(play={"far": 50.0})                    # their favourite, but it does not fit
    got = fit(rows, vec, ["a", "b"], taste=taste)
    assert got[0]["id"] == "near"


def test_every_pick_carries_a_reason_and_variety_is_kept():
    rows = [row(s, "R", film="same") for s in ("a", "b")] + [row(f"c{i}", "R", film="same") for i in range(5)]
    got = fit(rows, {}, ["a", "b"], limit=10)
    assert len(got) <= discover.MAX_PER_FILM and all(r["why"] for r in got)


def test_suggest_for_playlist_end_to_end_with_exclude(monkeypatch):
    rows = [row("a", "Rahman"), row("b", "Rahman")] + [row(s, "Rahman", film=f"F{s}") for s in ("c", "d", "e")]
    ids, index, meta, emb = world(rows, {})
    eng = SimpleNamespace(cat=SimpleNamespace(ids=ids, index=index, meta=meta),
                          fb=SimpleNamespace(au=emb["audio"].astype(np.float32), tx=emb["words"].astype(np.float32)))
    discover._events.update(at=NOW, events=[])
    monkeypatch.setattr(discover.mood_tags, "load", lambda *a, **k: {"c": ["sad"]})
    first = discover.suggest_for_playlist(eng, "me", ["a", "b"], limit=2, now=NOW)
    assert len(first) == 2 and all("Rahman" in o["why"] for o in first)
    ids1 = [o["navidrome_id"] for o in first]
    again = [o["navidrome_id"] for o in discover.suggest_for_playlist(eng, "me", ["a", "b"], limit=5, now=NOW, exclude=ids1)]
    assert again and not set(again) & set(ids1) and not {"a", "b"} & set(again)
    assert discover.suggest_for_playlist(eng, "me", ["a", "b"], limit=5, now=NOW, exclude=["c", "d", "e"]) == []


def test_artist_tokens_split_features_and_ignore_unknown():
    assert discover._artist_tokens({"artist": "A, B feat. C & D"}) == ["a", "b", "c", "d"]
    assert discover._artist_tokens({"artist": "Unknown"}) == []
    assert discover._artist_tokens({}) == []


def test_the_route_reads_exclude():
    import os
    src = open(os.path.join(os.path.dirname(discover.__file__), "server.py"), encoding="utf-8").read()
    assert 'body.get("exclude")' in src and "exclude=shown" in src
