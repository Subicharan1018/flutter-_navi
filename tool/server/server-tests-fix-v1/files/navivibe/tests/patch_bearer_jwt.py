"""Teach navivibe/navidrome.py to pass a Navidrome JWT to Navidrome as `jwt`.

The web app signs in with a Navidrome JWT (it never keeps the password), so the
shuffle server sees `Authorization: Bearer <jwt>`. Routes that call Navidrome
on the user's behalf (People / friend activity, Smart Shuffle of a playlist)
built `u=<user>&t=<jwt>`, which Navidrome rejects: `t` must be md5(password +
salt). Navidrome accepts the JWT itself as the `jwt` parameter.

usage: python patch_bearer_jwt.py /opt/shuffle-server/navivibe/navidrome.py
exit 0: patched or already patched; exit 2: the file is not the expected one
(nothing written).
"""
import sys

OLD = '''    if auth_header.startswith("Bearer "):
        token = auth_header[len("Bearer "):]
        return {
            "u": username,
            "t": token,
            "v": SUBSONIC_VERSION,'''

NEW = '''    if auth_header.startswith("Bearer "):
        token = auth_header[len("Bearer "):]
        # A Navidrome JWT is not a Subsonic token (t = md5(password + salt));
        # Navidrome takes it as `jwt` (web-server-v1).
        return {
            "u": username,
            "jwt": token,
            "v": SUBSONIC_VERSION,'''


def patch(text: str) -> tuple[str, str]:
    """Returns (new_text, status) with status in {"patched", "already", "mismatch"}."""
    if NEW in text:
        return text, "already"
    if text.count(OLD) != 1:
        return text, "mismatch"
    return text.replace(OLD, NEW), "patched"


def main(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    new, status = patch(text)
    if status == "mismatch":
        print(f"!! {path}: the Bearer branch is not the one this patch expects; nothing changed.")
        return 2
    if status == "patched":
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)
    print(f"   {path}: {status}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
