"""server-fixes-v1: the shuffle server's /fetch proxy forwards "Search online anyway".

POST /fetch/searches rebuilt the body from `query` and `kind` only, so a
`"force": true` body field or a `?force=1` query parameter never reached
tg-fetcher. Now either one is forwarded as `"force": true` in the body (the
only form tg-fetcher needs); nothing else changes.

usage: python patch_proxy.py <navivibe/fetch_proxy.py>
exit 0: patched or already patched; exit 2: not the expected file (nothing written).
"""
import sys
from pathlib import Path

OLD = '''        if body.get("kind"):
            out["kind"] = str(body["kind"])     # tg-fetcher validates the value
        return _forward("POST", "/searches", out)
'''
NEW = '''        if body.get("kind"):
            out["kind"] = str(body["kind"])     # tg-fetcher validates the value
        # server-fixes-v1: "Search online anyway" (body "force": true, or ?force=1)
        if body.get("force") in (True, 1, "1", "true") or \\
                request.args.get("force", "").strip().lower() in ("1", "true", "yes"):
            out["force"] = True
        return _forward("POST", "/searches", out)
'''


def main(path: str) -> int:
    p = Path(path)
    if not p.exists():
        print(f"!! {p} not found")
        return 2
    text = p.read_text(encoding="utf-8")
    if NEW in text:
        print("fetch_proxy.py: already patched")
        return 0
    if text.count(OLD) != 1:
        print(f"!! {p}: expected text found {text.count(OLD)} times (not the version this package was built on)")
        return 2
    p.write_text(text.replace(OLD, NEW), encoding="utf-8")
    print("fetch_proxy.py: patched")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
