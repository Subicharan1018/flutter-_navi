"""The job: decide what each song lacks, look it up (cached, rate-limited, resumable), write the empty fields."""
import datetime
import os
import re
import sys
import time

from . import genres as G
from . import match as M
from . import store as S
from .net import Client, NetError, RateLimited

ENV_KEY_NAME = "LASTFM_API_KEY"          # the key is referenced by NAME only; its value is never printed or stored


def cfg_from_env(env=os.environ) -> dict:
    return {
        "catalog": env.get("LIBENRICH_CATALOG_DB", "/opt/shuffle-server/catalog.db"),
        "details": env.get("NAVIVIBE_SPOTIFY_DETAILS_DB", "/opt/shuffle-server/spotify_details.db"),
        "cache": env.get("LIBENRICH_CACHE_DB", "/DATA/AppData/navivibe/library_enrich.db"),
        "contact": env.get("LIBENRICH_CONTACT", "").strip(),
        "env_file": env.get("LIBENRICH_ENV_FILE", "/opt/shuffle-server/.env"),
    }


def user_agent(contact: str) -> str:
    """MusicBrainz asks for a contact (a URL or an address) in the User-Agent; the owner supplies it."""
    return "NaviVibe-LibraryEnrich/1.0 ( %s )" % contact


def lastfm_key(env=os.environ, env_file: str = "") -> str:
    """The Last.fm key from the environment, else from the one `LASTFM_API_KEY=` line of the shuffle server's
    .env (no other line is read). Returns '' when absent. The value never leaves this function except in the
    request itself."""
    v = env.get(ENV_KEY_NAME, "").strip()
    if v or not env_file:
        return v
    try:
        with open(env_file, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"\s*(?:export\s+)?%s\s*=\s*(.*)$" % ENV_KEY_NAME, line)
                if m:
                    return m.group(1).strip().strip("'\"")
    except OSError:
        pass
    return ""


# ── what each song could get, from what is already known ─────────────────────

def candidates(song: dict, raw: dict, cache: S.Cache) -> dict:
    """{field: (value, source, date)} from the catalog's own stored Last.fm / MusicBrainz payloads and from this
    job's cache. Pure reading: no network."""
    sid, out = song["id"], {}
    mb = cache.get(sid, "mb")
    mbr = mb["result"] if mb and mb["status"] == "ok" else {}
    cat_mb = raw.get("musicbrainz")
    if mbr.get("label"):
        out["label"] = (mbr["label"], "musicbrainz", mb["fetched_at"])
    date = mbr.get("release_date")
    if date:
        out["release_date"] = (date, "musicbrainz", mb["fetched_at"])
    elif cat_mb and M.good_date(cat_mb[0].get("first_release_date")) and float(cat_mb[0].get("match", 0)) >= 0.9:
        out["release_date"] = (cat_mb[0]["first_release_date"], "musicbrainz(catalog)", cat_mb[1])
    if mbr.get("isrc") and not song.get("isrc"):
        out["isrc"] = (mbr["isrc"], "musicbrainz", mb["fetched_at"])
    sources, used, dates = [], [], []
    lf = cache.get(sid, "lastfm")
    lfp, lfd = (lf["result"], lf["fetched_at"]) if lf and lf["status"] == "ok" else (None, "")
    if lfp is None and raw.get("lastfm"):
        lfp, lfd = raw["lastfm"]
    if lfp:
        sources += [(lfp.get("track_tags") or {}, 1.0), (lfp.get("artist_tags") or {}, 0.6)]
        used.append("lastfm")
        dates.append(lfd)
    if mbr.get("genres"):
        sources.append((mbr["genres"], 0.8))
        used.append("musicbrainz")
        dates.append(mb["fetched_at"])
    if sources:
        g = G.normalise(sources, (song.get("artist"), song.get("album_artist"), song.get("composer")))
        if g:
            out["genres"] = (g, "+".join(used), max(dates))
    return out


def needs(song: dict, details: dict) -> set:
    d = details.get(song["id"]) or {}
    n = {f for f in ("label", "release_date", "genres") if S.empty(d.get(f))}
    if not song.get("isrc") and S.empty(d.get("isrc")):
        n.add("isrc")
    return n


# ── lookups ──────────────────────────────────────────────────────────────────

def lookup_mb(song: dict, raw: dict, client: Client, cache: S.Cache, want: set, now=None):
    """One song on MusicBrainz: by the catalog's mbid when it has one, else a strict search. 1 to 3 requests."""
    mbid = song.get("mbid") or (raw["musicbrainz"][0].get("mbid") if raw.get("musicbrainz") else "") or ""
    rec = None
    if mbid:
        rec = client.mb_recording(mbid)
    else:
        hit = M.pick_search_hit(song, client.mb_search(song["title"], song.get("artist") or ""))
        if hit:
            mbid = hit["id"]
            rec = hit if (hit.get("isrcs") is not None and hit.get("releases") is not None) else client.mb_recording(mbid)
    if not rec:
        cache.put(song["id"], "mb", "miss", None, now)
        return
    res = M.parse_recording(rec)
    res["mbid"] = mbid
    if "label" in want or not res["release_date"]:
        res.update(M.parse_releases(client.mb_releases(mbid)))
    if not any(res.get(k) for k in ("isrc", "release_date", "label", "genres")):
        cache.put(song["id"], "mb", "miss", None, now)
    else:
        cache.put(song["id"], "mb", "ok", res, now)


def lookup_lastfm(song: dict, key: str, client: Client, cache: S.Cache, now=None):
    """track.getTopTags first; artist.getTopTags always (the song's own tags are often empty)."""
    artist = (song.get("artist") or "").split(";")[0].strip()
    if not artist:
        cache.put(song["id"], "lastfm", "miss", None, now)
        return
    track = M.parse_lastfm(client.lf_tags(key, "track.getTopTags", artist, song["title"]))
    art = M.parse_lastfm(client.lf_tags(key, "artist.getTopTags", artist))
    if track or art:
        cache.put(song["id"], "lastfm", "ok", {"track_tags": track, "artist_tags": art}, now)
    else:
        cache.put(song["id"], "lastfm", "miss", None, now)


def deadline(max_minutes, end_by, now: float):
    end = now + (max_minutes or 24 * 60) * 60
    if end_by:
        h, m = (int(x) for x in end_by.split(":"))
        d = datetime.datetime.fromtimestamp(now).replace(hour=h, minute=m, second=0, microsecond=0)
        if d.timestamp() <= now:
            d += datetime.timedelta(days=1)
        end = min(end, d.timestamp())
    return end


def run(cfg: dict, args, client: Client, key: str = "", clock=time.time, log=print) -> dict:
    """Fetch what is missing (unless args.apply_only), then write the empty fields. Returns a summary dict."""
    songs, raw = S.read_catalog(cfg["catalog"])
    cache = S.Cache(cfg["cache"])
    out = {"songs": len(songs), "mb_lookups": 0, "lastfm_lookups": 0, "stopped": ""}
    try:
        if not args.apply_only:
            details = S.read_details(cfg["details"])
            end = deadline(args.max_minutes, args.end_by, clock())
            day = S.today(clock())
            errors = done = 0
            for song in songs:
                if clock() >= end:
                    out["stopped"] = "time"
                    break
                if args.limit and done >= args.limit:
                    out["stopped"] = "limit"
                    break
                want = needs(song, details)
                if not want:
                    continue
                sraw = raw.get(song["id"], {})
                still = want - set(candidates(song, sraw, cache))
                src = ""
                try:
                    if still & {"isrc", "label", "release_date"} and not args.no_musicbrainz                             and cache.due(song["id"], "mb", day):
                        src = "mb"
                        lookup_mb(song, sraw, client, cache, still, clock())
                        out["mb_lookups"] += 1
                        done += 1
                        still = want - set(candidates(song, sraw, cache))
                    if "genres" in still and key and not args.no_lastfm and not sraw.get("lastfm")                             and cache.due(song["id"], "lastfm", day):
                        src = "lastfm"
                        lookup_lastfm(song, key, client, cache, clock())
                        out["lastfm_lookups"] += 1
                        done += 1
                except RateLimited:
                    out["stopped"] = "rate-limited"
                    log("rate limited by the service: stopping; the next run continues")
                    break
                except NetError as e:
                    errors += 1
                    cache.put(song["id"], src, "error", {"error": str(e)}, clock())
                    if errors >= 5:
                        out["stopped"] = "errors"
                        log("5 failures in a row: stopping")
                        break
                    continue
                errors = 0
        details = S.read_details(cfg["details"])
        fills = {}
        for song in songs:
            want = needs(song, details)
            if not want:
                continue
            have = {f: v for f, v in candidates(song, raw.get(song["id"], {}), cache).items() if f in want}
            if have:
                fills[song["id"]] = have
        out["to_write"] = {f: sum(1 for v in fills.values() if f in v) for f in S.FIELDS}
        if getattr(args, "dry_run", False):
            out["written"] = {}
        else:
            out["written"] = S.write_details(cfg["details"], fills, clock()) if fills else {f: 0 for f in S.FIELDS}
    finally:
        cache.close()
    return out


def report(cfg: dict) -> str:
    songs, raw = S.read_catalog(cfg["catalog"])
    details = S.read_details(cfg["details"])
    lines = ["library songs: %d" % len(songs)]
    for f in S.FIELDS:
        have = sum(1 for s in songs if not S.empty((details.get(s["id"]) or {}).get(f)) or (f == "isrc" and s.get("isrc")))
        lines.append("  %-13s %d filled, %d empty" % (f, have, len(songs) - have))
    if os.path.exists(cfg["cache"]):
        c = S.Cache(cfg["cache"])
        lines.append("cache: " + ", ".join("%s=%d" % kv for kv in sorted(c.stats().items())))
        c.close()
    return "\n".join(lines)
