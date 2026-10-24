#!/usr/bin/env python3
"""Builds two APK-like zip files and a BSDIFF40 patch between them.

Uses the same `bsdiff4.diff` call as tool/release/package_release.py, so the
Dart test and tool/update_size_report.dart exercise exactly what CI produces.

  python tool/release/make_sample_patch.py --out build/update_sample --size 2000000

The "APKs" mimic the real layout: a stored (uncompressed) native library that
changes a little between versions, a stored dex, and a deflated asset.
"""
import argparse
import hashlib
import os
import random
import zipfile

import bsdiff4


def noise(rng, n):
    return bytes(rng.getrandbits(8) for _ in range(n))


def build(path, lib, dex, asset):
    with zipfile.ZipFile(path, "w") as z:
        for name, data, method in (
            ("classes.dex", dex, zipfile.ZIP_STORED),
            ("lib/arm64-v8a/libapp.so", lib, zipfile.ZIP_STORED),
            ("assets/flutter_assets/note.txt", asset, zipfile.ZIP_DEFLATED),
        ):
            z.writestr(zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0)), data, compress_type=method)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", type=int, default=2_000_000, help="bytes of the fake libapp.so")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    rng = random.Random(a.seed)

    lib_old = bytearray(noise(rng, a.size))
    dex_old = noise(rng, max(1000, a.size // 10))
    lib_new = bytearray(lib_old)
    # A typical release: a few changed regions plus code inserted in the middle.
    for _ in range(12):
        at = rng.randrange(0, len(lib_new) - 400)
        lib_new[at : at + 300] = noise(rng, 300)
    mid = len(lib_new) // 2
    lib_new[mid:mid] = noise(rng, 1500)
    dex_new = bytearray(dex_old)
    dex_new[100:200] = noise(rng, 100)

    old = os.path.join(a.out, "old.apk")
    new = os.path.join(a.out, "new.apk")
    build(old, bytes(lib_old), dex_old, b"release notes v1\n" * 50)
    build(new, bytes(lib_new), bytes(dex_new), b"release notes v2\n" * 50)

    old_b, new_b = open(old, "rb").read(), open(new, "rb").read()
    patch = bsdiff4.diff(old_b, new_b)
    with open(os.path.join(a.out, "sample.patch"), "wb") as f:
        f.write(patch)
    print(f"old {len(old_b)} B, new {len(new_b)} B, patch {len(patch)} B")
    print("new sha256", hashlib.sha256(new_b).hexdigest())


if __name__ == "__main__":
    main()
