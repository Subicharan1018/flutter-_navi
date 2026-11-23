"""moods-v3: patch the shuffle server's mood code (see README.md). Needs moods-v2 and exportify-v1.

Exact text matches; already patched files are left alone; anything unexpected stops the run before
anything is written.

usage: python patch_moods_v3.py <navivibe dir>
exit 0: patched or already patched; exit 2: not the expected files (nothing written).
"""
import sys
from pathlib import Path

Q = "catalog/mood_quality.py"
PATCHES = [
    (Q, "        **spotify_evidence.facts_for(row.get(\"id\")),   # exportify-v1: Spotify's valence / energy, when a CSV matched\n",
     "        **spotify_evidence.facts_for(row.get(\"id\")),   # exportify-v1: Spotify's valence / energy, when a CSV matched\n"
     "        \"v3\": _v3_features(row, ev),                    # moods-v3\n"),
    (Q, "def song_facts(row: dict, ev: dict = None) -> dict:\n",
     "def _v3_features(row: dict, ev: dict) -> dict:\n"
     "    \"\"\"What the moods-v3 rules look at (catalog/mood_fusion.py).\"\"\"\n"
     "    from navivibe import spotify_details\n"
     "    from navivibe.catalog import mood_fusion\n"
     "    return mood_fusion.features(row, ev, spotify_details.get(row[\"id\"]) if row.get(\"id\") else None,\n"
     "                                _SAD_WORDS, _ANGER_WORDS, _devotional())\n"
     "\n\n"
     "def song_facts(row: dict, ev: dict = None) -> dict:\n"),
    (Q, "    out = []\n    if meta and isinstance(meta.get(\"c\"), (int, float)) and meta[\"c\"] < MIN_CONFIDENCE:\n        return [(m, f\"labeller unsure",
     "    out = []\n"
     "    if rules_in_use() == 3 and facts and facts.get(\"v3\"):            # moods-v3\n"
     "        from navivibe.catalog import mood_fusion\n"
     "        return mood_fusion.decide(tags or [], facts[\"v3\"], meta)[\"dropped\"]\n"
     "    if meta and isinstance(meta.get(\"c\"), (int, float)) and meta[\"c\"] < MIN_CONFIDENCE:\n        return [(m, f\"labeller unsure"),
    (Q, "def meta_path(path: str = None) -> str:\n",
     "def rules_path(path: str = None) -> str:\n"
     "    \"\"\"moods-v3: the switch file; {\"rules\": 3} turns the v3 rules on (mood_relabel --write).\"\"\"\n"
     "    return os.path.join(_dir(path), \"mood_rules.json\")\n"
     "\n\n"
     "def rules_in_use(path: str = None) -> int:\n"
     "    return 3 if _read(rules_path(path)).get(\"rules\") == 3 else 2\n"
     "\n\n"
     "def meta_path(path: str = None) -> str:\n"),
    (Q, "def facts_version() -> int:\n    return id(_facts.data)\n",
     "def facts_version():\n"
     "    return id(_facts.data), _mtime(rules_path())                      # moods-v3: the switch changes the labels\n"),
    (Q, "    out = {sid: sanity(tags or [], fx.get(sid), meta.get(sid)) for sid, tags in raw.items()}\n",
     "    if rules_in_use(path) == 3:                                       # moods-v3\n"
     "        from navivibe.catalog import mood_fusion\n"
     "        out = {sid: (mood_fusion.decide(tags or [], fx[sid][\"v3\"], meta.get(sid))[\"moods\"]\n"
     "                     if (fx.get(sid) or {}).get(\"v3\") else sanity(tags or [], fx.get(sid), meta.get(sid)))\n"
     "               for sid, tags in raw.items()}\n"
     "    else:\n"
     "        out = {sid: sanity(tags or [], fx.get(sid), meta.get(sid)) for sid, tags in raw.items()}\n"),
    (Q, "    key = (p, _mtime(p), _mtime(admin_path(p)), _mtime(meta_path(p)), id(fx))\n",
     "    key = (p, _mtime(p), _mtime(admin_path(p)), _mtime(meta_path(p)), _mtime(rules_path(p)), id(fx))   # moods-v3: the switch\n"),
    # The cause upstream: the labeller was never told the genre, nor the danceability.
    ("catalog/mood_tags.py",
     "\"energy\": _num(r.get(\"energy\")), **ev.get(r.get(\"id\"), {})}\n",
     "\"energy\": _num(r.get(\"energy\")), \"danceability\": _num(r.get(\"danceability\")),\n"
     "         \"genre\": r.get(\"genre_primary\") or r.get(\"genre_display\"), **ev.get(r.get(\"id\"), {})}   # moods-v3: genre, danceability\n"),
    # Labels the sound contradicts and the current prompt never rated can be asked again (relabel_moods.sh).
    ("catalog/mood_audit.py",
     "        why = check(row, labels.get(sid) or [], ev.get(sid))\n",
     "        why = check(row, labels.get(sid) or [], ev.get(sid)) + _v3_conflict(sid, labels.get(sid) or [])   # moods-v3\n"),
    ("catalog/mood_audit.py",
     "def audit(rows: dict, labels: dict, ev: dict) -> dict:\n",
     "def _v3_conflict(sid: str, tags: list) -> list:\n"
     "    \"\"\"moods-v3: the sound or tags contradict a label the rated prompt never gave.\"\"\"\n"
     "    from navivibe.catalog import mood_fusion, mood_quality\n"
     "    f = (mood_quality.facts().get(sid) or {}).get(\"v3\")\n"
     "    if not f or sid in mood_quality.load_meta():\n"
     "        return []\n"
     "    return [\"v3_conflict\"] if any(mood_fusion.conflict(m, f) for m in tags[:2]) else []\n"
     "\n\n"
     "def audit(rows: dict, labels: dict, ev: dict) -> dict:\n"),
    ("catalog/mood_audit.py",
     "           \"score_vocal_mood\", \"unlabelled\", \"no_evidence\"]\n",
     "           \"score_vocal_mood\", \"unlabelled\", \"no_evidence\", \"v3_conflict\"]\n"),
]


def main(root: str) -> int:
    base, texts = Path(root), {}
    for rel, _, _ in PATCHES:
        p = base / rel
        if not p.exists():
            print(f"!! {p} not found")
            return 2
        texts.setdefault(rel, p.read_text(encoding="utf-8"))
    todo, bad = [], []
    for rel, old, new in PATCHES:
        if new in texts[rel]:
            continue
        if texts[rel].count(old) != 1:
            bad.append(f"{rel}: expected text found {texts[rel].count(old)} times: {old.strip().splitlines()[0][:70]!r}")
            continue
        texts[rel] = texts[rel].replace(old, new)
        todo.append(rel)
    if bad:
        for b in bad:
            print("!! " + b)
        print("!! not the version this package was built on (needs moods-v2 and exportify-v1): nothing written")
        return 2
    for rel in dict.fromkeys(todo):
        (base / rel).write_text(texts[rel], encoding="utf-8", newline="\n")
    print(f"patched: {', '.join(dict.fromkeys(todo)) or 'nothing (already patched)'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
