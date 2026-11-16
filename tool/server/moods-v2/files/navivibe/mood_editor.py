"""
navivibe/mood_editor.py   (moods-v2)
───────────────────────
The mood editor: a plain page at GET /moods/editor (also https://shuffle.subimusic.me/moods/editor)
and the API it uses.

  POST   /moods/editor/login   {username, password} → Navidrome's own login → {token, username,
                               is_admin}. The page keeps only the token (sessionStorage), never
                               the password. Every other call sends "Authorization: Bearer <token>",
                               the JWT the web app uses; Basic auth works too.
  GET    /moods/me             {username, is_admin}
  GET    /moods/songs          ?offset&limit(<=100)&q&mood=<mood>|none&filter=flagged|admin
                               → {items, total, offset, next_offset, is_admin, cover_base}
  PUT    /moods/songs/<id>     {moods: [..]} admin only: the song's label for everyone (beats the
                               labeller; a relabel never overwrites it). [] = "no mood".
  DELETE /moods/songs/<id>     admin only: back to the labeller's label.

Non-admins change nothing global; they use "Not this mood" (POST/DELETE /moods/not-this).
"""

import os
import threading

import requests
from flask import Response, g, jsonify, request

HERE = os.path.dirname(__file__)
STATIC = os.path.join(HERE, "mood_editor_static")
PUBLIC_NAVIDROME = os.getenv("NAVIVIBE_PUBLIC_NAVIDROME_URL", "https://navidrome.subimusic.me").rstrip("/")
MAX_LIMIT = 100

# The API's own policy is default-src 'none'; the editor page needs its own script, style and
# (Navidrome) cover images, nothing else. No inline script, no framing.
EDITOR_CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; "
              f"img-src 'self' data: {PUBLIC_NAVIDROME}; base-uri 'none'; form-action 'none'; "
              "frame-ancestors 'none'")

_TYPES = {"index.html": "text/html; charset=utf-8", "app.js": "text/javascript; charset=utf-8",
          "app.css": "text/css; charset=utf-8"}

_lib_lock = threading.Lock()
_lib = {"stamp": None, "rows": None}


def library() -> dict:
    """{song_id: catalog row}; tests replace this."""
    from navivibe.catalog import store
    return store.load_catalog()


def _songs() -> list:
    """Library rows sorted by title, cached per catalog change."""
    from navivibe.catalog import mood_quality
    stamp = mood_quality._Facts._stamp()
    with _lib_lock:
        if _lib["rows"] is not None and _lib["stamp"] == stamp and _lib.get("src") is library:
            return _lib["rows"]
    rows = library()
    out = sorted(({"id": sid, "title": r.get("title") or "", "artist": r.get("artist") or "",
                   "album": r.get("album") or "", "film": r.get("film") or "",
                   "language": r.get("language") or ""} for sid, r in rows.items()),
                 key=lambda s: (s["title"].lower(), s["artist"].lower(), s["id"]))
    with _lib_lock:
        _lib.update(stamp=stamp, rows=out, src=library)
    return out


def _item(s: dict, labels: dict, raw: dict, admin: dict, meta: dict, nots: dict, fx: dict) -> dict:
    from navivibe.catalog import mood_quality
    sid = s["id"]
    a = admin.get(sid)
    flags = [] if a else [f"{m}: {why}" for m, why in mood_quality.explain(raw.get(sid) or [], fx.get(sid), meta.get(sid))]
    return {**s, "moods": labels.get(sid) or [], "llm": raw.get(sid) or [],
            "source": "admin" if a else ("llm" if labels.get(sid) else "none"),
            "by": a.get("by") if a else None, "at": a.get("at") if a else None,
            "flags": flags, "not": nots.get(sid, [])}


def _context(user: str):
    from navivibe import mood_overrides
    from navivibe.catalog import mood_quality, mood_tags
    return (mood_tags.load(), mood_tags.load_raw(), mood_quality.load_admin(), mood_quality.load_meta(),
            mood_overrides.load(user), mood_quality.facts())


def register_mood_editor_routes(app, require_auth, admin_users, navidrome_url):
    """admin_users(): the admin user names (lower case); navidrome_url(): Navidrome's address."""

    def is_admin() -> bool:
        return g.username.lower() in admin_users()

    @app.route("/moods/editor", methods=["GET"])
    @app.route("/moods/editor/<name>", methods=["GET"])
    def mood_editor_page(name="index.html"):
        if name not in _TYPES:
            return jsonify({"error": "Not found"}), 404
        with open(os.path.join(STATIC, name), "rb") as f:
            body = f.read()
        resp = Response(body, mimetype=_TYPES[name].split(";")[0])
        resp.headers["Content-Type"] = _TYPES[name]
        resp.headers["Cache-Control"] = "no-cache"
        return resp

    @app.route("/moods/editor/login", methods=["POST"])
    def mood_editor_login():
        body = request.get_json(silent=True) or {}
        user, pw = str(body.get("username") or "").strip(), str(body.get("password") or "")
        if not user or not pw or len(user) > 64 or len(pw) > 256:
            return jsonify({"error": "Enter your user name and password."}), 400
        try:
            r = requests.post(f"{navidrome_url()}/auth/login", json={"username": user, "password": pw}, timeout=8)
        except requests.RequestException:
            return jsonify({"error": "The music server didn't answer. Try again in a minute."}), 503
        if r.status_code != 200:
            return jsonify({"error": "Wrong user name or password."}), 401
        data = r.json() if r.content else {}
        token = data.get("token")
        if not token:
            return jsonify({"error": "The music server didn't sign you in."}), 502
        name = str(data.get("username") or user)
        return jsonify({"token": token, "username": name, "is_admin": name.lower() in admin_users()})

    @app.route("/moods/me", methods=["GET"])
    @require_auth
    def moods_me():
        return jsonify({"username": g.username, "is_admin": is_admin()})

    @app.route("/moods/songs", methods=["GET"])
    @require_auth
    def moods_songs():
        from navivibe.catalog import mood_tags
        try:
            offset = max(int(request.args.get("offset", 0)), 0)
            limit = min(max(int(request.args.get("limit", 50)), 1), MAX_LIMIT)
        except ValueError:
            return jsonify({"error": "offset and limit must be numbers"}), 400
        q = (request.args.get("q") or "").strip().lower()[:100]
        mood = (request.args.get("mood") or "").strip().lower()
        flt = (request.args.get("filter") or "").strip().lower()
        if mood and mood != "none" and mood not in mood_tags.FLOW_MOODS:
            return jsonify({"error": f"mood must be none or one of: {', '.join(mood_tags.FLOW_MOODS)}"}), 400
        if flt and flt not in ("flagged", "admin"):
            return jsonify({"error": "filter must be flagged or admin"}), 400
        labels, raw, admin, meta, nots, fx = _context(g.username)
        items = []
        for s in _songs():
            if q and q not in f"{s['title']} {s['artist']} {s['album']} {s['film']}".lower():
                continue
            have = labels.get(s["id"]) or []
            if mood == "none" and have or mood and mood != "none" and mood not in have:
                continue
            if flt == "admin" and s["id"] not in admin:
                continue
            it = _item(s, labels, raw, admin, meta, nots, fx)
            if flt == "flagged" and not it["flags"]:
                continue
            items.append(it)
        page = items[offset:offset + limit]
        nxt = offset + limit if offset + limit < len(items) else None
        return jsonify({"items": page, "total": len(items), "offset": offset, "next_offset": nxt,
                        "is_admin": is_admin(), "cover_base": PUBLIC_NAVIDROME})

    def _one(sid: str):
        labels, raw, admin, meta, nots, fx = _context(g.username)
        s = next((x for x in _songs() if x["id"] == sid), None)
        return _item(s, labels, raw, admin, meta, nots, fx) if s else None

    @app.route("/moods/songs/<sid>", methods=["PUT", "DELETE"])
    @require_auth
    def moods_song(sid):
        from navivibe import mood_overrides
        from navivibe.catalog import mood_quality
        if not is_admin():
            return jsonify({"error": "Only an admin can change a song's moods for everyone. "
                                     "Use Not this mood to change them for you."}), 403
        if not mood_overrides.valid_id(sid) or not any(x["id"] == sid for x in _songs()):
            return jsonify({"error": "No such song in the library."}), 404
        if request.method == "DELETE":
            mood_quality.clear_admin(sid)
            return jsonify({"ok": True, "song": _one(sid)})
        moods = mood_quality.clean_moods((request.get_json(silent=True) or {}).get("moods"))
        if moods is None:
            return jsonify({"error": "moods must be a list of at most 2 different moods from: "
                                     "sad, romantic, happy, energetic, calm, devotional, angry, gym"}), 400
        mood_quality.set_admin(sid, moods, g.username)
        return jsonify({"ok": True, "song": _one(sid)})
