"""
navivibe/data_queue.py   (data-queue-v1)
────────────────────────────────────────
The admin's weekly data queue (see data_queue_store.py for what the queue is). Admin only: anyone else, signed in or
not as admin, gets the same 404 as for a route that does not exist and never sees a count or a song.

  GET  /data-queue/status                   counts, the next batch, the open batch, coverage, quality summary
  POST /data-queue/batches                  make this week's batch (the open one when there is one); {"new": true}
                                            makes another from the songs still waiting
  GET  /data-queue/batches                  history (newest first)
  GET  /data-queue/batches/<id>             one batch: its songs with their state, the audit trail
  GET  /data-queue/batches/<id>/file.csv    the transfer file (TuneMyMusic, Soundiiz): same bytes as
  GET  /data-queue/batches/<id>/file.txt    tool/exportify/library_export.py writes
  POST /data-queue/batches/<id>/upload      the Exportify CSV: JSON {"name", "csv"} or the raw text (text/csv).
                                            At most 8 MB and 20,000 rows. The same file twice changes nothing.
  POST /data-queue/batches/<id>/release     put the batch's songs back in the queue

The upload stores Spotify's real numbers for the songs it matched (ISRC first, then clean title + same version words
+ an artist in common + length within 5 s: the exportify-v1 rules, tool/exportify/spotify_match.py) in
spotify_details.db, and PREDICTED energy / valence / danceability / acousticness (data_queue_model.py) for the
others in data_queue.db, marked feature_source='predicted'. The two are never mixed. The CSV itself is never kept.

Command line (on the server, as subi):
    cd /opt/shuffle-server && venv/bin/python -m navivibe.data_queue backfill --dry-run
    venv/bin/python -m navivibe.data_queue backfill --exclude ~/exports/batch1.csv --exclude ~/exports/my_playlist.csv
"""

import csv
import functools
import io
import json
import logging
import os
import re
import sqlite3
import sys
import time

from navivibe import data_queue_store as store

log = logging.getLogger(__name__)

MAX_BYTES = 8_000_000
MAX_ROWS = 20_000
LINKS = {"soundiiz": "https://soundiiz.com/tutorial/import-excel-to-soundiiz",
         "tunemymusic": "https://www.tunemymusic.com/transfer/file-to-spotify"}
FEATURES = ("danceability", "energy", "key", "loudness", "mode", "speechiness", "acousticness", "instrumentalness",
            "liveness", "valence", "tempo", "time_signature")
_INT_FEATURES = {"key", "mode", "time_signature"}
DETAILS_COLUMNS = ("song_id TEXT PRIMARY KEY, isrc TEXT, popularity INTEGER, genres TEXT, label TEXT, "
                   "release_date TEXT, explicit INTEGER, duration_s REAL, matched_by TEXT, " +
                   ", ".join("%s %s" % (f, "INTEGER" if f in _INT_FEATURES else "REAL") for f in FEATURES) +
                   ", updated_at REAL NOT NULL")


class QueueError(ValueError):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def catalog_path() -> str:
    from navivibe.catalog import store as cat
    return cat.CATALOG_DB


# ── the library, plays, gaps ─────────────────────────────────────────────────

def read_library(path: str | None = None) -> dict:
    """{song_id: {id, title, artist, album, album_artist, duration, isrc, path, feature_source, ...}} of the live songs."""
    p = path or catalog_path()
    if not os.path.exists(p):
        return {}
    c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(p).replace("\\", "/"), uri=True, timeout=10)
    try:
        cols = ("id", "title", "artist", "album", "album_artist", "duration", "isrc", "path", "feature_source",
                "composer", "language", "COALESCE(genre_display, genre_primary)", "energy", "valence", "bpm", "year")
        names = ("id", "title", "artist", "album", "album_artist", "duration", "isrc", "path", "feature_source",
                 "composer", "language", "genre", "energy", "valence", "bpm", "year")
        out = {}
        for r in c.execute("SELECT %s FROM songs WHERE COALESCE(missing,0)=0" % ", ".join(cols)):
            d = dict(zip(names, r))
            d["isrc"] = store.norm_isrc(d["isrc"])
            out[d["id"]] = d
        return out
    finally:
        c.close()


def play_counts(library: dict, log_dir: str | None = None) -> dict:
    """{song_id: plays by everyone}: the listening logs' play_events, matched by file path. Read only; a log that
    cannot be read counts for nothing."""
    if log_dir is None:
        try:
            from navivibe.feedback import DB_DIR as log_dir
        except Exception:                                   # noqa: BLE001
            log_dir = os.getenv("NAVIVIBE_LOG_DIR", "")
    by_path = {}
    for s in library.values():
        if s.get("path"):
            by_path[s["path"].casefold()] = s["id"]
            by_path.setdefault(os.path.basename(s["path"]).casefold(), s["id"])
    out = {}
    try:
        names = [n for n in os.listdir(log_dir) if n.endswith("_listening_log.db")]
    except OSError:
        return out
    for n in names:
        try:
            c = sqlite3.connect("file:%s?mode=ro" % os.path.join(log_dir, n).replace("\\", "/"), uri=True, timeout=3)
            try:
                for fp, k in c.execute("SELECT file_path, COUNT(*) FROM play_events WHERE file_path IS NOT NULL "
                                       "GROUP BY file_path"):
                    sid = by_path.get(str(fp).casefold()) or by_path.get(os.path.basename(str(fp)).casefold())
                    if sid:
                        out[sid] = out.get(sid, 0) + k
            finally:
                c.close()
        except sqlite3.Error:
            continue
    return out


def gap_scores(waiting_ids, real: set, catalog: str) -> dict:
    """{song_id: 0..1}: how far a waiting song sits (audio embedding) from every song Spotify labelled; 1 = the biggest
    gap. Empty when numpy or the embeddings are missing."""
    try:
        import numpy as np
        from navivibe.data_queue_tools import embedding_gap
        emb = embedding_gap.load_embeddings(catalog)
        if not emb or not waiting_ids:
            return {}
        ids = sorted(emb)
        pos = {s: i for i, s in enumerate(ids)}
        P = embedding_gap.reduce(np.stack([emb[s] for s in ids]))
        labelled = [pos[s] for s in real if s in pos]
        want = [s for s in waiting_ids if s in pos]
        d = embedding_gap.dist_to_set(P, labelled)[[pos[s] for s in want]]
        d = np.where(np.isfinite(d), d, 0.0)
        top = float(d.max()) if len(d) else 0.0
        return {s: (float(x) / top if top > 0 else 0.0) for s, x in zip(want, d)}
    except Exception as e:                                  # noqa: BLE001
        log.warning("data-queue: gap scores unavailable (%s)", type(e).__name__)
        return {}


_rank_cache = {"key": None, "at": 0.0, "plays": {}, "gaps": {}}


def rank_inputs(c, library: dict, now: float, fresh: bool = False) -> tuple:
    """(plays, gaps), cached for ten minutes while the queue is unchanged (the numbers are not cheap)."""
    key = tuple(c.execute("SELECT COUNT(*), COALESCE(MAX(updated_at),0) FROM queue WHERE state='waiting'").fetchone())
    if not fresh and _rank_cache["key"] == key and now - _rank_cache["at"] < 600:
        return _rank_cache["plays"], _rank_cache["gaps"]
    waiting = [r[0] for r in c.execute("SELECT song_id FROM queue WHERE state='waiting'")]
    plays = play_counts(library)
    real = store.real_ids() | {s["id"] for s in library.values() if s.get("feature_source") == "spotify"}
    gaps = gap_scores(waiting, real, catalog_path())
    _rank_cache.update(key=key, at=now, plays=plays, gaps=gaps)
    return plays, gaps


# ── reading the Exportify CSV ────────────────────────────────────────────────

_HEADERS = {"title": ("track name", "name", "title", "track"),
            "artist": ("artist name(s)", "artist names", "artist name", "artists", "artist"),
            "isrc": ("isrc",), "duration": ("duration (ms)", "duration_ms"), "popularity": ("popularity",),
            "release": ("release date", "album release date"), "genres": ("genres", "artist genres"),
            "label": ("record label", "label"), "explicit": ("explicit",)}
_HEADERS.update({f: (f, f.replace("_", " ")) for f in FEATURES})
_CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


def _num(v, cast=float):
    try:
        return cast(float(str(v).strip()))
    except (TypeError, ValueError):
        return None


def parse_csv(data) -> list:
    """Rows [{isrc, title, artist, duration_s, features{...}, details{...}}] of an Exportify export.
    'Added By' / 'Added At' are never read. Raises QueueError."""
    if isinstance(data, (bytes, bytearray)):
        if len(data) > MAX_BYTES:
            raise QueueError("This file is too big. The limit is 8 MB.", 413)
        try:
            text = bytes(data).decode("utf-8-sig")
        except UnicodeDecodeError:
            text = bytes(data).decode("cp1252", errors="replace")
    else:
        text = str(data)
        if len(text) > MAX_BYTES:
            raise QueueError("This file is too big. The limit is 8 MB.", 413)
    text = text.replace("﻿", "").replace("\x00", "")
    try:
        reader = csv.reader(io.StringIO(text, newline=""))
        header = next((rec for rec in reader if any(c.strip() for c in rec)), None)
        if header is None:
            raise QueueError("The file is empty.")
        names = [re.sub(r"\s+", " ", (h or "").strip().lower()) for h in header]
        cols = {}
        for field, aliases in _HEADERS.items():
            for a in aliases:
                if a in names:
                    cols[field] = names.index(a)
                    break
        if "title" not in cols or "artist" not in cols:
            raise QueueError("This isn't an Exportify playlist. Export it as CSV from exportify.net: it needs the "
                             "Track Name and Artist Name(s) columns.")
        rows = []

        def cell(rec, field):
            i = cols.get(field)
            return _CTRL.sub("", rec[i]).strip() if i is not None and i < len(rec) else ""

        for rec in reader:
            if not any(c.strip() for c in rec):
                continue
            title = cell(rec, "title")
            if not title:
                continue
            if len(rows) >= MAX_ROWS:
                raise QueueError("This playlist has more than 20,000 songs. Split it and export the parts one by one.", 413)
            ms = _num(cell(rec, "duration"))
            feats = {}
            for f in FEATURES:
                v = _num(cell(rec, f), int if f in _INT_FEATURES else float)
                if v is not None and cell(rec, f) != "":
                    feats[f] = v
            rows.append({"isrc": store.norm_isrc(cell(rec, "isrc")), "title": title[:200],
                         "artist": "; ".join(p.strip() for p in cell(rec, "artist").split(";") if p.strip())[:300],
                         "duration_s": round(ms / 1000.0, 1) if ms and ms > 0 else None, "features": feats,
                         "details": {"popularity": max(0, min(100, _num(cell(rec, "popularity"), int) or 0)),
                                     "genres": [g.strip()[:40] for g in cell(rec, "genres").split(",") if g.strip()][:8],
                                     "label": cell(rec, "label")[:80], "release_date": cell(rec, "release")[:10],
                                     "explicit": 1 if cell(rec, "explicit").lower() in ("true", "1", "yes") else 0}})
    except csv.Error:
        raise QueueError("This file isn't a readable CSV.") from None
    if not rows:
        raise QueueError("No songs found in this file.")
    return rows


def _match_module():
    from navivibe.data_queue_tools import spotify_match
    return spotify_match

def write_details(path: str, items: list, now: float) -> int:
    """Spotify's real numbers for library songs -> spotify_details.db (the same table exportify-v1 writes). Re-running
    rewrites the same rows. Returns the number of rows."""
    if not items:
        return 0
    c = sqlite3.connect(path, timeout=10)
    try:
        c.execute("CREATE TABLE IF NOT EXISTS spotify_details (%s)" % DETAILS_COLUMNS)
        c.execute("CREATE INDEX IF NOT EXISTS spotify_details_isrc ON spotify_details(isrc)")
        cols = ["song_id", "isrc", "popularity", "genres", "label", "release_date", "explicit", "duration_s",
                "matched_by"] + list(FEATURES) + ["updated_at"]
        c.executemany("INSERT OR REPLACE INTO spotify_details (%s) VALUES (%s)" % (", ".join(cols), ",".join("?" * len(cols))),
                      [(sid, row["isrc"] or song.get("isrc") or None, row["details"]["popularity"],
                        json.dumps(row["details"]["genres"], ensure_ascii=False), row["details"]["label"] or None,
                        row["details"]["release_date"] or None, row["details"]["explicit"], row["duration_s"], how,
                        *[row["features"].get(f) for f in FEATURES], now)
                       for sid, row, song, how in items])
        c.commit()
    finally:
        c.close()
    return len(items)


# ── the upload ───────────────────────────────────────────────────────────────

def process_upload(c, batch_id: int, data: bytes, name: str = "", now: float | None = None,
                   details_path: str | None = None, catalog: str | None = None) -> dict:
    """Apply an Exportify CSV to an open batch. Returns the result summary; `repeated` is true when this very file was
    applied before (nothing changes then). Raises QueueError."""
    now = time.time() if now is None else now
    details_path = details_path or store.DETAILS_PATH
    if len(data) > MAX_BYTES:
        raise QueueError("This file is too big. The limit is 8 MB.", 413)
    sha = store.sha256(data)
    old = store.find_upload(c, sha)
    if old:
        if old["batch_id"] != batch_id:
            raise QueueError("This file was already used for batch %d." % old["batch_id"], 409)
        store.audit(c, batch_id, "repeated_upload", {"sha256": sha[:12]}, now)
        return {**json.loads(old["result"]), "repeated": True}
    b = c.execute("SELECT * FROM batches WHERE id=?", (batch_id,)).fetchone()
    if not b:
        raise QueueError("No such batch.", 404)
    if b["state"] != "open":
        raise QueueError("This batch is %s: it takes no more files." % b["state"], 409)
    rows = parse_csv(data)
    if not any("energy" in r["features"] and "valence" in r["features"] for r in rows):
        raise QueueError("This export has no audio features (Energy, Valence ...). In Exportify, export the playlist "
                         "again and keep the audio-feature columns.")
    songs = [dict(r, id=r["song_id"]) for r in store.batch_songs(c, batch_id)]
    matched = _match_module().match_rows(rows, songs)
    real_items, states, by = [], {}, {"isrc": 0, "title": 0}
    no_features = 0
    for row, song, how in matched:
        if "energy" in row["features"] and "valence" in row["features"]:
            real_items.append((song["song_id"], row, song, how))
            states[song["song_id"]] = ("done", "spotify:" + how)
            by[how] += 1
        else:                                   # on Spotify, but this row came without audio features
            states[song["song_id"]] = ("skipped", "on_spotify_without_features")
            no_features += 1
    guess = [s["song_id"] for s in songs if states.get(s["song_id"], ("", ""))[0] != "done"]   # these get a prediction
    for sid in guess:
        states.setdefault(sid, ("not_on_spotify", None))
    stored = write_details(details_path, real_items, now)
    predicted, report = {}, {}
    if guess:
        try:
            from navivibe import data_queue_model as model
            cat = catalog or catalog_path()
            predicted, report = model.predict(guess, model.load_embeddings(cat), model.load_truth(cat, details_path))
        except Exception as e:                              # noqa: BLE001 - the upload itself must still land
            log.warning("data-queue: prediction skipped (%s)", type(e).__name__)
            report = {"error": type(e).__name__}
    for sid in guess:
        if states[sid][0] == "not_on_spotify":
            states[sid] = ("not_on_spotify", "predicted" if sid in predicted else "no_prediction")
    result = {"batch_id": batch_id, "rows": len(rows), "songs": len(songs), "matched": len(real_items),
              "matched_by_isrc": by["isrc"], "matched_by_title": by["title"],
              "not_found": sum(1 for s in states.values() if s[0] == "not_on_spotify"),
              "on_spotify_without_features": no_features, "features_stored": stored, "predicted": len(predicted),
              "sha256": sha, "repeated": False, "model": report}
    store.close_batch(c, batch_id, sha, name, states, result, predicted, now)
    return result


# ── routes ───────────────────────────────────────────────────────────────────

def _next_batch(c, ranked: list) -> dict:
    top = ranked[:store.BATCH_SIZE]
    return {"size": len(top), "full": len(ranked) >= store.BATCH_SIZE, "with_isrc": sum(1 for r in top if r["isrc"]),
            "songs": [{"title": r["title"], "artist": r["artist"], "isrc": bool(r["isrc"]), "source": r["source"]} for r in top]}


def status_payload(c, now: float | None = None) -> dict:
    now = time.time() if now is None else now
    store.release_stale(c, now)
    store.reconcile(c, now)
    library = read_library()
    plays, gaps = rank_inputs(c, library, now)
    ranked = store.rank_waiting(c, plays, gaps, now)
    real = store.real_ids() | {s["id"] for s in library.values() if s.get("feature_source") == "spotify"}
    ob = store.open_batch(c)
    counts = store.counts(c)
    return {"counts": counts, "waiting": counts["waiting"], "batch_size": store.BATCH_SIZE,
            "full_batch_ready": ob is None and len(ranked) >= store.BATCH_SIZE,
            "next_batch": _next_batch(c, ranked), "open_batch": store.batch_out(c, ob) if ob else None,
            "coverage": store.coverage(c, library.keys(), real), "quality": store.quality(c, now), "links": LINKS,
            "limits": {"upload_bytes": MAX_BYTES, "upload_rows": MAX_ROWS, "stale_days": store.STALE_DAYS}}


def register_data_queue_routes(app, require_auth, admin_users):
    """admin_users(): the admin user names, lower case (server.ADMIN_USERS)."""
    from flask import Response, g, jsonify, request

    def not_found():
        return jsonify({"error": "Not found"}), 404

    def admin_route(rule, **opts):
        def deco(f):
            @functools.wraps(f)
            def checked(*a, **k):
                if g.username.lower() not in admin_users():
                    return not_found()
                try:
                    return f(*a, **k)
                except QueueError as e:
                    return jsonify({"error": str(e)}), e.status
                except sqlite3.Error as e:
                    log.warning("data-queue: database error (%s)", type(e).__name__)
                    return jsonify({"error": "The queue could not be read right now. Try again in a minute."}), 503
            return app.route(rule, **opts)(require_auth(checked))
        return deco

    @admin_route("/data-queue/status", methods=["GET"])
    def dq_status():
        c = store.connect()
        try:
            return jsonify(status_payload(c))
        finally:
            c.close()

    @admin_route("/data-queue/batches", methods=["GET"])
    def dq_history():
        c = store.connect()
        try:
            return jsonify({"batches": store.history(c)})
        finally:
            c.close()

    @admin_route("/data-queue/batches", methods=["POST"])
    def dq_create():
        body = request.get_json(silent=True) or {}
        c = store.connect()
        try:
            now = time.time()
            store.release_stale(c, now)
            ob = store.open_batch(c)
            if ob and not body.get("new"):
                return jsonify({"batch": store.batch_out(c, ob), "created": False})
            library = read_library()
            plays, gaps = rank_inputs(c, library, now, fresh=True)
            live = {sid: s for sid, s in library.items()} if library else None
            made = store.build_batch(c, plays, gaps, live, now)
            if not made["batch_id"]:
                return jsonify({"batch": None, "created": False, "skipped": made["skipped"]})
            row = c.execute("SELECT * FROM batches WHERE id=?", (made["batch_id"],)).fetchone()
            return jsonify({"batch": store.batch_out(c, row), "created": True, "skipped": made["skipped"]}), 201
        finally:
            c.close()

    @admin_route("/data-queue/batches/<int:bid>", methods=["GET"])
    def dq_batch(bid):
        c = store.connect()
        try:
            row = c.execute("SELECT * FROM batches WHERE id=?", (bid,)).fetchone()
            if not row:
                return not_found()
            songs = [{"title": r["title"], "artist": r["artist"], "isrc": bool(r["isrc"]), "state": r["state"],
                      "note": r["note"]} for r in store.batch_songs(c, bid)]
            return jsonify({"batch": store.batch_out(c, row), "songs": songs, "audit": store.audit_of(c, bid)})
        finally:
            c.close()

    @admin_route("/data-queue/batches/<int:bid>/file.<fmt>", methods=["GET"])
    def dq_file(bid, fmt):
        if fmt not in ("csv", "txt"):
            return not_found()
        c = store.connect()
        try:
            row = c.execute("SELECT * FROM batches WHERE id=?", (bid,)).fetchone()
            if not row:
                return not_found()
            data = store.file_bytes(store.batch_songs(c, bid), fmt)
            store.audit(c, bid, "download", {"format": fmt, "bytes": len(data)})
            return Response(data, mimetype="text/csv" if fmt == "csv" else "text/plain",
                            headers={"Content-Disposition": 'attachment; filename="navivibe_data_queue_%02d.%s"' % (bid, fmt),
                                     "Cache-Control": "no-store"})
        finally:
            c.close()

    @admin_route("/data-queue/batches/<int:bid>/upload", methods=["POST"])
    def dq_upload(bid):
        if (request.mimetype or "").endswith("json"):
            body = request.get_json(silent=True) or {}
            text, name = body.get("csv"), str(body.get("name") or "")
            if not isinstance(text, str) or not text.strip():
                raise QueueError("Send the CSV file's text.")
            data = text.encode("utf-8")
        else:
            data, name = request.get_data(cache=False), ""
            if not data.strip():
                raise QueueError("Send the CSV file's text.")
        c = store.connect()
        try:
            result = process_upload(c, bid, data, name)
            _rank_cache["key"] = None
            return jsonify(result), 200 if result.get("repeated") else 201
        finally:
            c.close()

    @admin_route("/data-queue/batches/<int:bid>/release", methods=["POST"])
    def dq_release(bid):
        c = store.connect()
        try:
            if not store.release(c, bid, "admin"):
                raise QueueError("Only an open batch can be released.", 409)
            _rank_cache["key"] = None
            return jsonify({"released": True})
        finally:
            c.close()


# ── backfill: the library songs that still lack real Spotify features ─────────

def backfill(catalog: str, exclude_files=(), limit: int = 0, dry_run: bool = False, details_path: str | None = None,
             path: str | None = None, now: float | None = None) -> dict:
    """Seed the queue with the library songs that have no real Spotify features, in coverage-gap order
    (tool/exportify/library_sample.py `pick_gaps`: farthest in the audio-embedding space from every labelled song
    first, ISRC songs before the others). `exclude_files` (earlier export files, ours or Exportify's) skip the songs
    already exported or covered. Songs the sampler finds ineligible (remixes, sped-up, live ... , under a minute,
    spoken word) are not queued: Spotify would not match them."""
    now = time.time() if now is None else now
    from navivibe.data_queue_tools import embedding_gap, library_sample
    library = read_library(catalog)
    songs = list(library.values())
    real = store.real_ids(details_path) | {s["id"] for s in songs if s.get("feature_source") == "spotify"}
    ex_isrc, ex_keys = library_sample.read_exclusions(list(exclude_files))
    ex_ids = library_sample.excluded_ids(list(exclude_files), songs) if exclude_files else set()
    exclude = (ex_isrc, ex_keys, ex_ids)
    c = store.connect(path)
    try:
        known = {r[0] for r in c.execute("SELECT song_id FROM queue")}
    finally:
        c.close()
    pool = [s for s in songs if s["id"] not in real and s["id"] not in known]
    sampler_ok = [s for s in pool if library_sample.eligible(s, ((), ()), False)]
    eligible = [s for s in sampler_ok if library_sample.eligible(s, exclude, False)]
    emb = embedding_gap.load_embeddings(catalog)
    n = limit or len(eligible)
    if emb and eligible:
        chosen = library_sample.pick_gaps(eligible, n, real, emb, exclude)
        rest = [s for s in eligible if s["id"] not in {x["id"] for x in chosen}]
        chosen = chosen + sorted(rest, key=lambda s: s["id"])[:max(0, n - len(chosen))]
    else:
        chosen = sorted(eligible, key=lambda s: (0 if s.get("isrc") else 1, s["id"]))[:n]
    out = {"library": len(songs), "have_real_features": len(real & set(library)), "already_queued": len(known),
           "excluded": len(sampler_ok) - len(eligible), "not_eligible": len(pool) - len(sampler_ok),
           "to_queue": len(chosen), "with_isrc": sum(1 for s in chosen if s.get("isrc")), "queued": 0, "dry_run": dry_run}
    if dry_run:
        return out
    for i, s in enumerate(chosen):
        prio = 1.0 - i / max(1, len(chosen))            # the biggest gap first
        out["queued"] += store.enqueue(s, "backfill", now, path, details_path, prio) == "queued"
    return out


def main(argv=None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("backfill", help="queue the library songs that lack real Spotify features")
    b.add_argument("--catalog", default=None, help="catalog.db (default: the server's)")
    b.add_argument("--exclude", action="append", default=[], metavar="CSV",
                   help="an earlier export file (ours or Exportify's): its songs are not queued; repeatable")
    b.add_argument("--limit", type=int, default=0, help="queue at most this many (default: all)")
    b.add_argument("--dry-run", action="store_true")
    sub.add_parser("status", help="print the queue counts")
    a = ap.parse_args(argv)
    if a.cmd == "status":
        c = store.connect()
        try:
            print(json.dumps(store.counts(c)))
        finally:
            c.close()
        return 0
    res = backfill(a.catalog or catalog_path(), a.exclude, a.limit, a.dry_run)
    for k, v in res.items():
        print("%-22s %s" % (k, v))
    return 0


if __name__ == "__main__":
    sys.exit(main())
