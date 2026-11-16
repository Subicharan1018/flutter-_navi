"""moods-v1: patch the shuffle server's mood code (see README.md).

Every patch is an exact text match: a file already patched is left alone, a file that
is not the version this package was built on stops the whole run before anything is
written.

usage: python patch_moods.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
exit 0: patched or already patched; exit 2: not the expected files (nothing written).
"""
import sys
from pathlib import Path

PATCHES = [
    # ── catalog/mood_tags.py: longer lyrics, English prompt, slower pace for the bigger batches
    ("catalog/mood_tags.py",
     "from navivibe.llm_client import call_tool\n",
     "from navivibe.llm_client import call_tool\n"
     "from navivibe.catalog.mood_lyrics import is_english, lyrics_excerpt, system_for  # moods-v1\n"),
    ("catalog/mood_tags.py",
     "PACE_S = 30.0                      # gpt-oss-120b free tier: ~8K tokens a minute; a batch with lyrics is ~4K\n",
     "PACE_S = 75.0                      # gpt-oss-120b free tier: ~8K tokens a minute; moods-v1 batches (verse + chorus) are ~8K\n"),
    ("catalog/mood_tags.py",
     "LYRICS_CHARS = 220\n",
     "LYRICS_CHARS = 800                 # moods-v1: the first verse plus the chorus (was 220: the opening lines)\n"),
    ("catalog/mood_tags.py",
     '                text = " / ".join(line.strip() for line in p["text"].splitlines() if line.strip() and line.strip() != "...")\n'
     '                out[sid]["lyrics"] = text[:LYRICS_CHARS]\n',
     '                out[sid]["lyrics"] = lyrics_excerpt(p["text"], LYRICS_CHARS)   # moods-v1: verse + chorus\n'),
    ("catalog/mood_tags.py",
     "    if limit:\n        todo = todo[:limit]\n",
     "    if limit:\n        todo = todo[:limit]\n"
     "    todo.sort(key=is_english)                     # moods-v1: English songs batch together, for their own prompt\n"),
    ("catalog/mood_tags.py",
     "        args = call_tool(base_url=BASE_URL, api_key=key, model=MODEL, system=SYSTEM,\n",
     "        args = call_tool(base_url=BASE_URL, api_key=key, model=MODEL, system=system_for(batch, SYSTEM),\n"),

    # ── catalog/mood_audit.py: the re-label uses the same prompt choice and batching
    ("catalog/mood_audit.py",
     "        return call_tool(base_url=mood_tags.BASE_URL, api_key=key, model=mood_tags.MODEL, system=mood_tags.SYSTEM,\n",
     "        return call_tool(base_url=mood_tags.BASE_URL, api_key=key, model=mood_tags.MODEL,\n"
     "                         system=mood_tags.system_for(batch, mood_tags.SYSTEM),       # moods-v1\n"),
    ("catalog/mood_audit.py",
     "    out = []\n    for i in range(0, len(ids), mood_tags.BATCH):\n",
     "    out = []\n"
     "    ids = sorted(ids, key=lambda s: mood_tags.is_english(rows[s]))    # moods-v1: English songs batch together\n"
     "    for i in range(0, len(ids), mood_tags.BATCH):\n"),

    # ── catalog/api.py: /catalog/songs carries each song's labels as "moods"
    ("catalog/api.py",
     "from navivibe.catalog import store\n",
     "from navivibe.catalog import mood_tags, store\n"),
    ("catalog/api.py",
     "def _song_entry(s: dict) -> dict:\n",
     "def _song_entry(s: dict, moods: list = None) -> dict:\n"),
    ("catalog/api.py",
     '    if s.get("bpm"):\n        e["bpm"] = int(round(s["bpm"]))\n',
     '    if moods:                                     # moods-v1: the LLM labels, most fitting first\n'
     '        e["moods"] = [m for m in moods if isinstance(m, str)][:2]\n'
     '    if s.get("bpm"):\n        e["bpm"] = int(round(s["bpm"]))\n'),
    ("catalog/api.py",
     "def build_document(rows: dict) -> dict:\n    songs = [_song_entry(s) for s in rows.values()]\n",
     "def build_document(rows: dict, labels: dict = None) -> dict:\n"
     "    labels = labels or {}\n"
     "    songs = [_song_entry(s, labels.get(s[\"id\"])) for s in rows.values()]\n"),
    ("catalog/api.py",
     "        self.path = path or store.CATALOG_DB\n",
     "        self.path = path or store.CATALOG_DB\n"
     "        self.moods_path = os.path.join(os.path.dirname(self.path), \"mood_tags.json\")   # moods-v1\n"),
    ("catalog/api.py",
     '        for p in (self.path, self.path + "-wal"):\n',
     '        for p in (self.path, self.path + "-wal", self.moods_path):   # moods-v1: new labels change the ETag\n'),
    ("catalog/api.py",
     "                doc = build_document(store.load_catalog(self.path))\n",
     "                doc = build_document(store.load_catalog(self.path), mood_tags.load(self.moods_path))\n"),

    # ── discover.py: a listener's "Not this mood" beats the label in their taste, Discover, Weekly mix and Flow
    ("discover.py",
     '    """(taste, events, meta, moods, emb) for `user`, shared by Discover, Weekly mix and Flow."""\n'
     "    now = now or time.time()\n"
     "    events = _all_events(engine, now)\n"
     "    meta, moods = engine.cat.meta, mood_tags.load()\n",
     '    """(taste, events, meta, moods, emb) for `user`, shared by Discover, Weekly mix and Flow."""\n'
     "    from navivibe import mood_overrides                 # moods-v1\n"
     "    now = now or time.time()\n"
     "    events = _all_events(engine, now)\n"
     "    meta, moods = engine.cat.meta, mood_overrides.for_user(user, mood_tags.load())\n"),

    # ── flow.py: a mood chip leaves out the songs the listener said are not that mood (also gym)
    ("flow.py",
     "from navivibe import discover, explore, flow_prefs, taste_exclusions\n",
     "from navivibe import discover, explore, flow_prefs, mood_overrides, taste_exclusions\n"),
    ("flow.py",
     "    if mood:\n"
     "        ids = [s for s in ids if mood_tags.flow_fit(meta.get(s) or {}, moods.get(s) or [], mood)]\n",
     "    if mood:\n"
     "        not_this = mood_overrides.disputed(user, mood)     # moods-v1: \"Not this mood\"\n"
     "        ids = [s for s in ids if s not in not_this\n"
     "               and mood_tags.flow_fit(meta.get(s) or {}, moods.get(s) or [], mood)]\n"),

    # ── server.py: the override routes
    ("server.py",
     '            "GET  /flow/moods":               "Mood chips Flow can use (auth required)",\n',
     '            "GET  /flow/moods":               "Mood chips Flow can use (auth required)",\n'
     '            "GET  /moods/overrides":          "Your Not this mood marks: {song_id: [moods]} (auth required)",\n'
     '            "POST/DELETE /moods/not-this":    "Not this mood {song_id, mood}; DELETE takes it back (auth required)",\n'),
    ("server.py",
     "\n\ndef _flow_prefs_json(user: str) -> dict:\n",
     '''

# moods-v1 ─ "Not this mood": per listener, beats the LLM label (navivibe/mood_overrides.py)
@app.route("/moods/overrides", methods=["GET"])
@require_auth
def mood_overrides_list():
    """The caller's "Not this mood" marks: {"overrides": {song_id: [moods]}}."""
    from navivibe import mood_overrides
    return jsonify({"overrides": mood_overrides.load(g.username)})


@app.route("/moods/not-this", methods=["POST", "DELETE"])
@require_auth
def mood_not_this():
    """Body (or query) {"song_id", "mood"}. POST marks the song "not this mood" for the caller;
    DELETE takes the mark back. Returns the song's labels as the caller now sees them."""
    from navivibe import mood_overrides
    from navivibe.catalog import mood_tags
    body = request.get_json(silent=True) or {}
    sid = str(body.get("song_id") or request.args.get("song_id") or "").strip()
    mood = str(body.get("mood") or request.args.get("mood") or "").strip().lower()
    if mood not in mood_tags.FLOW_MOODS:
        return jsonify({"error": f"mood must be one of: {', '.join(mood_tags.FLOW_MOODS)}"}), 400
    if not mood_overrides.valid_id(sid):
        return jsonify({"error": "song_id is missing or not a song id"}), 400
    if request.method == "DELETE":
        nots = mood_overrides.remove(g.username, sid, mood)
    else:
        nots = mood_overrides.add(g.username, sid, mood)
    labels = mood_tags.load().get(sid) or []
    return jsonify({"ok": True, "song_id": sid, "not": nots, "moods": [m for m in labels if m not in nots]})


def _flow_prefs_json(user: str) -> dict:
'''),

    # ── tests/conftest.py: tests never touch the real override files
    ("tests/conftest.py",
     '    from navivibe import flow_prefs\n'
     '    monkeypatch.setattr(flow_prefs, "DIR", str(tmp_path / "flow_prefs"))\n',
     '    from navivibe import flow_prefs\n'
     '    monkeypatch.setattr(flow_prefs, "DIR", str(tmp_path / "flow_prefs"))\n'
     '    from navivibe import mood_overrides                      # moods-v1\n'
     '    monkeypatch.setattr(mood_overrides, "DIR", str(tmp_path / "mood_overrides"))\n'),
]


def main(root: str) -> int:
    base = Path(root)
    texts = {}
    for rel, _, _ in PATCHES:
        p = base / rel
        if not p.exists():
            print(f"!! {p} not found")
            return 2
        texts.setdefault(rel, p.read_text(encoding="utf-8"))
    todo, bad = [], []
    for rel, old, new in PATCHES:
        text = texts[rel]
        if new in text:
            continue
        if text.count(old) != 1:
            bad.append(f"{rel}: expected text found {text.count(old)} times: {old.strip().splitlines()[0][:70]!r}")
            continue
        texts[rel] = text.replace(old, new)
        todo.append(rel)
    if bad:
        for b in bad:
            print("!! " + b)
        print("!! not the version this package was built on: nothing written")
        return 2
    for rel in dict.fromkeys(todo):
        (base / rel).write_text(texts[rel], encoding="utf-8")
    print(f"patched: {', '.join(dict.fromkeys(todo)) or 'nothing (already patched)'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
