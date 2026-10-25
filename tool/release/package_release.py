#!/usr/bin/env python3
"""Turn a folder of freshly built, signed APKs into release assets.

Shared by the GitHub Actions release workflow and tool/make_release_local.ps1,
so a local dry run produces exactly what CI publishes.

Inputs
  --apk-dir   folder with NaviVibe-<abi>.apk (arm64-v8a, armeabi-v7a, x86_64)
              and optionally NaviVibe-universal.apk
  --prev-dir  optional folder of earlier releases: <prev-dir>/<build>/NaviVibe-<abi>.apk
  --out       folder that receives patches, latest.json and SHA256SUMS.txt

Output
  NaviVibe-<abi>-from-<build>.patch   BSDIFF40 patch of the whole signed APK
  latest.json                         what the in-app updater reads
  SHA256SUMS.txt

Only needs `pip install bsdiff4`.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import sys

ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
# A patch that saves less than this fraction of the full download is not worth
# the extra complexity; the app falls back to the full APK anyway.
MAX_PATCH_RATIO = 0.6


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def entry(path, **extra):
    d = {"name": os.path.basename(path), "size": os.path.getsize(path), "sha256": sha256(path)}
    d.update(extra)
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk-dir", required=True)
    ap.add_argument("--prev-dir")
    ap.add_argument("--out", required=True)
    ap.add_argument("--version", required=True, help="versionName, e.g. 1.0.0")
    ap.add_argument("--build", required=True, type=int)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--asset-base", default="", help="URL prefix of the release assets (public repos)")
    ap.add_argument("--notes-file")
    ap.add_argument("--windows-dir", help="folder holding the Windows assets, listed in latest.json")
    ap.add_argument("--channel", default="stable", help="stable (main) or beta (other branches)")
    ap.add_argument("--max-patches", type=int, default=3, help="how many previous builds get a patch")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    notes = ""
    if args.notes_file and os.path.exists(args.notes_file):
        notes = open(args.notes_file, encoding="utf-8").read().strip()

    manifest = {
        "schema": 1,
        "version": args.version,
        "build": args.build,
        "tag": args.tag,
        "channel": args.channel,
        "published": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "assetBase": args.asset_base,
        "notes": notes,
        "android": {"abis": {}},
    }

    prev_builds = []
    if args.prev_dir and os.path.isdir(args.prev_dir):
        for name in os.listdir(args.prev_dir):
            if name.isdigit() and int(name) < args.build:
                prev_builds.append(int(name))
    prev_builds = sorted(prev_builds, reverse=True)[: args.max_patches]

    sums = []
    for abi in ABIS:
        apk = os.path.join(args.apk_dir, f"NaviVibe-{abi}.apk")
        if not os.path.exists(apk):
            continue
        item = entry(apk)
        item["patches"] = []
        sums.append((item["sha256"], item["name"]))
        new_bytes = None
        for pb in prev_builds:
            old = os.path.join(args.prev_dir, str(pb), f"NaviVibe-{abi}.apk")
            if not os.path.exists(old):
                continue
            import bsdiff4  # imported late so --help works without it

            patch = os.path.join(args.out, f"NaviVibe-{abi}-from-{pb}.patch")
            if new_bytes is None:
                new_bytes = open(apk, "rb").read()
            patch_bytes = bsdiff4.diff(open(old, "rb").read(), new_bytes)
            if len(patch_bytes) > MAX_PATCH_RATIO * item["size"]:
                print(f"[{abi}] patch from {pb} is {len(patch_bytes)} B; not worth it, skipped")
                continue
            with open(patch, "wb") as f:
                f.write(patch_bytes)
            p = entry(patch, fromBuild=pb, fromSha256=sha256(old), format="bsdiff40")
            item["patches"].append(p)
            sums.append((p["sha256"], p["name"]))
            print(f"[{abi}] patch from {pb}: {p['size']} B (full {item['size']} B)")
        manifest["android"]["abis"][abi] = item

    uni = os.path.join(args.apk_dir, "NaviVibe-universal.apk")
    if os.path.exists(uni):
        manifest["android"]["universal"] = entry(uni)
        sums.append((manifest["android"]["universal"]["sha256"], os.path.basename(uni)))

    if not manifest["android"]["abis"]:
        sys.exit("no NaviVibe-<abi>.apk files found in --apk-dir")

    if args.windows_dir and os.path.isdir(args.windows_dir):
        win = {}
        for fn in sorted(os.listdir(args.windows_dir)):
            path = os.path.join(args.windows_dir, fn)
            if re.search(r"Setup\.exe$", fn):
                win["setup"] = entry(path)
            elif fn.endswith(".zip"):
                win["zip"] = entry(path)
            elif fn.endswith(".nupkg"):
                win.setdefault("packages", []).append(entry(path))
            else:
                continue
            sums.append((sha256(path), fn))
        manifest["windows"] = win

    with open(os.path.join(args.out, "latest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    with open(os.path.join(args.out, "SHA256SUMS.txt"), "w", encoding="utf-8", newline="\n") as f:
        for digest, name in sums:
            f.write(f"{digest}  {name}\n")
    print("wrote latest.json and SHA256SUMS.txt")


if __name__ == "__main__":
    main()
