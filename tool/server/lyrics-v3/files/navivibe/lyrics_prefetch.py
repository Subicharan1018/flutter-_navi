"""
navivibe/lyrics_prefetch.py   (lyrics-v3: a source that does not answer is never recorded as "not found";
                               a song whose only cache entry is an old miss is asked again)

Fetches synced lyrics for every song in catalog.db ahead of time and keeps them in the lyrics cache
(the same files GET /lyrics/fetch reads), so the sources are asked once per song, not on every play.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m navivibe.lyrics_prefetch [options]

      --max-minutes N      stop after N minutes (default 45); the next run carries on: a song with a
                           cache entry is skipped, so it is resumable by design
      --rate N             requests a minute across ALL sources (default 30; never more than 60)
      --limit N            at most N songs this run
      --sample N           a random sample of N songs (use with --seed) instead of the library in order
      --cache-dir DIR      write somewhere else (a dry run: nothing in the live cache changes)
      --retry-misses DAYS  ask again about songs nobody had after DAYS days (default 14)
      --sources a,b,c      default: every source that is on (lrcred, betterlyrics, ytmusic)

Gentle by construction: one request at a time, spaced to the rate; a 429 or 403 makes it wait (the
Retry-After, else 60 s doubling up to 15 min) and retry; a source that keeps refusing is left out
for 20 minutes. It never raises into the service: it is its own process, and every error is logged
and counted. Exit status is 0 unless the environment itself is broken.
"""
import argparse
import json
import logging
import os
import random
import signal
import sqlite3
import sys
import time

from navivibe import lyrics_proxy as lp

log = logging.getLogger("lyrics_prefetch")
FAILURES_IN_A_ROW = 15      # this many songs in a row where a source did not answer: stop for tonight


class GentleNet:
    """`get` with a shared rate limit and back-off on 429 / 403. Same signature as lyrics_proxy.http_get."""

    def __init__(self, per_minute=30, real_get=None, sleep=time.sleep, now=time.monotonic):
        self.interval = 60.0 / max(1, min(int(per_minute), 60))
        self.real_get, self.sleep, self.now = real_get or lp.http_get, sleep, now
        self.next_at = 0.0
        self.penalty = 0.0
        self.refused = {}            # host -> consecutive refusals
        self.cooldown_until = {}     # host -> monotonic time
        self.requests = 0
        self.backoffs = 0

    def throttle(self):
        wait = self.next_at - self.now()
        if wait > 0:
            self.sleep(wait)
        self.next_at = max(self.now(), self.next_at) + self.interval
        self.requests += 1

    def host_ok(self, host):
        return self.now() >= self.cooldown_until.get(host, 0)

    def __call__(self, url, params=None, headers=None, timeout=lp.TIMEOUT):
        host = url.split("/")[2] if "//" in url else url
        if not self.host_ok(host):
            return 429, ""
        status, text = 0, ""
        for attempt in range(3):
            self.throttle()
            try:
                status, text = self.real_get(url, params, headers, timeout)
            except Exception as e:           # a network blip is a miss, not a crash
                log.warning("request failed (%s): %s", host, type(e).__name__)
                return 0, ""
            if status not in (429, 403):
                self.penalty = 0.0
                self.refused[host] = 0
                return status, text
            self.backoffs += 1
            self.penalty = min(max(60.0, self.penalty * 2), 900.0)
            log.warning("%s answered %s: waiting %ds", host, status, self.penalty)
            self.sleep(self.penalty)
        self.refused[host] = self.refused.get(host, 0) + 1
        if self.refused[host] >= 2:
            self.cooldown_until[host] = self.now() + 20 * 60
            log.warning("%s keeps refusing: leaving it out for 20 minutes", host)
        return status, text


def catalog_songs(db_path):
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5)
    try:
        rows = con.execute(
            "SELECT id, title, artist, album, duration FROM songs WHERE missing = 0 AND title <> '' ORDER BY id"
        ).fetchall()
    finally:
        con.close()
    return [{"song_id": r[0], "title": r[1] or "", "artist": r[2] or "", "album": r[3] or "",
             "duration": int(r[4] or 0), "spotify_id": ""} for r in rows]


def run(songs, sources, cache, net, max_seconds, retry_misses_days, now=time.time, clock=time.monotonic,
        should_stop=lambda: False):
    """-> summary dict. Skips songs whose cache entry is a hit or a fresh miss."""
    start = clock()
    summary = {"songs": len(songs), "skipped": 0, "found": {}, "not_found": 0, "failed": 0, "errors": 0,
               "stopped": ""}
    miss_ttl = retry_misses_days * 86400
    in_a_row = 0                                 # failures in a row: the sources are down, stop asking
    for song in songs:
        if should_stop():
            summary["stopped"] = "signal"
            break
        if clock() - start > max_seconds:
            summary["stopped"] = "time budget"
            break
        # A hit, a fresh complete miss (written by this version) and a failure of the last 5 minutes are
        # left alone. An old miss (v1 / v2), a plain answer due for a second look and a stale entry are asked.
        if lp.peek(song, sources, cache, now, miss_ttl) in ("hit", "miss", "failed"):
            summary["skipped"] += 1
            continue
        try:
            out = lp.lookup_ex(song, sources, cache, net, now, miss_ttl=miss_ttl, budget=None)
        except Exception as e:                   # never stop the run for one song
            log.exception("song %s: %s", song["song_id"], type(e).__name__)
            summary["errors"] += 1
            continue
        if out.state == "found":
            in_a_row = 0
            summary["found"][out.result["source"]] = summary["found"].get(out.result["source"], 0) + 1
        elif out.state == "failed":              # NOT recorded as a miss: the next run asks again
            summary["failed"] += 1
            in_a_row += 1
            if in_a_row >= FAILURES_IN_A_ROW:
                summary["stopped"] = "sources not answering"
                break
        else:
            in_a_row = 0
            summary["not_found"] += 1
    return summary


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--max-minutes", type=float, default=45)
    ap.add_argument("--rate", type=int, default=30)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--cache-dir", default=lp.CACHE_DIR)
    ap.add_argument("--retry-misses", type=float, default=14)
    ap.add_argument("--sources", default="")
    ap.add_argument("--catalog", default=lp.CATALOG_DB)
    args = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    sources = tuple(s for s in (args.sources.split(",") if args.sources else lp.DEFAULT_SOURCES)
                    if s in lp.SOURCES and s in lp.enabled_sources())
    if not sources:
        log.error("no source is switched on")
        return 0
    try:
        songs = catalog_songs(args.catalog)
    except sqlite3.Error as e:
        log.error("can't read %s: %s", args.catalog, e)
        return 1
    if args.sample:
        songs = random.Random(args.seed).sample(songs, min(args.sample, len(songs)))
    if args.limit:
        songs = songs[:args.limit]

    stop = {"now": False}
    signal.signal(signal.SIGTERM, lambda *_: stop.update(now=True))
    signal.signal(signal.SIGINT, lambda *_: stop.update(now=True))
    net = GentleNet(args.rate)
    cache = lp.SongCache(args.cache_dir)
    log.info("lyrics prefetch: %d songs, sources %s, %d requests/min, cache %s", len(songs), ",".join(sources),
             min(args.rate, 60), args.cache_dir)

    # YouTube Music goes through a subprocess, not `net`: it takes a slot from the same budget.
    plain_yt = lp.run_ytmusic

    def gentle_yt(query, **kw):
        net.throttle()
        return plain_yt(query, **kw)

    lp.run_ytmusic = gentle_yt
    try:
        summary = run(songs, sources, cache, net, args.max_minutes * 60, args.retry_misses,
                      should_stop=lambda: stop["now"])
    except Exception:                      # the final guard: log, exit 0, leave the service alone
        log.exception("prefetch stopped by an unexpected error")
        return 0
    summary["requests"], summary["backoffs"] = net.requests, net.backoffs
    found = sum(summary["found"].values())
    tried = found + summary["not_found"]
    log.info("summary: %s", json.dumps(summary, sort_keys=True))
    if tried:
        log.info("found %d of %d tried (%.0f%%): %s; not found %d; skipped %d already cached",
                 found, tried, 100.0 * found / tried,
                 ", ".join(f"{k} {v}" for k, v in sorted(summary["found"].items())) or "none",
                 summary["not_found"], summary["skipped"])
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
