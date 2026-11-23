"""
tgfetch/weekly_exploration_api.py  (weekly-exploration-v1)
─────────────────────────────────────────────────────────
Internal routes behind the Weekly Exploration page. Same caller rules as every other route
(api.py's `user`: signed by the NaviVibe server, download access needed). No query strings.

  GET  /weekly/current                 the page: picks, prefs, this week's keeps, `needs_build`
  POST /weekly/build                   {artists, blocked_artists, extra}: the listener's taste, sent by the
                                       shuffle server. 202; the list is made in the background (a minute)
  POST /weekly/picks/{id}/keep         Keep: fetched at night under the weekly cap
  POST /weekly/picks/{id}/skip         Not for me
  POST /weekly/picks/{id}/restore      Undo a Not for me
  PUT  /weekly/prefs                   {enabled?, cap?}
"""

import contextlib
import logging
import sqlite3
import threading

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from tgfetch import weekly_exploration as wx
from tgfetch.library import load_library

log = logging.getLogger("tgfetch.weekly")

# Swapped in tests; the real one talks to Deezer and iTunes.
make_sources = wx.Sources


class SeedArtist(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    language: str = Field("", max_length=40)
    plays: float = Field(1.0, ge=0, le=100000)


class Hint(BaseModel):
    artist: str = Field(min_length=1, max_length=120)
    title: str = Field(min_length=1, max_length=160)
    source: str = Field("ListenBrainz", max_length=40)


class BuildIn(BaseModel):
    artists: list[SeedArtist] = Field(default_factory=list, max_length=12)
    blocked_artists: list[str] = Field(default_factory=list, max_length=500)
    extra: list[Hint] = Field(default_factory=list, max_length=30)


class PrefsIn(BaseModel):
    enabled: bool | None = None
    cap: int | None = Field(None, ge=0, le=wx.MAX_CAP)


def _file_of(conn) -> str:
    """The database file behind `conn` ('' for an in-memory database)."""
    try:
        row = conn.execute("PRAGMA database_list").fetchone()
        return (row[2] if row else "") or ""
    except Exception:
        return ""


def _open_own(path: str):
    """A connection for the build thread alone, to the same file (same settings as db.connect)."""
    c = sqlite3.connect(path, timeout=10, isolation_level=None)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA busy_timeout=10000")
    c.execute("PRAGMA foreign_keys=ON")
    return c


def register_routes(app, settings, conn, who_dep) -> None:
    wx.ensure_schema(conn)
    db_path = _file_of(conn)      # read once, here, on the thread that owns `conn`
    # The build runs in its own thread. One sqlite3 connection must not be used from two threads at once (the
    # poll of /weekly/current during the build raised InterfaceError and the list was not made), so a file
    # database gets the build a connection of its own. An in-memory database (tests) cannot be opened twice:
    # there the build and the weekly routes take turns on this lock.
    db_guard = contextlib.nullcontext() if db_path else threading.RLock()

    def run_build(who: str, seeds: dict) -> None:
        """Runs in its own thread: a build makes about 40 slow outside calls and must not hold the service."""
        own = _open_own(db_path) if db_path else None
        c = own or conn
        picks, err = 0, None
        try:
            with db_guard:
                try:
                    try:
                        library = load_library()
                    except Exception as e:           # without the library every song looks new: do not build
                        log.warning("weekly: library not read (%s)", type(e).__name__)
                        raise RuntimeError("library") from None
                    picks = wx.build(c, who, seeds, make_sources(), library)
                except Exception as e:                              # a failed build must never take the service down
                    err = f"The list couldn't be made ({type(e).__name__}). It will try again."
                    log.warning("weekly: build failed (%s)", type(e).__name__)
                wx.finish_build(c, who, picks, err)
        finally:
            if own is not None:
                own.close()

    @app.get("/weekly/current")
    async def current(who: str = Depends(who_dep)):
        with db_guard:
            return wx.current(conn, who)

    @app.post("/weekly/build", status_code=202)
    async def build(body: BuildIn, who: str = Depends(who_dep)):
        with db_guard:
            if not wx.get_prefs(conn, who)["enabled"]:
                return {"started": False, "reason": "off"}
            if not wx.begin_build(conn, who):
                return {"started": False, "reason": "running"}
        threading.Thread(target=run_build, args=(who, body.model_dump()), daemon=True, name="weekly-build").start()
        return {"started": True}

    def act(fn, pick_id: int, who: str):
        try:
            with db_guard:
                return fn(conn, who, pick_id)
        except wx.PickError as e:
            raise HTTPException(409 if "expired" in str(e) or "way" in str(e) else 404, str(e)) from None

    @app.post("/weekly/picks/{pick_id}/keep")
    async def keep(pick_id: int, who: str = Depends(who_dep)):
        return act(wx.keep, pick_id, who)

    @app.post("/weekly/picks/{pick_id}/skip")
    async def skip(pick_id: int, who: str = Depends(who_dep)):
        return act(wx.skip, pick_id, who)

    @app.post("/weekly/picks/{pick_id}/restore")
    async def restore(pick_id: int, who: str = Depends(who_dep)):
        return act(wx.restore, pick_id, who)

    @app.put("/weekly/prefs")
    async def prefs(body: PrefsIn, who: str = Depends(who_dep)):
        with db_guard:
            wx.set_prefs(conn, who, body.enabled, body.cap)
            return wx.current(conn, who)
