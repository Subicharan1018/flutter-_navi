"""film-credits-v1: patch the shuffle server so the credits reach the app.

  server.py          registers GET /credits/films (navivibe/film_credits.py), next to /catalog/songs
  catalog/api.py     optional extra keys in GET /catalog/songs entries (film where missing, fk, md, ly, sg), and the
                     document's ETag changes when film_credits.db does

Every patch is an exact text match: a file already patched is left alone, a file that is not the version this package was
built on stops the run before anything is written. Needs the catalog/api.py of exportify-v1 (its extend_entry hook).

usage: python patch_proxy.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

PATCHES = [   # (file, old (exactly once), new)
    ("server.py",
     "@app.route(\"/catalog/songs\", methods=[\"GET\"])\n",
     "# film-credits-v1: GET /credits/films (navivibe/film_credits.py)\n"
     "from navivibe.film_credits import register_film_credits_routes  # noqa: E402\n"
     "register_film_credits_routes(app, require_auth)\n\n\n"
     "@app.route(\"/catalog/songs\", methods=[\"GET\"])\n"),
    ("catalog/api.py",
     "    spotify_details.extend_entry(e, s)\n",
     "    spotify_details.extend_entry(e, s)\n"
     "    from navivibe import film_credits   # film-credits-v1: film where missing, fk, md, ly, sg\n"
     "    film_credits.extend_entry(e, s)\n"),
    ("catalog/api.py",
     "        from navivibe import spotify_details   # exportify-v1\n        stamp = []\n",
     "        from navivibe import film_credits, spotify_details   # exportify-v1, film-credits-v1\n        stamp = []\n"),
    ("catalog/api.py",
     "spotify_details.stamp())        # moods-v2, exportify-v1\n",
     "spotify_details.stamp(), film_credits.stamp())        # moods-v2, exportify-v1, film-credits-v1\n"),
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
