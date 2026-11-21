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

import logging
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


def register_routes(app, settings, conn, who_dep) -> None:
    wx.ensure_schema(conn)

    def run_build(who: str, seeds: dict) -> None:
        """Runs in its own thread: a build makes about 40 slow outside calls and must not hold the service."""
        picks, err = 0, None
        try:
            try:
                library = load_library()
            except Exception as e:           # without the library every song looks new: do not build
                log.warning("weekly: library not read (%s)", type(e).__name__)
                raise RuntimeError("library") from None
            picks = wx.build(conn, who, seeds, make_sources(), library)
        except Exception as e:                                  # a failed build must never take the service down
            err = f"The list couldn't be made ({type(e).__name__}). It will try again."
            log.warning("weekly: build failed (%s)", type(e).__name__)
        wx.finish_build(conn, who, picks, err)

    @app.get("/weekly/current")
    async def current(who: str = Depends(who_dep)):
        return wx.current(conn, who)

    @app.post("/weekly/build", status_code=202)
    async def build(body: BuildIn, who: str = Depends(who_dep)):
        if not wx.get_prefs(conn, who)["enabled"]:
            return {"started": False, "reason": "off"}
        if not wx.begin_build(conn, who):
            return {"started": False, "reason": "running"}
        threading.Thread(target=run_build, args=(who, body.model_dump()), daemon=True, name="weekly-build").start()
        return {"started": True}

    def act(fn, pick_id: int, who: str):
        try:
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
        wx.set_prefs(conn, who, body.enabled, body.cap)
        return wx.current(conn, who)
