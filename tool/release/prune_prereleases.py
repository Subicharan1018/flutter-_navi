#!/usr/bin/env python3
"""Prints the tags of pre-releases that should be deleted.

Reads `gh release list --json tagName,isPrerelease,createdAt` on stdin. A
pre-release is pruned when it is older than --days or not among the newest
--keep pre-releases. Normal (non-pre) releases are never listed.

  gh release list --limit 200 --json tagName,isPrerelease,createdAt | python tool/release/prune_prereleases.py
"""
import argparse
import datetime
import json
import sys


def to_prune(releases, keep, days, now=None):
    now = now or datetime.datetime.now(datetime.timezone.utc)
    cutoff = now - datetime.timedelta(days=days)
    pre = [r for r in releases if r.get("isPrerelease")]
    pre.sort(key=lambda r: r["createdAt"], reverse=True)
    out = []
    for i, r in enumerate(pre):
        created = datetime.datetime.fromisoformat(r["createdAt"].replace("Z", "+00:00"))
        if i >= keep or created < cutoff:
            out.append(r["tagName"])
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", type=int, default=10)
    ap.add_argument("--days", type=int, default=30)
    a = ap.parse_args()
    for tag in to_prune(json.load(sys.stdin), a.keep, a.days):
        print(tag)
