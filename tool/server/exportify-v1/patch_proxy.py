"""exportify-v1: patch the shuffle server so it forwards /exportify/* to tg-fetcher.

  server.py      registers navivibe/exportify_proxy.py and allows a 12 MB body on /exportify
  hardening.py   /exportify counts as the "fetch" route class (same rate limits as /fetch)
  catalog/mood_quality.py  Spotify's valence / energy as a second opinion for the mood rules (needs moods-v2)
  catalog/api.py           optional extra keys in GET /catalog/songs (pop, released, sp_genres, label; year where missing)

Every patch is an exact text match: a file already patched is left alone, a file that is not
the version this package was built on stops the run before anything is written.

usage: python patch_proxy.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

PATCHES = [   # (file, old (exactly once), new)
    ("server.py",
     '    ("/fetch", 16 * 1024),\n',
     '    ("/fetch", 16 * 1024),\n'
     '    ("/exportify", 12 * 1024 * 1024),        # exportify-v1: an Exportify CSV (JSON-wrapped)\n'),
    ("server.py",
     "register_pair_routes(app, require_auth)\n",
     "register_pair_routes(app, require_auth)\n"
     "\n"
     "# exportify-v1: Import a Spotify playlist from an Exportify CSV (navivibe/exportify_proxy.py)\n"
     "from navivibe.exportify_proxy import register_exportify_routes  # noqa: E402\n"
     "register_exportify_routes(app, require_auth)\n"),
    ("hardening.py",
     '    if path.startswith("/fetch"):\n',
     '    if path.startswith("/fetch") or path.startswith("/exportify"):      # exportify-v1\n'),
    # Spotify's valence / energy as a second opinion for the mood rules (needs moods-v2).
    ("catalog/mood_quality.py",
     '    dev = _devotional()\n    return {\n        "energy": row.get("energy"),\n',
     '    dev = _devotional()\n    from navivibe.catalog import spotify_evidence   # exportify-v1\n    return {\n'
     '        **spotify_evidence.facts_for(row.get("id")),   # exportify-v1: Spotify\'s valence / energy, when a CSV matched\n'
     '        "energy": row.get("energy"),\n'),
    ("catalog/mood_quality.py",
     'def ruled_out(mood: str, f: dict) -> str | None:\n'
     '    """Why the evidence rules this mood out for the song (None: it doesn\'t)."""\n',
     'def ruled_out(mood: str, f: dict) -> str | None:\n'
     '    """Why the evidence rules this mood out for the song (None: it doesn\'t). exportify-v1: Spotify\'s\n'
     '    numbers are a second opinion (catalog/spotify_evidence.py)."""\n'
     '    from navivibe.catalog import spotify_evidence\n'
     '    return spotify_evidence.second_opinion(mood, f, _ruled_out)\n\n\n'
     'def _ruled_out(mood: str, f: dict) -> str | None:\n'
     '    """The moods-v2 evidence rules."""\n'),
    ("catalog/mood_quality.py",
     '        from navivibe.catalog import store\n        out = []\n        for p in (store.CATALOG_DB, store.CATALOG_DB + "-wal"):\n',
     '        from navivibe import spotify_details    # exportify-v1: a new import changes the facts\n'
     '        from navivibe.catalog import store\n        out = []\n'
     '        for p in (store.CATALOG_DB, store.CATALOG_DB + "-wal", spotify_details.PATH):\n'),
    # Optional extra keys in GET /catalog/songs (nothing renamed).
    ("catalog/api.py",
     '    if s.get("bpm"):\n        e["bpm"] = int(round(s["bpm"]))\n',
     '    from navivibe import spotify_details   # exportify-v1: pop, released, sp_genres, label; year where missing\n'
     '    spotify_details.extend_entry(e, s)\n'
     '    if s.get("bpm"):\n        e["bpm"] = int(round(s["bpm"]))\n'),
    ("catalog/api.py",
     '    def _mtime(self):\n        stamp = []\n',
     '    def _mtime(self):\n        from navivibe import spotify_details   # exportify-v1\n        stamp = []\n'),
    ("catalog/api.py",
     '        return tuple(stamp) + (mood_quality.facts_version(),)        # moods-v2\n',
     '        return tuple(stamp) + (mood_quality.facts_version(), spotify_details.stamp())        # moods-v2, exportify-v1\n'),
]


def main(root: str) -> int:
    base = Path(root)
    texts, done = {}, []
    for rel, old, new in PATCHES:
        p = base / rel
        if not p.exists():
            print(f"!! {p} not found")
            return 2
        texts.setdefault(rel, p.read_text(encoding="utf-8"))
    for rel, old, new in PATCHES:
        text = texts[rel]
        if new in text:
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected text found {text.count(old)} times: {old.strip().splitlines()[0][:70]!r}")
            print("!! not the version this package was built on: nothing written")
            return 2
        texts[rel] = text.replace(old, new)
        done.append(rel)
    for rel in dict.fromkeys(done):
        (base / rel).write_text(texts[rel], encoding="utf-8")
    print(f"patched: {', '.join(dict.fromkeys(done)) or 'nothing (already patched)'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
