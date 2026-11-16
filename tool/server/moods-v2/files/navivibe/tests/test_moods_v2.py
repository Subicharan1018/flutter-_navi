"""moods-v2: evidence rules over the labeller's labels, admin labels that beat it (and survive a
relabel), the labeller's confidence, and the mood editor's page and API.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_moods_v2.py -q
"""

import json

import pytest

from navivibe import mood_editor, mood_overrides
from navivibe.catalog import mood_audit, mood_eval, mood_quality, mood_tags
from navivibe.catalog.api import CatalogIndex
from navivibe.tests.test_listen_routes import H, _basic, client  # noqa: F401  (the route fixture)


def _facts(**kw):
    base = {"energy": 0.6, "valence": 0.5, "bpm": 100, "audio": {"sad": 0.3, "happy": 0.3, "relaxed": 0.5,
            "aggressive": 0.2}, "has_lyrics": True, "sad_words": 0, "anger_words": 0,
            "devotional_lyrics": False, "devotional_title": False, "devotional_other": False}
    audio = kw.pop("audio", {})
    return {**base, **kw, "audio": {**base["audio"], **audio}}


# ── the rules ────────────────────────────────────────────────────────────────

def test_sad_on_a_bright_happy_sounding_song_is_dropped_unless_the_lyrics_say_sad():
    bright = _facts(valence=0.83, energy=0.89, audio={"happy": 0.7, "sad": 0.12})
    assert mood_quality.sanity(["sad", "romantic"], bright) == ["romantic"]          # "Stole My Heart"
    assert mood_quality.sanity(["sad"], _facts(**{**bright, "sad_words": 2})) == ["sad"]
    assert mood_quality.sanity(["sad"], _facts(valence=0.2, audio={"sad": 0.6})) == ["sad"]  # a sad-sounding sad song


def test_without_lyrics_the_sound_must_be_clearly_happy():
    f = _facts(has_lyrics=False, valence=0.65, audio={"happy": 0.5, "sad": 0.25})   # gap 0.25 < 0.3
    assert mood_quality.sanity(["sad"], f) == ["sad"]
    assert mood_quality.sanity(["sad"], _facts(**{**f, "audio": {"happy": 0.6, "sad": 0.2}})) == []


def test_angry_needs_an_angry_sound_or_angry_words():
    gentle = _facts(valence=0.71, audio={"aggressive": 0.19})                        # "Pudikale Pudikudhu"
    assert mood_quality.sanity(["angry"], gentle) == []                              # nothing rather than wrong
    assert mood_quality.sanity(["angry"], _facts(**{**gentle, "anger_words": 1})) == ["angry"]
    assert mood_quality.sanity(["angry"], _facts(valence=0.55, audio={"aggressive": 0.48})) == ["angry"]


def test_calm_is_not_fast_and_loud_and_energetic_is_never_dropped_by_sound():
    assert mood_quality.sanity(["calm"], _facts(energy=0.67, bpm=152, audio={"relaxed": 0.67})) == []
    assert mood_quality.sanity(["calm"], _facts(energy=0.8)) == []
    assert mood_quality.sanity(["calm"], _facts(energy=0.5, bpm=164, audio={"relaxed": 0.95})) == ["calm"]
    assert mood_quality.sanity(["energetic"], _facts(energy=0.3)) == ["energetic"]


def test_devotional_from_the_title_alone_is_dropped():
    f = _facts(devotional_title=True)                                                # "Tujh Mein Rab Dikhta Hai"
    assert mood_quality.sanity(["devotional", "calm"], f) == ["calm"]
    assert mood_quality.sanity(["devotional"], _facts(devotional_title=True, devotional_lyrics=True)) == ["devotional"]
    assert mood_quality.sanity(["devotional"], _facts(devotional_title=True, has_lyrics=False)) == ["devotional"]


def test_an_unsure_labeller_means_no_label_and_no_facts_change_nothing():
    assert mood_quality.sanity(["happy"], None, {"c": 0.3}) == []
    assert mood_quality.sanity(["happy"], None, {"c": 0.8}) == ["happy"]
    assert mood_quality.sanity(["sad", "romantic", "calm"], None) == ["sad", "romantic"]
    assert mood_quality.explain(["happy"], None, {"c": 0.3}) == [("happy", "labeller unsure (0.30)")]


def test_facts_read_lyric_words():
    f = mood_quality.song_facts({"energy": 0.5, "title": "Swamiye Saranam"},
                                {"lyrics": "kanneer / I cry alone / ரத்தம்", "audio_mood": {"sad": 0.4}})
    assert f["sad_words"] >= 3 and f["anger_words"] == 1 and f["devotional_title"] and f["audio"]["sad"] == 0.4


def test_eval_scores_first_labels():
    ref = {"a": {"title": "A", "ok": ["sad"]}, "b": {"title": "B", "ok": ["happy"]}, "c": {"title": "C", "ok": ["calm"]}}
    s = mood_eval.score({"a": ["sad"], "b": ["sad", "happy"]}, ref)
    assert (s["right"], s["wrong"], s["unlabelled"], s["precision"]) == (1, 1, 1, 0.5)
    assert len(mood_eval.load_reference()) >= 40


# ── admin labels, confidence, effective labels ──────────────────────────────

@pytest.fixture
def labels(tmp_path, monkeypatch):
    p = tmp_path / "mood_tags.json"
    p.write_text(json.dumps({"a": ["sad", "romantic"], "b": ["angry"], "c": ["calm"]}))
    monkeypatch.setattr(mood_tags, "PATH", str(p))
    return p


def test_an_admin_label_beats_the_labeller_and_the_rules(labels, monkeypatch):
    monkeypatch.setattr(mood_quality, "facts", lambda: {"b": _facts(valence=0.8, audio={"aggressive": 0.1})})
    assert mood_tags.load()["b"] == []                                              # ruled out
    mood_quality.set_admin("b", ["angry"], "boss")
    mood_quality.set_admin("c", [], "boss")                                         # "no mood" on purpose
    eff = mood_tags.load()
    assert eff["b"] == ["angry"] and eff["c"] == [] and eff["a"] == ["sad", "romantic"]
    assert mood_tags.load_raw()["c"] == ["calm"]                                    # the labeller's file is untouched
    e = mood_quality.load_admin()["b"]
    assert e["by"] == "boss" and e["at"].endswith("Z")
    assert mood_quality.clear_admin("b") and mood_tags.load()["b"] == []
    assert not mood_quality.clear_admin("b")


def test_admin_moods_are_validated():
    assert mood_quality.clean_moods(["Sad", "gym"]) == ["sad", "gym"]
    assert mood_quality.clean_moods([]) == []
    for bad in (["sad", "sad"], ["sad", "happy", "calm"], ["spicy"], "sad", None, [3]):
        assert mood_quality.clean_moods(bad) is None


def test_a_relabel_never_overwrites_an_admin_label(labels):
    mood_quality.set_admin("a", ["romantic"], "boss")
    res = mood_audit.apply([{"id": "a", "new": ["happy"], "changed": True, "still_suspect": False},
                            {"id": "c", "new": ["sad"], "changed": True, "still_suspect": False,
                             "meta": {"c": 0.9, "b": "lyrics"}}], path=str(labels))
    raw = mood_tags.load_raw()
    assert raw["a"] == ["sad", "romantic"] and raw["c"] == ["sad"] and res["written"] == 1
    assert mood_quality.load_meta()["c"] == {"c": 0.9, "b": "lyrics"}
    assert mood_tags.load()["a"] == ["romantic"]


class _Post:
    def __init__(self, answer):
        self.answer, self.calls = answer, []

    def __call__(self, url, json=None, headers=None, timeout=None):
        self.calls.append(json)
        ans = self.answer

        class R:
            def raise_for_status(self):
                pass

            def json(self):
                return {"choices": [{"message": {"tool_calls": [{"function": {"arguments": __import__("json").dumps(ans)}}]}}]}
        return R()


def test_labelling_skips_admin_songs_records_confidence_and_drops_unsure_labels(tmp_path, monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "k")
    path = str(tmp_path / "mood_tags.json")
    monkeypatch.setattr(mood_tags, "PATH", path)
    mood_quality.set_admin("x0", ["happy"], "boss")
    rows = [{"id": f"x{i}", "title": f"S{i}", "language": "ta"} for i in range(3)]
    post = _Post({"songs": [{"n": 1, "moods": ["sad"], "confidence": 0.9, "basis": "lyrics"},
                            {"n": 2, "moods": ["calm"], "confidence": 0.2, "basis": "sound"}]})
    mood_tags.label_missing(rows, {}, post=post, sleep=lambda s: None, path=path, load_evidence=lambda ids: {})
    sent = json.loads(post.calls[0]["messages"][1]["content"])["songs"]
    assert [s["title"] for s in sent] == ["S1", "S2"]                              # the admin's song isn't asked
    assert "confidence" in json.dumps(post.calls[0]["tools"]) and "Rules:" in post.calls[0]["messages"][0]["content"]
    assert mood_quality.load_meta() == {"x1": {"c": 0.9, "b": "lyrics"}, "x2": {"c": 0.2, "b": "sound"}}
    eff = mood_tags.load()
    assert eff["x1"] == ["sad"] and eff["x2"] == [] and eff["x0"] == ["happy"]


def test_an_admin_gym_label_fits_the_gym_chip():
    assert mood_tags.gym_fit({"energy": 0.2}, ["gym"])
    assert mood_tags.flow_fit({"energy": 0.2}, ["gym"], "gym")


def test_the_catalog_shows_admin_labels_and_its_etag_follows_them(tmp_path):
    from navivibe.catalog import store
    db = str(tmp_path / "catalog.db")
    store.init_db(db)
    with store.connect(db) as c:
        c.execute("INSERT INTO songs (id, title, language) VALUES ('x', 'X', 'ta')")
    (tmp_path / "mood_tags.json").write_text(json.dumps({"x": ["calm"]}))
    idx = CatalogIndex(db)
    _, etag1 = idx.get()
    mood_quality.set_admin("x", ["happy", "energetic"], "boss", path=str(tmp_path / "mood_tags.json"))
    body, etag2 = idx.get()
    assert etag2 != etag1 and json.loads(body)["songs"][0]["moods"] == ["happy", "energetic"]


# ── the mood editor ──────────────────────────────────────────────────────────

LIB = {f"s{i:02d}": {"title": f"Song {i:02d}", "artist": "Anirudh" if i % 2 else "Rahman", "album": "Leo",
                     "film": "Leo", "language": "ta"} for i in range(60)}


@pytest.fixture
def editor(client, tmp_path, monkeypatch):
    import navivibe.server as srv
    p = tmp_path / "mood_tags.json"
    p.write_text(json.dumps({"s00": ["sad"], "s01": ["happy", "energetic"], "s02": ["angry"]}))
    monkeypatch.setattr(mood_tags, "PATH", str(p))
    monkeypatch.setattr(mood_editor, "library", lambda: LIB)
    monkeypatch.setattr(mood_quality, "facts", lambda: {"s02": _facts(valence=0.8, audio={"aggressive": 0.1})})
    monkeypatch.setattr(srv, "ADMIN_USERS", {"boss"})
    return client


BOSS = _basic("boss")


def test_the_page_is_public_html_with_its_own_policy(editor):
    r = editor.get("/moods/editor")
    assert r.status_code == 200 and r.mimetype == "text/html" and b"Song Moods" in r.data
    csp = r.headers["Content-Security-Policy"]
    assert "script-src 'self'" in csp and "frame-ancestors 'none'" in csp and "unsafe-inline" not in csp
    assert editor.get("/moods/editor/app.js").mimetype == "text/javascript"
    assert editor.get("/moods/editor/app.css").status_code == 200
    assert editor.get("/moods/editor/../server.py").status_code == 404
    assert editor.get("/moods/editor/secret.py").status_code == 404
    assert editor.get("/flow/moods", headers=H).headers["Content-Security-Policy"].startswith("default-src 'none'")


def test_the_list_needs_a_login_and_pages(editor):
    assert editor.get("/moods/songs").status_code == 401
    b = editor.get("/moods/songs?limit=25", headers=H).get_json()
    assert b["total"] == 60 and len(b["items"]) == 25 and b["next_offset"] == 25 and b["is_admin"] is False
    last = editor.get("/moods/songs?offset=50&limit=25", headers=H).get_json()
    assert len(last["items"]) == 10 and last["next_offset"] is None
    ids = [i["id"] for i in b["items"]] + [i["id"] for i in editor.get("/moods/songs?offset=25&limit=25", headers=H).get_json()["items"]]
    assert len(set(ids)) == 50                                                      # no repeats across pages
    assert editor.get("/moods/songs?limit=500", headers=H).get_json()["items"].__len__() == 60  # capped at 100
    assert editor.get("/moods/songs?offset=x", headers=H).status_code == 400


def test_search_and_filters(editor):
    q = editor.get("/moods/songs?q=song 0", headers=H).get_json()
    assert q["total"] == 10
    assert editor.get("/moods/songs?q=rahman&limit=100", headers=H).get_json()["total"] == 30
    sad = editor.get("/moods/songs?mood=sad", headers=H).get_json()["items"]
    assert [i["id"] for i in sad] == ["s00"] and sad[0]["source"] == "llm"
    assert editor.get("/moods/songs?mood=energetic", headers=H).get_json()["total"] == 1   # any label counts
    none = editor.get("/moods/songs?mood=none&limit=100", headers=H).get_json()
    assert none["total"] == 58 and "s02" in {i["id"] for i in none["items"]}        # ruled out: no mood
    flagged = editor.get("/moods/songs?filter=flagged", headers=H).get_json()["items"]
    assert [i["id"] for i in flagged] == ["s02"] and flagged[0]["llm"] == ["angry"] and flagged[0]["flags"]
    assert editor.get("/moods/songs?mood=spicy", headers=H).status_code == 400
    assert editor.get("/moods/songs?filter=odd", headers=H).status_code == 400


def test_an_admin_sets_moods_for_everyone(editor):
    r = editor.put("/moods/songs/s00", json={"moods": ["romantic", "calm"]}, headers=BOSS)
    assert r.status_code == 200
    song = r.get_json()["song"]
    assert song["moods"] == ["romantic", "calm"] and song["source"] == "admin" and song["by"] == "boss"
    # everyone sees it: the list, the catalog labels, a mood Flow's labels
    mine = editor.get("/moods/songs?filter=admin", headers=H).get_json()["items"]
    assert [i["id"] for i in mine] == ["s00"] and mine[0]["moods"] == ["romantic", "calm"]
    assert mood_tags.load()["s00"] == ["romantic", "calm"]
    assert editor.get("/moods/me", headers=BOSS).get_json() == {"username": "boss", "is_admin": True}
    r = editor.delete("/moods/songs/s00", headers=BOSS)
    assert r.status_code == 200 and r.get_json()["song"]["moods"] == ["sad"] and r.get_json()["song"]["source"] == "llm"


def test_only_an_admin_can_change_moods_for_everyone(editor):
    assert editor.put("/moods/songs/s00", json={"moods": ["happy"]}, headers=H).status_code == 403
    assert editor.delete("/moods/songs/s00", headers=H).status_code == 403
    assert editor.put("/moods/songs/s00", json={"moods": ["happy"]}).status_code == 401
    assert mood_quality.load_admin() == {}
    # a listener's own "Not this mood" shows in their list only
    editor.post("/moods/not-this", json={"song_id": "s00", "mood": "sad"}, headers=H)
    assert editor.get("/moods/songs?q=song 00", headers=H).get_json()["items"][0]["not"] == ["sad"]
    assert editor.get("/moods/songs?q=song 00", headers=BOSS).get_json()["items"][0]["not"] == []


def test_admin_input_is_validated(editor):
    for body in ({"moods": ["sad", "happy", "calm"]}, {"moods": ["sad", "sad"]}, {"moods": ["spicy"]},
                 {"moods": "sad"}, {}):
        assert editor.put("/moods/songs/s00", json=body, headers=BOSS).status_code == 400
    assert editor.put("/moods/songs/nope", json={"moods": ["sad"]}, headers=BOSS).status_code == 404
    assert editor.put("/moods/songs/s00", json={"moods": []}, headers=BOSS).get_json()["song"]["moods"] == []


def test_login_goes_through_navidrome_and_returns_only_a_token(editor, monkeypatch):
    seen = {}

    class R:
        def __init__(self, code, body):
            self.status_code, self._b, self.content = code, body, b"x"

        def json(self):
            return self._b

    def post(url, json=None, timeout=None):
        seen.update(url=url, body=json)
        return R(200, {"token": "jwt.abc", "username": "Boss"}) if json["password"] == "pw" else R(401, {})

    monkeypatch.setattr(mood_editor.requests, "post", post)
    r = editor.post("/moods/editor/login", json={"username": "boss", "password": "pw"})
    assert r.status_code == 200 and r.get_json() == {"token": "jwt.abc", "username": "Boss", "is_admin": True}
    assert seen["url"].endswith("/auth/login")
    assert editor.post("/moods/editor/login", json={"username": "boss", "password": "no"}).status_code == 401
    assert editor.post("/moods/editor/login", json={"username": "", "password": ""}).status_code == 400
