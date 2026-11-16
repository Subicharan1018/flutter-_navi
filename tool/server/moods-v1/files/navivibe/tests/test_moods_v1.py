"""moods-v1: /catalog/songs carries each song's mood labels, "Not this mood" beats the label for
that listener (catalog-free routes, Flow, taste), and the labeller reads the first verse plus the
chorus with an English prompt for English songs.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_moods_v1.py -q
"""

import json

import pytest

from navivibe import discover, mood_overrides
from navivibe.catalog import mood_audit, mood_lyrics, mood_tags, store
from navivibe.catalog.api import CatalogIndex, build_document
from navivibe.tests.test_listen_routes import H, _basic, client  # noqa: F401  (the route fixture)


# ── /catalog/songs: moods ────────────────────────────────────────────────────

def _rows():
    return {i: {"id": i, "title": f"Song {i}", "language": "ta"} for i in ("a", "b", "c")}


def test_document_carries_the_labels_most_fitting_first():
    doc = build_document(_rows(), {"a": ["sad", "romantic"], "b": ["happy"], "c": []})
    songs = {s["id"]: s for s in doc["songs"]}
    assert songs["a"]["moods"] == ["sad", "romantic"]
    assert songs["b"]["moods"] == ["happy"]
    assert "moods" not in songs["c"]                       # no label: no key (no empty lists sent)
    assert songs["a"]["language"] == "ta" and songs["a"]["languages"] == ["ta"]   # the other fields as before


def test_document_without_labels_is_as_before():
    assert all("moods" not in s for s in build_document(_rows())["songs"])


def _catalog(tmp_path):
    db = str(tmp_path / "catalog.db")
    store.init_db(db)
    with store.connect(db) as c:
        c.execute("INSERT INTO songs (id, title, language) VALUES ('x', 'X', 'ta')")
        c.execute("INSERT INTO songs (id, title, language) VALUES ('y', 'Y', 'en')")
    return db


def test_catalog_index_reads_the_labels_and_a_new_label_changes_the_etag(tmp_path):
    db = _catalog(tmp_path)
    idx = CatalogIndex(db)
    body1, etag1 = idx.get()
    assert b'"moods"' not in body1
    (tmp_path / "mood_tags.json").write_text(json.dumps({"x": ["calm"]}))
    body2, etag2 = idx.get()
    assert etag2 != etag1
    songs = {s["id"]: s for s in json.loads(body2)["songs"]}
    assert songs["x"]["moods"] == ["calm"] and "moods" not in songs["y"]


def test_catalog_route_returns_moods(client, tmp_path, monkeypatch):
    import navivibe.server as srv
    db = _catalog(tmp_path)
    (tmp_path / "mood_tags.json").write_text(json.dumps({"x": ["sad", "romantic"]}))
    monkeypatch.setattr(srv, "_catalog_index", CatalogIndex(db))
    r = client.get("/catalog/songs", headers=H)
    assert r.status_code == 200
    songs = {s["id"]: s for s in r.get_json()["songs"]}
    assert songs["x"]["moods"] == ["sad", "romantic"] and songs["x"]["language"] == "ta"
    assert client.get("/catalog/songs", headers={**H, "If-None-Match": r.headers["ETag"]}).status_code == 304


# ── "Not this mood" ──────────────────────────────────────────────────────────

def test_override_beats_the_label_for_that_listener_only():
    labels = {"s1": ["sad", "romantic"], "s2": ["sad"]}
    assert mood_overrides.add("me", "s1", "sad") == ["sad"]
    assert mood_overrides.add("me", "s1", "sad") == ["sad"]                  # twice is once
    mine = mood_overrides.for_user("me", labels)
    assert mine["s1"] == ["romantic"] and mine["s2"] == ["sad"]
    assert labels["s1"] == ["sad", "romantic"]                              # the shared labels are untouched
    assert mood_overrides.for_user("you", labels)["s1"] == ["sad", "romantic"]
    assert mood_overrides.disputed("me", "sad") == {"s1"}
    assert mood_overrides.remove("me", "s1", "sad") == []
    assert mood_overrides.for_user("me", labels)["s1"] == ["sad", "romantic"]
    assert mood_overrides.load("me") == {}


def test_a_damaged_or_odd_file_is_ignored(tmp_path):
    import os
    os.makedirs(mood_overrides.DIR, exist_ok=True)
    with open(mood_overrides._path("me"), "w") as f:
        f.write("{not json")
    assert mood_overrides.load("me") == {}
    with open(mood_overrides._path("me"), "w") as f:
        json.dump({"ok1": ["sad", "spicy"], "../x": ["sad"], "ok2": "sad"}, f)
    assert mood_overrides.load("me") == {"ok1": ["sad"]}


def test_override_routes(client):
    assert client.get("/moods/overrides").status_code == 401
    assert client.post("/moods/not-this", json={"song_id": "n0", "mood": "calm"}).status_code == 401
    r = client.post("/moods/not-this", json={"song_id": "n0", "mood": "Calm"}, headers=H)
    assert r.status_code == 200
    assert r.get_json() == {"ok": True, "song_id": "n0", "not": ["calm"], "moods": []}
    assert client.get("/moods/overrides", headers=H).get_json() == {"overrides": {"n0": ["calm"]}}
    assert client.get("/moods/overrides", headers=_basic("other")).get_json() == {"overrides": {}}
    assert client.post("/moods/not-this", json={"song_id": "n0", "mood": "spicy"}, headers=H).status_code == 400
    assert client.post("/moods/not-this", json={"song_id": "../../x", "mood": "sad"}, headers=H).status_code == 400
    r = client.delete("/moods/not-this", query_string={"song_id": "n0", "mood": "calm"}, headers=H)
    assert r.status_code == 200 and r.get_json()["moods"] == ["calm"]
    assert client.get("/moods/overrides", headers=H).get_json() == {"overrides": {}}


def test_a_mood_flow_leaves_out_what_the_listener_said_is_not_that_mood(client):
    def calm_ids():
        out = set()
        for _ in range(3):
            body = client.post("/flow/next", json={"count": 20, "mood": "calm"}, headers=H).get_json()
            out |= {i["navidrome_id"] for i in body["items"]}
        return out

    assert "n0" in calm_ids() or "n1" in calm_ids()                          # calm songs come before
    for s in ("n0", "n1"):
        client.post("/moods/not-this", json={"song_id": s, "mood": "calm"}, headers=H)
    assert not calm_ids() & {"n0", "n1"}
    # The sound-based gym chip honours it too.
    mood_overrides.add("me", "n2", "gym")
    assert "n2" in mood_overrides.disputed("me", "gym")


def test_taste_reads_the_listener_labels(client):
    mood_overrides.add("me", "n3", "calm")
    _, _, _, moods, _ = discover.user_context(client.engine, "me")
    assert moods["n3"] == [] and moods["n4"] == ["calm"]


# ── what the labeller reads ──────────────────────────────────────────────────

VERSE = ["Walking down the empty road tonight", "Every window dark, every door shut tight",
         "I keep your letters folded in my coat", "Reading every line you ever wrote"]
CHORUS = ["Oh you're gone, you're gone", "And the night goes on and on", "Oh you're gone, you're gone",
          "I'm still singing our old song"]
VERSE2 = ["Morning comes but it is grey and slow", "Nowhere left that I still want to go",
          "Coffee cold beside the telephone", "Learning how to be alone"]


def _song(*stanzas):
    return "\n\n".join("\n".join(s) for s in stanzas)


def test_excerpt_is_the_first_verse_plus_the_chorus():
    text = _song(VERSE, CHORUS, VERSE2, CHORUS, CHORUS)
    out = mood_lyrics.lyrics_excerpt(text, 800)
    verse_part, chorus_part = out.split(" // chorus: ")
    assert verse_part.startswith("Walking down the empty road tonight / Every window dark")
    assert "Reading every line you ever wrote" in verse_part
    assert chorus_part == " / ".join(CHORUS)
    assert out.count("Oh you're gone") == 2                             # the chorus once, not three times
    assert len(out) <= 800


def test_excerpt_is_much_longer_than_the_old_220_characters():
    text = _song(VERSE, CHORUS, VERSE2, VERSE, CHORUS)
    out = mood_lyrics.lyrics_excerpt(text, 800)
    assert 600 <= len(out) <= 800 or "Learning how to be alone" in out   # short verse: more of the song follows
    assert len(out) > 220


def test_excerpt_reads_marked_choruses_and_synced_lyrics():
    lrc = "\n".join(f"[00:{i:02d}.10] {line}" for i, line in enumerate(VERSE))
    text = lrc + "\n\n[Chorus]\n" + "\n".join(CHORUS[:2]) + "\n\n" + "\n".join(VERSE2)
    out = mood_lyrics.lyrics_excerpt(text, 800)
    assert "[00:" not in out
    assert out.split(" // chorus: ")[1] == " / ".join(CHORUS[:2])


def test_excerpt_without_blank_lines_and_limits():
    one_block = "\n".join(VERSE + CHORUS + VERSE2 + CHORUS)
    out = mood_lyrics.lyrics_excerpt(one_block, 800)
    assert out.startswith(VERSE[0]) and " // chorus: " in out
    long = _song([("la " * 200).strip()], CHORUS, CHORUS)
    assert len(mood_lyrics.lyrics_excerpt(long, 300)) <= 301
    assert mood_lyrics.lyrics_excerpt("", 800) == "" and mood_lyrics.lyrics_excerpt("...\n\n♪", 800) == ""


def test_evidence_sends_verse_and_chorus(tmp_path):
    db = str(tmp_path / "catalog.db")
    store.init_db(db)
    with store.connect(db) as c:
        c.execute("INSERT INTO source_raw (song_id, source, ok, fetched_at, payload) VALUES (?, 'lrclib', 1, 'now', ?)",
                  ("s", json.dumps({"text": _song(VERSE, CHORUS, VERSE2, CHORUS)})))
    lyrics = mood_tags.evidence(["s"], db)["s"]["lyrics"]
    assert len(lyrics) > 220 and " // chorus: " in lyrics and lyrics.endswith(CHORUS[-1])


class _Post:
    def __init__(self):
        self.calls = []

    def __call__(self, url, json=None, headers=None, timeout=None):
        self.calls.append(json)
        n = len(json and __import__("json").loads(json["messages"][1]["content"])["songs"])
        answer = {"songs": [{"n": k, "moods": ["happy"]} for k in range(1, n + 1)]}

        class R:
            def raise_for_status(self):
                pass

            def json(self):
                return {"choices": [{"message": {"tool_calls": [{"function": {"arguments": __import__("json").dumps(answer)}}]}}]}
        return R()


def _r(sid, lang):
    return {"id": sid, "title": sid, "artist": "A", "language": lang}


def test_english_songs_batch_together_under_their_own_prompt(tmp_path, monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "k")
    monkeypatch.setattr(mood_tags, "BATCH", 2)
    rows = [_r("e1", "en"), _r("t1", "ta"), _r("e2", "en"), _r("t2", "ta")]
    post = _Post()
    res = mood_tags.label_missing(rows, {}, post=post, sleep=lambda s: None, path=str(tmp_path / "m.json"),
                                  load_evidence=lambda ids: {})
    assert res["labelled"] == 4
    systems = [c["messages"][0]["content"] for c in post.calls]
    sent = [[s["title"] for s in json.loads(c["messages"][1]["content"])["songs"]] for c in post.calls]
    assert sent == [["t1", "t2"], ["e1", "e2"]]
    assert systems[0] == mood_tags.SYSTEM and systems[1] == mood_lyrics.SYSTEM_EN
    assert mood_lyrics.system_for([_r("a", "en"), _r("b", "ta")], "X") == "X"     # a mixed batch: the general prompt


def test_the_relabel_uses_the_same_prompt_choice():
    seen = []

    def ask(batch, ev):
        seen.append([r["id"] for r in batch])
        return {"songs": [{"n": k, "moods": ["calm"]} for k in range(1, len(batch) + 1)]}

    rows = {s: {**_r(s, lang), "energy": 0.3} for s, lang in (("e1", "en"), ("t1", "ta"))}
    out = mood_audit.relabel(["e1", "t1"], rows, {}, {}, {}, ask, sleep=lambda s: None)
    assert seen[0] == ["t1", "e1"] and {p["id"] for p in out} == {"e1", "t1"}
