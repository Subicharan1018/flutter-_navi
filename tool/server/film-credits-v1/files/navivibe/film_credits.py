"""
navivibe/film_credits.py   (film-credits-v1)
─────────────────────────────────────────────
Film, music director, lyricist and singers per song, read from film_credits.db (written by the filmcredits job, next
to catalog.db; override with NAVIVIBE_FILM_CREDITS_DB). Read-only here; no file, table or row = no answer, never an error.

  extend_entry(e, s)   optional extra keys in one GET /catalog/songs entry (nothing renamed or removed):
                         film (only where the catalog has none), fk (film key), md / ly / sg (name lists)
  stamp()              changes whenever the file does (for the catalog document's ETag)
  GET /credits/films   {"films": [{fk, title, year, directors, music_directors, lyricists, wikidata, tracklist?}]} with an ETag
"""
import hashlib
import json
import logging
import os
import sqlite3
import threading

from flask import Response, request

log = logging.getLogger(__name__)

PATH = os.getenv("NAVIVIBE_FILM_CREDITS_DB",
                 os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "film_credits.db"))
_lock = threading.Lock()
_cache = {"stamp": None, "path": None, "songs": {}, "films": [], "body": b"", "etag": ""}


def stamp(path=None):
    try:
        st = os.stat(path or PATH)
        return (st.st_mtime_ns, st.st_size)
    except OSError:
        return None


def _load(path):
    s = stamp(path)
    with _lock:
        if _cache["path"] == path and _cache["stamp"] == s:
            return _cache
        songs, films = {}, []
        if s is not None:
            try:
                c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=5)
                try:
                    for sid, fk, film, md, ly, sg in c.execute("SELECT song_id, fk, film, md, ly, sg FROM songs"):
                        songs[sid] = {"fk": fk or "", "film": film or "", "md": json.loads(md or "[]"),
                                      "ly": json.loads(ly or "[]"), "sg": json.loads(sg or "[]")}
                    for fk, title, year, dr, md, ly, wd, tl in c.execute(
                            "SELECT fk, title, year, directors, music_directors, lyricists, wikidata, tracklist FROM films "
                            "WHERE fk IN (SELECT fk FROM songs WHERE fk != '') ORDER BY fk"):
                        f = {"fk": fk, "title": title, "year": year, "directors": json.loads(dr or "[]"),
                             "music_directors": json.loads(md or "[]"), "lyricists": json.loads(ly or "[]"), "wikidata": wd or ""}
                        if tl:
                            f["tracklist"] = json.loads(tl)
                        films.append({k: v for k, v in f.items() if v not in (None, "", [])} | {"fk": fk})
                finally:
                    c.close()
            except (sqlite3.Error, ValueError) as e:      # no table yet, half-written file: no answer
                log.warning("film_credits unreadable: %s", type(e).__name__)
                songs, films = {}, []
        body = json.dumps({"films": films}, ensure_ascii=False, separators=(",", ":")).encode()
        _cache.update(stamp=s, path=path, songs=songs, films=films, body=body,
                      etag='"' + hashlib.sha1(body).hexdigest()[:20] + '"')
        return _cache


def get(song_id):
    return _load(PATH)["songs"].get(song_id)


def extend_entry(e: dict, s: dict) -> None:
    d = get(s.get("id"))
    if not d:
        return
    if d["film"] and not e.get("film"):
        e["film"] = d["film"]
    if d["fk"]:
        e["fk"] = d["fk"]
    for k in ("md", "ly", "sg"):
        if d[k]:
            e[k] = list(d[k])[:6]


def register_film_credits_routes(app, require_auth):
    @app.route("/credits/films", methods=["GET"])
    @require_auth
    def credits_films():
        c = _load(PATH)
        headers = {"ETag": c["etag"], "Cache-Control": "private, no-cache"}
        if c["etag"] in (request.headers.get("If-None-Match") or ""):
            return Response(status=304, headers=headers)
        return Response(c["body"], mimetype="application/json", headers=headers)
