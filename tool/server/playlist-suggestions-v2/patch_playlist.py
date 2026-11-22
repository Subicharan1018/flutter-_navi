"""playlist-suggestions-v2: patches navivibe/discover.py and server.py. Idempotent.

    python -I patch_playlist.py /opt/shuffle-server            # patches both files
    python -I patch_playlist.py --check /opt/shuffle-server    # exit 0 if already patched

discover.py gets the new fit_playlist / suggest_for_playlist appended (they
replace the earlier definitions of the same names, which stay above, unused).
server.py's /predict/playlist-suggestions starts reading "exclude".
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MARK = "# ── playlist-suggestions-v2 ─"

SERVER_OLD = '''    picks = discover.suggest_for_playlist(eng, g.username, ids, limit=limit)
'''
SERVER_NEW = '''    shown = [str(s) for s in (body.get("exclude") or []) if s][:200]
    picks = discover.suggest_for_playlist(eng, g.username, ids, limit=limit, exclude=shown)
'''


def patch_discover(text: str) -> str:
    if MARK in text:
        return text
    for anchor in ("def fit_playlist(", "def suggest_for_playlist(", "def payload(", "def _all_events("):
        if anchor not in text:
            raise SystemExit(f"!! discover.py has no `{anchor}`: not the version this package was built for")
    with open(os.path.join(HERE, "append_discover.py.txt"), encoding="utf-8") as f:
        return text.rstrip("\n") + "\n" + f.read()


def patch_server(text: str) -> str:
    if SERVER_NEW in text:
        return text
    if SERVER_OLD not in text:
        raise SystemExit("!! server.py has no playlist-suggestions call to patch")
    return text.replace(SERVER_OLD, SERVER_NEW, 1)


def _rewrite(path: str, fn):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    out = fn(src)
    if out != src:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(out)
        print("patched", path)
    else:
        print("already patched", path)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = args[0]
    if "--check" in sys.argv:
        with open(os.path.join(root, "navivibe", "discover.py"), encoding="utf-8") as f:
            sys.exit(0 if MARK in f.read() else 1)
    _rewrite(os.path.join(root, "navivibe", "discover.py"), patch_discover)
    _rewrite(os.path.join(root, "navivibe", "server.py"), patch_server)
