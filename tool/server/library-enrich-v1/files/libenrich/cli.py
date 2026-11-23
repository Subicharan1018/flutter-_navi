"""python3 -m libenrich --run | --apply-only | --report"""
import argparse
import sys

from . import core
from .net import Client


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="libenrich", description="Fill empty genre / label / release date / ISRC from "
                                 "MusicBrainz and Last.fm into spotify_details.db (never overwrites).")
    ap.add_argument("--run", action="store_true", help="look up what is missing (cached, 1 request/s), then write")
    ap.add_argument("--apply-only", action="store_true", help="no network: write from the cache and the catalog")
    ap.add_argument("--report", action="store_true", help="print how many songs have each field")
    ap.add_argument("--dry-run", action="store_true", help="count what would be written; write nothing")
    ap.add_argument("--limit", type=int, default=0, help="at most N lookups this run")
    ap.add_argument("--max-minutes", type=float, default=0)
    ap.add_argument("--end-by", help="HH:MM server time at the latest")
    ap.add_argument("--no-musicbrainz", action="store_true")
    ap.add_argument("--no-lastfm", action="store_true")
    a = ap.parse_args(argv)
    cfg = core.cfg_from_env()
    if a.report:
        print(core.report(cfg))
        return 0
    if not (a.run or a.apply_only):
        ap.error("choose --run, --apply-only or --report")
    client = None
    key = ""
    if a.run:
        if not cfg["contact"] and not a.no_musicbrainz:
            print("LIBENRICH_CONTACT is not set. MusicBrainz asks every client for a contact (a URL or address) in its "
                  "User-Agent; set it to the one you choose, or use --no-musicbrainz.", file=sys.stderr)
            return 2
        client = Client(core.user_agent(cfg["contact"] or "no-musicbrainz"))
        key = core.lastfm_key(env_file=cfg["env_file"])
        if not key and not a.no_lastfm:
            print("note: no %s found: Last.fm is read from the catalog's stored tags only" % core.ENV_KEY_NAME)
    a.apply_only = a.apply_only or not a.run
    out = core.run(cfg, a, client, key)
    print("songs %(songs)d; MusicBrainz lookups %(mb_lookups)d; Last.fm lookups %(lastfm_lookups)d; "
          "stopped: %(stopped)s" % {**out, "stopped": out["stopped"] or "finished"})
    print("would write:", out["to_write"], "| written:", out["written"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
