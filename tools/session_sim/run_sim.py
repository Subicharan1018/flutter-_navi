"""
A throwaway copy of the live-playback relay with fake auth, for driving the REAL app client against
the REAL relay code over real WebSockets, with no credentials and no production data.

  cd /tmp/nv_sim                       # a copy of /opt/shuffle-server/navivibe + the session.py under test
  PYTHONPATH=/tmp/nv_sim SIM_PORT=5599 SIM_FAST=1 /opt/shuffle-server/venv/bin/python run_sim.py

Auth: the token is base64("user:sim") (what the app sends); the password must be "sim".
Extra routes for the test driver:  GET /_sim/rooms   what the server believes, per user
                                   GET /_sim/drop?user=&device=   cut a device's socket (a network drop)
                                   GET /_sim/stats   how many logins were accepted / refused
SIM_FAST=1 shortens only the reconnect grace (to 4 s) so outage scenarios finish quickly; every other
constant (pings, stale timeout, hysteresis, claim cooldown, transfer timeout) is the production value.
"""

import base64
import os

import uvicorn
from fastapi import Query
from fastapi.responses import JSONResponse

from navivibe import session


STATS = {"auth_ok": 0, "auth_fail": 0}


async def fake_auth(token):
    try:
        user, password = base64.b64decode(token).decode().split(":", 1)
    except Exception:
        STATS["auth_fail"] += 1
        return None
    if password == "sim" and user:
        STATS["auth_ok"] += 1
        return user
    STATS["auth_fail"] += 1
    return None


class NoLimit:
    def check(self, *a, **k):
        return 0.0

    def peek(self, *a, **k):
        return 0.0


session.authenticate = fake_auth
session._authenticate_guarded = lambda token, ip: fake_auth(token)
session._limiter = NoLimit()
if os.getenv("SIM_FAST") == "1":
    session.RECONNECT_GRACE_SECONDS = 4.0


@session.app.get("/_sim/rooms")
async def sim_rooms():
    out = {}
    for key, room in session.hub.rooms.items():
        out[key] = {
            "epoch": room.epoch,
            "version": room.version,
            "active": room.state["active_device"],
            "track": room.state["track_id"],
            "is_playing": room.state["is_playing"],
            "position_ms": room.state["position_ms"],
            "pending": bool(room.pending),
            "devices": {
                d.id: {"name": d.name, "type": d.type, "proto": d.proto, "sockets": len(d.sockets)}
                for d in room.devices.values()
            },
        }
    return JSONResponse(out)


@session.app.get("/_sim/stats")
async def sim_stats():
    return JSONResponse(STATS)


@session.app.get("/_sim/drop")
async def sim_drop(user: str = Query(...), device: str = Query(...)):
    room = session.hub.rooms.get(user.strip().lower())
    dev = room.devices.get(device) if room else None
    n = 0
    for ws in list(dev.sockets if dev else []):
        try:
            await ws.close(code=1001)
        except Exception:
            pass
        n += 1
    return {"dropped": n}


if __name__ == "__main__":
    uvicorn.run(session.app, host="127.0.0.1", port=int(os.getenv("SIM_PORT", "5599")), log_level="info")
