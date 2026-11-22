"""
navivibe/album_overnight_proxy.py   (album-overnight-v1)
────────────────────────────────────────────────────────
"Complete the album overnight" for the app: a thin authenticated proxy to tg-fetcher (which looks the album
up, queues its missing tracks and fetches them at night through the Exportify queue). Same rules as /fetch
and /exportify: signed in, download access (403 otherwise, tg-fetcher not called), the call to tg-fetcher
is signed.

The paths live under /exportify/, so the rate limits and the access check of /exportify apply unchanged
(hardening.py needs no patch).

  GET  /exportify/album-overnight                         prefs + the queue (albums and their tracks)
  PUT  /exportify/album-overnight/prefs                   {"enabled"?, "film_only"?, "per_night"?, "max_per_album"?}
  POST /exportify/album-overnight/albums/<id>/cancel      drop what is not with the bot yet; never queued again
  POST /exportify/album-overnight/cancel-all
"""

from flask import jsonify, request

from navivibe import fetch_proxy

PER_NIGHT = (10, 20, 30, 50, 100)
MAX_PER_ALBUM = (5, 10, 15, 25, 40)


def register_album_overnight_routes(app, require_auth):
    @app.route("/exportify/album-overnight", methods=["GET"])
    @require_auth
    def album_overnight_get():
        return fetch_proxy._forward("GET", "/album-overnight/current")

    @app.route("/exportify/album-overnight/prefs", methods=["PUT"])
    @require_auth
    def album_overnight_prefs():
        body = request.get_json(silent=True) or {}
        out = {}
        for k in ("enabled", "film_only"):
            if k in body:
                if not isinstance(body[k], bool):
                    return jsonify({"error": f"{k} must be true or false."}), 400
                out[k] = body[k]
        for k, choices in (("per_night", PER_NIGHT), ("max_per_album", MAX_PER_ALBUM)):
            if k in body:
                v = body[k]
                if isinstance(v, bool) or not isinstance(v, int) or v not in choices:
                    return jsonify({"error": f"{k} must be one of {', '.join(map(str, choices))}."}), 400
                out[k] = v
        return fetch_proxy._forward("PUT", "/album-overnight/prefs", out)

    @app.route("/exportify/album-overnight/albums/<int:album_id>/cancel", methods=["POST"])
    @require_auth
    def album_overnight_cancel(album_id):
        return fetch_proxy._forward("POST", f"/album-overnight/albums/{album_id}/cancel", {})

    @app.route("/exportify/album-overnight/cancel-all", methods=["POST"])
    @require_auth
    def album_overnight_cancel_all():
        return fetch_proxy._forward("POST", "/album-overnight/cancel-all", {})
