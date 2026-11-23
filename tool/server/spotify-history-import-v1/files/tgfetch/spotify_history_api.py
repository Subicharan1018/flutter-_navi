"""
tgfetch/spotify_history_api.py  (spotify-history-import-v1)
────────────────────────────────────────────────────────────
The internal routes behind "Import Spotify History". Same caller rules as /history-import (signed by the NaviVibe
server, download access needed, no query strings). Undo, cancel and the list reuse /history-import/jobs/{id}/...

  POST /spotify-import/jobs                {format: extended|basic, total?}         -> 201 new / 200 the unfinished one
  GET  /spotify-import/jobs                the user's Spotify imports (newest first)
  GET  /spotify-import/jobs/{id}           progress
  POST /spotify-import/jobs/{id}/page      {plays: [{t, ms, title, artist, album?, end?, sk?}, ...≤1000]}
  POST /spotify-import/jobs/{id}/finish    close the job
"""

import asyncio
import logging
import time

from fastapi import Depends, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from tgfetch import history_import as hi
from tgfetch import spotify_history as sh
from tgfetch.library import load_library

log = logging.getLogger("tgfetch.spotify_history")
LIBRARY_TTL_S = 600


class JobIn(BaseModel):
    format: str = Field("extended", max_length=12)
    total: int | None = Field(None, ge=0, le=sh.MAX_TOTAL)


class PageIn(BaseModel):
    plays: list = Field(max_length=sh.MAX_PAGE)       # rows are validated one by one (a bad one is counted, not fatal)


def register_routes(app, settings, conn, who_dep, library_loader=None) -> None:
    sh.ensure_schema(conn)
    loader = library_loader or load_library
    cache = {"at": 0.0, "lib": None}

    async def library() -> list[dict]:
        if cache["lib"] is None or time.monotonic() - cache["at"] > LIBRARY_TTL_S:
            cache["lib"] = await asyncio.to_thread(loader)
            cache["at"] = time.monotonic()
        return cache["lib"]

    def own(job_id: int, who: str) -> dict:
        job = hi.get_job(conn, job_id, who)
        if job is None or job["source"] != sh.SOURCE:
            raise HTTPException(404, "no such import")
        return job

    @app.post("/spotify-import/jobs")
    async def create(body: JobIn, who: str = Depends(who_dep)):
        try:
            job, created = sh.create_job(conn, who, body.format, body.total)
        except hi.HistoryError as e:
            raise HTTPException(422, str(e)) from None
        return JSONResponse(sh.summary(conn, job), status_code=201 if created else 200)

    @app.get("/spotify-import/jobs")
    async def jobs(who: str = Depends(who_dep)):
        rows = conn.execute("SELECT * FROM history_jobs WHERE user=? AND source=? ORDER BY id DESC LIMIT 5",
                            (who, sh.SOURCE)).fetchall()
        return [sh.summary(conn, dict(r)) for r in rows]

    @app.get("/spotify-import/jobs/{job_id}")
    async def one(job_id: int, who: str = Depends(who_dep)):
        return sh.summary(conn, own(job_id, who))

    @app.post("/spotify-import/jobs/{job_id}/page")
    async def page(job_id: int, body: PageIn, who: str = Depends(who_dep)):
        own(job_id, who)
        lib = await library()
        try:
            return await asyncio.to_thread(sh.page, conn, job_id, who, lib, body.plays)
        except hi.Busy:
            raise HTTPException(409, "this import is already running") from None
        except hi.HistoryError as e:
            raise HTTPException(422, str(e)) from None

    @app.post("/spotify-import/jobs/{job_id}/finish")
    async def finish(job_id: int, who: str = Depends(who_dep)):
        own(job_id, who)
        return sh.finish(conn, job_id, who)
