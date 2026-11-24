"""python3 -m filmcredits [--offline | --run [--tracklists] [--limit N] [--max-minutes M]] [--report]

--offline  (default) tags and album names only: rebuilds the `songs` and `films` tables, no network.
--run      then asks Wikidata (and, with --tracklists, MusicBrainz) about each film not asked about yet.
--report   counts, and how many songs have each field.
"""
import argparse
import collections
import json
import os
import sys
import time

from . import derive, sources
from .store import Store, read_catalog, today

CATALOG = os.getenv("FILMCREDITS_CATALOG_DB", "/opt/shuffle-server/catalog.db")
OUT = os.getenv("FILMCREDITS_DB", os.getenv("NAVIVIBE_FILM_CREDITS_DB", "/opt/shuffle-server/film_credits.db"))


def build(store: Store, songs, itunes_raw):
    """Offline pass. Returns {fk: {'title', 'year', 'composers'}} for the films it found."""
    lyr = {derive.norm_key(n) for s in songs for n in derive.split_names(s.get("lyricist"))}
    for r in store.c.execute("SELECT lyricists FROM films"):          # lyricists Wikidata already named
        lyr |= {derive.norm_key(n) for n in json.loads(r[0] or "[]")}
    # a composer is never re-labelled a lyricist because the same name shows up in an artist tag
    rows, films = [], collections.defaultdict(lambda: {"titles": collections.Counter(), "years": [], "md": collections.Counter()})
    for s in songs:
        d = derive.derive_song(s, derive.itunes_payload(itunes_raw.get(s["id"])), lyr)
        rows.append((s["id"], d))
        if d["fk"]:
            f = films[d["fk"]]
            f["titles"][d["film"]] += 1
            if s.get("year"):
                f["years"].append(int(s["year"]))
            f["md"].update(d["md"])
    store.replace_songs(rows)
    out = {}
    for fk, f in films.items():
        years = sorted(f["years"])
        out[fk] = {"title": f["titles"].most_common(1)[0][0], "year": years[len(years) // 2] if years else None,
                   "composers": [n for n, _ in f["md"].most_common(2)]}
        store.upsert_film(fk, out[fk]["title"], year=out[fk]["year"], music_directors=(), source="tags")
    return out


def main(argv=None, opener=None, now=time.monotonic):
    ap = argparse.ArgumentParser(prog="filmcredits")
    ap.add_argument("--run", action="store_true")
    ap.add_argument("--tracklists", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--max-minutes", type=float, default=0)
    ap.add_argument("--catalog", default=CATALOG)
    ap.add_argument("--db", default=OUT)
    a = ap.parse_args(argv)
    songs, it = read_catalog(a.catalog)
    store = Store(a.db)
    films = build(store, songs, it)
    if a.run:
        contact = os.getenv("FILMCREDITS_CONTACT") or os.getenv("LIBENRICH_CONTACT")
        if not contact:
            print("!! set FILMCREDITS_CONTACT (the contact Wikidata / MusicBrainz see in the User-Agent)")
            return 2
        client = sources.Client("NaviVibe-FilmCredits/1.0 ( %s )" % contact, **({"opener": opener} if opener else {}))
        start, done, day = now(), 0, today()
        for fk, f in sorted(films.items()):
            if (a.limit and done >= a.limit) or (a.max_minutes and now() - start > a.max_minutes * 60):
                break
            try:
                if store.due(fk, "wikidata", day):
                    done += 1
                    r = sources.resolve_film(client, f["title"], f["year"], f["composers"])
                    store.put(fk, "wikidata", "ok" if r else "miss", r)
                    if r:
                        store.upsert_film(fk, f["title"], r["year"], r["directors"], r["music_directors"], r["lyricists"],
                                          r["wikidata"], source="wikidata")
                if a.tracklists and store.due(fk, "musicbrainz", day):
                    t = sources.tracklist(client, f["title"], f["composers"], f["year"])
                    store.put(fk, "musicbrainz", "ok" if t else "miss", t)
                    if t:
                        store.upsert_film(fk, f["title"], tracklist=t["tracks"], tracklist_mbid=t["mbid"], source="musicbrainz")
            except sources.RateLimited:
                print("a service is busy; stopping, the next run continues here")
                break
            except sources.NetError as e:
                store.put(fk, "wikidata", "error", {"error": str(e)})
        build(store, songs, it)         # again: lyricists Wikidata named now move artist-tag names out of `singers`
        print("requests:", client.requests)
    if a.report or not a.run:
        print(json.dumps(store.counts(), indent=1))
    store.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
