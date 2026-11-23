"""moods-v3: one decision from labeller, sound, tags and lyrics; the on/off switch; the owner review.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_moods_v3.py -q
"""

import json

import pytest

from navivibe.catalog import mood_audit, mood_fusion as F, mood_quality, mood_relabel, mood_review, mood_tags


def f(**kw):
    base = {"src": "spotify", "energy": 0.5, "valence": 0.5, "tempo": 100, "danceability": 0.6, "acousticness": 0.4,
            "audio": {}, "has_lyrics": True, "sad_words": 0, "anger_words": 0, "devotional_lyrics": False,
            "devotional_title": False, "devotional_other": False, "mass": False, "dance": False, "hype": False}
    return {**base, **kw}


THALAIVANE = {"id": "t", "title": 'Thalaivane (From "Kanguva")', "energy": 0.69, "valence": 0.246, "bpm": 89.998,
              "danceability": 0.634, "acousticness": 0.229, "feature_source": "spotify", "genre_primary": "Action / Mass",
              "nd_genres": '["Action", "Mass"]', "tags": '{"action": 1.0, "mass": 1.0, "tamil": 0.28}'}


def test_the_reported_song_is_not_calm_or_sad():
    facts = F.features(THALAIVANE, {"audio_mood": {"sad": 0.28, "happy": 0.18, "relaxed": 0.62, "aggressive": 0.38}})
    assert facts["mass"] and facts["src"] == "spotify"
    d = F.decide(["calm", "sad"], facts)
    assert d["moods"] == ["energetic"] and d["added"] == ["energetic"]
    assert {m for m, _ in d["dropped"]} == {"calm", "sad"}


@pytest.mark.parametrize("mood,facts", [
    ("calm", f(energy=0.7)), ("calm", f(mass=True, energy=0.4)), ("calm", f(energy=0.56, dance=True)),
    ("calm", f(energy=0.57, tempo=140, acousticness=0.2)),
    ("sad", f(valence=0.7)), ("sad", f(energy=0.85, valence=0.3)), ("sad", f(mass=True, energy=0.65, valence=0.2)),
    ("happy", f(valence=0.15)), ("energetic", f(energy=0.3)), ("angry", f(energy=0.3)),
    ("romantic", f(mass=True, energy=0.7, has_lyrics=False)), ("devotional", f(devotional_title=True)),
])
def test_contradictions_drop_a_first_label(mood, facts):
    assert F.conflict(mood, facts) and mood not in F.decide([mood], facts)["moods"]


def test_a_label_the_evidence_backs_survives():
    assert F.decide(["sad"], f(valence=0.2, energy=0.35, danceability=0.4))["moods"] == ["sad"]
    assert F.decide(["calm"], f(energy=0.35, acousticness=0.8))["moods"] == ["calm"]
    assert F.decide(["happy", "energetic"], f(valence=0.8, energy=0.85))["moods"] == ["happy", "energetic"]
    assert F.decide(["sad"], f(valence=0.6, energy=0.5, sad_words=3))["moods"] == ["sad"]         # the words say it
    assert F.decide(["energetic"], f(energy=0.39, hype=True, danceability=0.8))["dropped"][0][1].startswith("too little")  # rap: no hard veto


def test_thin_evidence_means_no_label():
    assert F.decide(["calm"], {"src": None, "has_lyrics": False})["moods"] == []
    assert F.decide(["sad"], f(valence=0.45, energy=0.6, has_lyrics=False))["moods"] == []
    assert F.decide(["sad"], f(valence=0.2, energy=0.3), {"c": 0.3, "b": "sound"})["moods"] == []   # the labeller was unsure
    assert F.decide([], None)["moods"] == []


def test_the_sound_does_not_reorder_but_sad_needs_a_word_to_lead_a_love_song():
    assert F.decide(["romantic", "happy"], f(valence=0.9, energy=0.8))["moods"] == ["romantic", "happy"]
    assert F.decide(["sad", "romantic"], f(valence=0.25, energy=0.35))["moods"] == ["romantic", "sad"]
    assert F.decide(["sad", "romantic"], f(valence=0.25, energy=0.35, sad_words=2))["moods"] == ["sad", "romantic"]
    assert F.decide(["sad", "romantic"], f(valence=0.42, energy=0.55))["moods"] == ["romantic"]


def test_only_energetic_is_ever_added_and_only_from_spotify_numbers():
    assert F.decide(["happy"], f(dance=True, energy=0.8, valence=0.8))["moods"] == ["happy", "energetic"]
    assert F.decide([], f(src="estimate", mass=True, energy=0.9))["moods"] == []
    assert F.decide([], f(energy=0.2, valence=0.1))["moods"] == []


def test_confidence_rises_with_the_evidence():
    weak = F.decide(["happy"], f(valence=0.55, energy=0.5))["confidence"]["happy"]
    strong = F.decide(["happy"], f(valence=0.9, energy=0.8))["confidence"]["happy"]
    assert 0 < weak < strong < 1


def test_sound_prefers_spotify_and_never_mixes_sources():
    row = {"energy": 0.9, "valence": 0.9, "bpm": 170, "feature_source": "essentia_calibrated"}
    assert F.sound(row)["src"] == "estimate"
    s = F.sound(row, {"energy": 0.3, "valence": 0.2, "tempo": 80})
    assert (s["src"], s["energy"], s["tempo"], s["acousticness"]) == ("spotify", 0.3, 80, None)
    assert F.sound(row, {"energy": None, "valence": None})["src"] == "estimate"     # a details row with no numbers
    assert F.sound({})["src"] is None


def test_a_repeated_chorus_word_is_one_piece_of_evidence():
    assert F.distinct(mood_quality._SAD_WORDS, "alone alone alone tears") == 2


# ── the switch ───────────────────────────────────────────────────────────────

@pytest.fixture
def library(tmp_path, monkeypatch):
    p = tmp_path / "mood_tags.json"
    p.write_text(json.dumps({"t": ["calm", "sad"], "h": ["happy"], "a": ["calm"]}))
    monkeypatch.setattr(mood_tags, "PATH", str(p))
    fx = {"t": mood_quality.song_facts(THALAIVANE, {}), "h": mood_quality.song_facts({"energy": 0.8, "valence": 0.9, "feature_source": "spotify"}, {"lyrics": "la la"}),
          "a": mood_quality.song_facts(THALAIVANE, {})}
    monkeypatch.setattr(mood_quality, "facts", lambda: fx)
    mood_quality.set_admin("a", ["calm"], "boss")
    return tmp_path


def test_installing_changes_nothing_until_it_is_switched_on(library, monkeypatch):
    assert mood_quality.rules_in_use() == 2
    assert mood_tags.load()["t"] == ["calm", "sad"]
    said = []
    assert mood_relabel.main([], out=said.append) == 0                             # the dry run
    assert "dry run" in said[-1] and mood_tags.load()["t"] == ["calm", "sad"]
    raw_before = (library / "mood_tags.json").read_text()
    assert mood_relabel.main(["--write"], out=said.append) == 0
    assert mood_quality.rules_in_use() == 3 and mood_tags.load()["t"] == ["energetic"]
    assert mood_tags.load()["a"] == ["calm"]                                       # an admin label is final
    assert (library / "mood_tags.json").read_text() == raw_before
    saved = list((library / "backups").glob("mood-labels-in-use-*.json"))
    assert json.loads(saved[0].read_text())["t"] == ["calm", "sad"]
    assert mood_quality.explain(["calm"], mood_quality.facts()["t"])[0][0] == "calm"  # the editor's flag
    mood_relabel.main(["--off"], out=said.append)
    assert mood_tags.load()["t"] == ["calm", "sad"]


def test_the_report_counts_changes_and_agreement(library):
    rep = mood_relabel.report(mood_relabel.live_rows())
    assert rep["songs"] == 2 and rep["changed"] == 1 and rep["gain_energetic"] == 1
    assert rep["agreement_v2"] == {"labelled": 2, "disagree": 1, "agree": 0.5}
    assert rep["agreement_v3"]["disagree"] == 0


def test_a_new_import_moves_the_labels_by_itself(library, monkeypatch):
    mood_relabel.main(["--write"], out=lambda *_: None)
    assert mood_tags.load()["h"] == ["happy"]
    monkeypatch.setattr(mood_quality, "facts", lambda: {"h": mood_quality.song_facts({"energy": 0.4, "valence": 0.1, "feature_source": "spotify"}, {})})
    assert mood_tags.load()["h"] == []


def test_the_audit_asks_again_about_unrated_contradicted_labels(library):
    assert "v3_conflict" in mood_audit.audit({"t": THALAIVANE}, {"t": ["calm"]}, {})["t"]
    mood_quality.record_meta({"t": {"c": 0.9, "b": "lyrics"}})
    assert "v3_conflict" not in mood_audit.audit({"t": THALAIVANE}, {"t": ["calm"]}, {}).get("t", [])


def test_the_labeller_is_told_the_genre():
    sent = json.loads(mood_tags.describe([THALAIVANE]))["songs"][0]
    assert sent["genre"] == "Action / Mass" and sent["danceability"] == 0.63


# ── the owner review ─────────────────────────────────────────────────────────

def _rows(n=300):
    return [{"id": f"s{i:03d}", "v2": ["calm"] if i % 3 else ["happy"], "v3": ["happy"], "confidence": {}, "dropped": [],
             "sound": {"src": "spotify", "energy": 0.8 if i % 3 else 0.5, "valence": 0.6}} for i in range(n)]


def test_the_sample_is_fixed_distinct_and_grouped():
    a, b = mood_review.pick(_rows(), pinned=["s007"]), mood_review.pick(_rows(), pinned=["s007"])
    assert [r["id"] for r in a] == [r["id"] for r in b] and len({r["id"] for r in a}) == len(a)
    groups = [r["group"] for r in a]
    assert groups.count("random") == 40 and groups.count("conflict") == 45 and groups.count("changed") == 15
    assert "s007" in {r["id"] for r in a}


def test_the_page_carries_the_songs_safely():
    page = mood_review.build(mood_review.items(mood_review.pick(_rows(), pinned=[]), {"s001": {"title": "</script><b>x"}}))
    assert "__DATA__" not in page and "</script><b>x" not in page and page.count("</script>") == 1


def test_scoring_uses_the_owners_marks_only():
    song = lambda i, g, mark: {"id": i, "group": g, "current": ["calm"], "proposed": ["happy"], "mark": mark}
    s = mood_review.score({"songs": [
        song("a", "random", {"current": "wrong", "proposed": "right", "moods": ["happy", "energetic"]}),
        song("b", "random", {"current": "right", "proposed": "wrong", "moods": ["calm"]}),
        song("c", "random", {"skip": True}), song("d", "random", None),
        song("e", "conflict", {"current": "wrong", "proposed": "right", "moods": ["happy"]})]},
        {"a": ["happy"], "b": ["sad"], "e": []})
    assert s["random"]["marked"] == 2
    assert s["random"]["current"]["right"] == 1 and s["random"]["proposed"]["right"] == 1
    assert s["random"]["now"]["right"] == 1 and s["conflict"]["now"]["no_label"] == 1
    lo, hi = mood_review.wilson(32, 40)
    assert 0.6 < lo < 0.8 < hi < 0.92
