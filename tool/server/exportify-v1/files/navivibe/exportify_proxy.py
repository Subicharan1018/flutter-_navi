"""
navivibe/exportify_proxy.py   (exportify-v1)
────────────────────────────────────────────
"Import a Spotify playlist from an Exportify CSV" for the app: a thin authenticated proxy to
tg-fetcher (which parses, matches and fetches). Same rules as /fetch: the sign-in is checked here,
the call to tg-fetcher is signed, and anyone without download access gets 403 without a call.

  POST   /exportify/imports                  {"name", "csv"}     the CSV text; 201 summary + owned_ids
  GET    /exportify/imports                  the user's imports
  GET    /exportify/imports/<id>             one import (counts, plan, free space)
  GET    /exportify/imports/<id>/songs/<state>/<page>
  GET    /exportify/imports/<id>/owned       Navidrome ids of the songs already owned
  POST   /exportify/imports/<id>/estimate    what a fetch would cost with these settings
  PUT    /exportify/imports/<id>/plan        order, minimum popularity, per night, disk floor, night only
  POST   /exportify/imports/<id>/start | pause | cancel | retry-failed
  POST   /exportify/imports/<id>/playlist    {"playlist_id"}
  DELETE /exportify/imports/<id>

The CSV is never logged and never stored here: it goes straight on to tg-fetcher.
"""

import re

from flask import jsonify, request

from navivibe import fetch_proxy

_ID = re.compile(r"^[A-Za-z0-9_\-]{1,64}$")
_STATES = {"all", "owned", "wishlist", "queued", "downloaded", "failed", "skipped_disk"}
_ACTIONS = {"start", "pause", "cancel", "retry-failed"}
_PLAN_KEYS = ("priority", "min_popularity", "per_night", "disk_floor_gb", "night_only")
MAX_CSV_CHARS = 8_000_000


def _plan_body(body: dict):
    """The plan fields of a request, type-checked; (dict, None) or (None, error)."""
    out = {}
    for k in _PLAN_KEYS:
        if k not in body:
            continue
        v = body[k]
        if k == "priority":
            if v not in ("popularity", "list"):
                return None, "Order must be most popular first or your list order."
        elif k == "night_only":
            if not isinstance(v, bool):
                return None, "night_only must be true or false."
        elif isinstance(v, bool) or not isinstance(v, (int, float)):
            return None, f"{k} must be a number."
        out[k] = v
    return out, None


def register_exportify_routes(app, require_auth):
    @app.route("/exportify/imports", methods=["POST"])
    @require_auth
    def exportify_create():
        body = request.get_json(silent=True) or {}
        text = body.get("csv")
        if not isinstance(text, str) or not text.strip():
            return jsonify({"error": "Send the CSV file's text."}), 400
        if len(text) > MAX_CSV_CHARS:
            return jsonify({"error": "This file is too big. The limit is 8 MB."}), 413
        return fetch_proxy._forward("POST", "/exportify/imports",
                                    {"name": str(body.get("name", ""))[:200], "csv": text})

    @app.route("/exportify/imports", methods=["GET"])
    @require_auth
    def exportify_list():
        return fetch_proxy._forward("GET", "/exportify/imports")

    @app.route("/exportify/imports/<int:import_id>", methods=["GET"])
    @require_auth
    def exportify_get(import_id):
        return fetch_proxy._forward("GET", f"/exportify/imports/{import_id}")

    @app.route("/exportify/imports/<int:import_id>", methods=["DELETE"])
    @require_auth
    def exportify_delete(import_id):
        return fetch_proxy._forward("DELETE", f"/exportify/imports/{import_id}")

    @app.route("/exportify/imports/<int:import_id>/songs/<state>/<int:page>", methods=["GET"])
    @require_auth
    def exportify_songs(import_id, state, page):
        if state not in _STATES or page > 1000:
            return jsonify({"error": "no such list"}), 404
        return fetch_proxy._forward("GET", f"/exportify/imports/{import_id}/songs/{state}/{page}")

    @app.route("/exportify/imports/<int:import_id>/owned", methods=["GET"])
    @require_auth
    def exportify_owned(import_id):
        return fetch_proxy._forward("GET", f"/exportify/imports/{import_id}/owned")

    @app.route("/exportify/imports/<int:import_id>/estimate", methods=["POST"])
    @require_auth
    def exportify_estimate(import_id):
        plan, err = _plan_body(request.get_json(silent=True) or {})
        if err:
            return jsonify({"error": err}), 400
        return fetch_proxy._forward("POST", f"/exportify/imports/{import_id}/estimate", plan)

    @app.route("/exportify/imports/<int:import_id>/plan", methods=["PUT"])
    @require_auth
    def exportify_plan(import_id):
        plan, err = _plan_body(request.get_json(silent=True) or {})
        if err:
            return jsonify({"error": err}), 400
        return fetch_proxy._forward("PUT", f"/exportify/imports/{import_id}/plan", plan)

    @app.route("/exportify/imports/<int:import_id>/<action>", methods=["POST"])
    @require_auth
    def exportify_action(import_id, action):
        if action == "playlist":
            pid = (request.get_json(silent=True) or {}).get("playlist_id")
            if not isinstance(pid, str) or not _ID.match(pid):
                return jsonify({"error": "playlist_id must be a Navidrome playlist id"}), 400
            return fetch_proxy._forward("POST", f"/exportify/imports/{import_id}/playlist", {"playlist_id": pid})
        if action not in _ACTIONS:
            return jsonify({"error": "no such action"}), 404
        body = {}
        if action == "start":                      # "Fetch my wishlist" carries the settings with it
            body, err = _plan_body(request.get_json(silent=True) or {})
            if err:
                return jsonify({"error": err}), 400
        return fetch_proxy._forward("POST", f"/exportify/imports/{import_id}/{action}", body)
