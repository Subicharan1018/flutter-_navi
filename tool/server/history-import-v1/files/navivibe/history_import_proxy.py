"""
navivibe/history_import_proxy.py   (history-import-v1)
──────────────────────────────────────────────────────
"Import your listening history" for the app: a thin authenticated proxy to tg-fetcher (which reads
ListenBrainz / Last.fm, matches the library and writes the listening log). Same rules as /exportify: the
sign-in is checked here, the call to tg-fetcher is signed, and anyone without download access gets 403.

  POST /history-import/jobs                  {"source", "account", "full"?}
  GET  /history-import/jobs                  the user's imports
  GET  /history-import/jobs/<id>
  POST /history-import/jobs/<id>/step        {"secret"?}   one page; the Last.fm API key / ListenBrainz token
                                             rides along per request, is passed on and never kept or logged
  POST /history-import/jobs/<id>/cancel | undo
"""

import re

from flask import jsonify, request

from navivibe import fetch_proxy

_SOURCES = ("listenbrainz", "lastfm")
_SECRET = re.compile(r"^[A-Za-z0-9\-]{8,64}$")


def register_history_import_routes(app, require_auth):
    @app.route("/history-import/jobs", methods=["POST"])
    @require_auth
    def history_import_create():
        body = request.get_json(silent=True) or {}
        source, account = body.get("source"), body.get("account")
        if source not in _SOURCES:
            return jsonify({"error": "Choose ListenBrainz or Last.fm."}), 400
        if not isinstance(account, str) or not account.strip() or len(account) > 200:
            return jsonify({"error": "Enter your username."}), 400
        return fetch_proxy._forward("POST", "/history-import/jobs",
                                    {"source": source, "account": account.strip(), "full": body.get("full") is True})

    @app.route("/history-import/jobs", methods=["GET"])
    @require_auth
    def history_import_list():
        return fetch_proxy._forward("GET", "/history-import/jobs")

    @app.route("/history-import/jobs/<int:job_id>", methods=["GET"])
    @require_auth
    def history_import_get(job_id):
        return fetch_proxy._forward("GET", f"/history-import/jobs/{job_id}")

    @app.route("/history-import/jobs/<int:job_id>/step", methods=["POST"])
    @require_auth
    def history_import_step(job_id):
        secret = (request.get_json(silent=True) or {}).get("secret")
        if secret is not None and (not isinstance(secret, str) or not _SECRET.match(secret)):
            return jsonify({"error": "That key or token doesn’t look right."}), 400
        return fetch_proxy._forward("POST", f"/history-import/jobs/{job_id}/step", {"secret": secret})

    @app.route("/history-import/jobs/<int:job_id>/<action>", methods=["POST"])
    @require_auth
    def history_import_action(job_id, action):
        if action not in ("cancel", "undo"):
            return jsonify({"error": "no such action"}), 404
        return fetch_proxy._forward("POST", f"/history-import/jobs/{job_id}/{action}", {})
