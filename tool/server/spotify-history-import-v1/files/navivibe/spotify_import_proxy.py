"""
navivibe/spotify_import_proxy.py   (spotify-history-import-v1)
───────────────────────────────────────────────────────────────
"Import Spotify History" for the app: a thin authenticated proxy to tg-fetcher, which validates the cleaned plays,
matches the library and writes the listening log. Same rules as /history-import: the sign-in is checked here, the
call to tg-fetcher is signed, anyone without download access gets 403. The page body is checked here too (shape and
size) so a malformed request never reaches tg-fetcher. Undo / cancel / list are history-import-v1's routes.

  POST /spotify-import/jobs                {"format": "extended"|"basic", "total"?}
  GET  /spotify-import/jobs                the user's Spotify imports
  GET  /spotify-import/jobs/<id>
  POST /spotify-import/jobs/<id>/page      {"plays": [{"t","ms","title","artist","album"?,"end"?,"sk"?}, ... ≤1000]}
  POST /spotify-import/jobs/<id>/finish
"""

from flask import jsonify, request

from navivibe import fetch_proxy

_FORMATS = ("extended", "basic")
_MAX_PAGE = 1000
_KEEP = ("t", "ms", "title", "artist", "album", "end", "sk")     # anything else in a row is dropped here


def register_spotify_import_routes(app, require_auth):
    @app.route("/spotify-import/jobs", methods=["POST"])
    @require_auth
    def spotify_import_create():
        body = request.get_json(silent=True) or {}
        fmt = body.get("format", "extended")
        if fmt not in _FORMATS:
            return jsonify({"error": "Choose the extended or the basic Spotify export."}), 400
        payload = {"format": fmt}
        total = body.get("total")
        if isinstance(total, int) and not isinstance(total, bool) and 0 <= total <= 3_000_000:
            payload["total"] = total
        return fetch_proxy._forward("POST", "/spotify-import/jobs", payload)

    @app.route("/spotify-import/jobs", methods=["GET"])
    @require_auth
    def spotify_import_list():
        return fetch_proxy._forward("GET", "/spotify-import/jobs")

    @app.route("/spotify-import/jobs/<int:job_id>", methods=["GET"])
    @require_auth
    def spotify_import_get(job_id):
        return fetch_proxy._forward("GET", f"/spotify-import/jobs/{job_id}")

    @app.route("/spotify-import/jobs/<int:job_id>/page", methods=["POST"])
    @require_auth
    def spotify_import_page(job_id):
        plays = (request.get_json(silent=True) or {}).get("plays")
        if not isinstance(plays, list) or len(plays) > _MAX_PAGE:
            return jsonify({"error": f"Send up to {_MAX_PAGE} plays at a time."}), 400
        # A row that is not an object is passed on as it is: tg-fetcher counts it as refused. Known fields only.
        clean = [{k: p[k] for k in _KEEP if k in p} if isinstance(p, dict) else p for p in plays]
        return fetch_proxy._forward("POST", f"/spotify-import/jobs/{job_id}/page", {"plays": clean})

    @app.route("/spotify-import/jobs/<int:job_id>/finish", methods=["POST"])
    @require_auth
    def spotify_import_finish(job_id):
        return fetch_proxy._forward("POST", f"/spotify-import/jobs/{job_id}/finish", {})
