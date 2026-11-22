"""Registers the Jam invite routes in navivibe/social.py. Idempotent.

    python -I patch_social.py /opt/shuffle-server/navivibe/social.py
"""
import sys

IMPORT_ANCHOR = "from navivibe.jam import register_jam_routes\n"
IMPORT_NEW = IMPORT_ANCHOR + "from navivibe.jam_invites import register_jam_invite_routes\n"
CALL_ANCHOR = "    register_jam_routes(app, require_auth)\n"
CALL_NEW = CALL_ANCHOR + "    register_jam_invite_routes(app, require_auth)\n"


def patch(text: str) -> str:
    if "register_jam_invite_routes" in text:
        return text
    if IMPORT_ANCHOR not in text or CALL_ANCHOR not in text:
        raise SystemExit("!! social.py does not look like the version this package was built for")
    return text.replace(IMPORT_ANCHOR, IMPORT_NEW, 1).replace(CALL_ANCHOR, CALL_NEW, 1)


if __name__ == "__main__":
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        src = f.read()
    out = patch(src)
    if out != src:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(out)
        print("patched", path)
    else:
        print("already patched", path)
