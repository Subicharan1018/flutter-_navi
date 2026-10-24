#!/usr/bin/env python3
"""Checks that an APK keeps its native libraries stored (not deflated).

Stored libs are what make binary patches small: deflate scrambles the whole
entry whenever a few bytes change, stored bytes diff cleanly.

  python tool/release/verify_apk.py dist/NaviVibe-arm64-v8a.apk [...]
"""
import sys
import zipfile


def main(paths):
    bad = False
    for path in paths:
        z = zipfile.ZipFile(path)
        print(f"{path}  ({sum(i.compress_size for i in z.infolist()) / 1048576:.1f} MB of entries)")
        for i in z.infolist():
            if not i.filename.endswith(".so"):
                continue
            stored = i.compress_type == zipfile.ZIP_STORED
            bad |= not stored
            print(f"  {'stored  ' if stored else 'DEFLATED'} {i.file_size / 1048576:6.2f} MB  {i.filename}")
        for name in ("classes.dex",):
            try:
                i = z.getinfo(name)
                print(f"  {'stored  ' if i.compress_type == zipfile.ZIP_STORED else 'deflated'} {i.file_size / 1048576:6.2f} MB  {name}")
            except KeyError:
                pass
    if bad:
        sys.exit("native libraries are compressed; patches would be huge")


if __name__ == "__main__":
    main(sys.argv[1:])
