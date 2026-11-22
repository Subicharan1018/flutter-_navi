"""
navivibe/jam_invites.py
───────────────────────
Invite a friend into a live Jam from inside the app.

  POST /social/jam/<code>/invite          {"to": "bob"}    -> {"invited": "Bob"}
  GET  /social/jam/invites                                  -> {"invites": [{"code","from","mode","members","at","expires_at"}]}
  POST /social/jam/<code>/invite/decline                    -> {"declined": true}

Accepting needs no route of its own: the app calls the existing
POST /social/jam/join with the invite's code, which also makes the invite
disappear (a person already in the room is never offered it again).

Rules, enforced here and not in the app:
  • the sender is in that room (the room's code is never disclosed to anyone else)
  • both people turned social features on; you cannot invite yourself
  • not someone who is already in the room, and not into a full room
  • an invite is valid for INVITE_TTL_S, or until the room ends
  • one invite per sender -> friend every PAIR_GAP_S (re-sending refreshes it),
    HOURLY_MAX invites an hour per sender, at most INBOX_MAX waiting per friend
Invites live in memory like the rooms they point at: a restart ends both.
"""

import threading
import time

from flask import g, jsonify, request

from navivibe import jam as jam_mod
from navivibe import social_db
from navivibe.jam import JamError

INVITE_TTL_S = 30 * 60
PAIR_GAP_S = 5
HOURLY_MAX = 40
INBOX_MAX = 10


class InviteStore:
    def __init__(self, jam_store=None, clock=time.time):
        self._js = jam_store
        self._clock = clock
        self._lock = threading.RLock()
        self._inv: dict[tuple[str, str], dict] = {}     # (code, recipient key) -> invite
        self._sent: dict[str, list[float]] = {}         # sender key -> send times (last hour)
        self._pair: dict[tuple[str, str], float] = {}

    @property
    def js(self):
        return self._js or jam_mod.store

    def invite(self, sender: str, code: str, to_key: str, to_name: str) -> dict:
        """`to_name` is the friend as they are signed in; the caller checked social settings."""
        js = self.js
        with js._lock, self._lock:
            jam, skey = js._get(code, sender)          # 410 ended, 403 not in the room
            now = self._clock()
            if to_key == skey:
                raise JamError("You’re already in this Jam.", 400)
            if to_key in jam.members:
                raise JamError(f"{to_name} is already in this Jam.", 409)
            if len(jam.members) >= jam_mod.MAX_MEMBERS:
                raise JamError("This Jam is full.", 409)
            self._purge(now)
            if now - self._pair.get((skey, to_key), -1e9) < PAIR_GAP_S:
                raise JamError("Wait a moment before inviting them again.", 429)
            sent = [t for t in self._sent.get(skey, []) if now - t < 3600]
            if len(sent) >= HOURLY_MAX:
                raise JamError("Too many invites. Try again later.", 429)
            waiting = [k for k in self._inv if k[1] == to_key]
            if (jam.code, to_key) not in self._inv and len(waiting) >= INBOX_MAX:
                raise JamError("They have too many invitations waiting.", 429)
            self._inv[(jam.code, to_key)] = {"from_key": skey, "at": now}
            self._pair[(skey, to_key)] = now
            self._sent[skey] = sent + [now]
            js._names()[skey] = sender
            return {"invited": to_name}

    def inbox(self, user: str) -> list[dict]:
        js = self.js
        with js._lock, self._lock:
            js._sweep()
            now = self._clock()
            self._purge(now)
            key = js._key(user)
            out = []
            for (code, rkey), inv in list(self._inv.items()):
                if rkey != key:
                    continue
                jam = js._jams.get(code)
                if jam is None or key in jam.members:
                    self._inv.pop((code, rkey), None)
                    continue
                out.append({"code": code, "from": js._names().get(inv["from_key"], inv["from_key"]),
                            "mode": jam.mode, "members": len(jam.members), "at": inv["at"],
                            "expires_at": inv["at"] + INVITE_TTL_S})
            out.sort(key=lambda i: -i["at"])
            return out

    def decline(self, user: str, code: str) -> dict:
        js = self.js
        with js._lock, self._lock:
            self._inv.pop((str(code or "").strip().upper()[:12], js._key(user)), None)
            return {"declined": True}

    def _purge(self, now: float):
        for k, inv in list(self._inv.items()):
            if now - inv["at"] > INVITE_TTL_S or k[0] not in self.js._jams:
                del self._inv[k]
        for k, t in list(self._pair.items()):
            if now - t > 3600:
                del self._pair[k]


invites = InviteStore()


def register_jam_invite_routes(app, require_auth, jam_store=None, invite_store: InviteStore = None):
    st = invite_store or (InviteStore(jam_store) if jam_store is not None else invites)

    def run(fn):
        try:
            return jsonify(fn())
        except JamError as e:
            return jsonify({"error": e.message}), e.status

    @app.route("/social/jam/<code>/invite", methods=["POST"])
    @require_auth
    def jam_invite(code):
        body = request.get_json(silent=True) or {}
        to = str(body.get("to") or "").strip()

        def go():
            if not to:
                raise JamError("Pick a friend to invite.")
            conn = social_db.connect()
            try:
                if not social_db.is_enabled(conn, g.username):
                    raise JamError("Turn on social features in Settings first.", 403)
                target = next((p for p in social_db.enabled_users(conn) if p["username"].lower() == to.lower()), None)
            finally:
                conn.close()
            if target is None:
                raise JamError("That person isn’t on social features.", 404)
            return st.invite(g.username, code, target["username"].lower(), target["username"])
        return run(go)

    @app.route("/social/jam/invites", methods=["GET"])
    @require_auth
    def jam_invites():
        return jsonify({"invites": st.inbox(g.username)})

    @app.route("/social/jam/<code>/invite/decline", methods=["POST"])
    @require_auth
    def jam_invite_decline(code):
        return jsonify(st.decline(g.username, code))
