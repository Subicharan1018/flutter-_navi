"""
tgfetch/history_import_api.py  (history-import-v1)
──────────────────────────────────────────────────
The internal routes behind "Import your listening history". Same caller rules as /exportify (signed by the
NaviVibe server, download access needed, no query strings).

  POST /history-import/jobs            {source: listenbrainz|lastfm, account, full?}  → 201 new / 200 the unfinished one
  GET  /history-import/jobs            the user's jobs (newest first)
  GET  /history-import/jobs/{id}       one job's progress
  POST /history-import/jobs/{id}/step  {secret?}  read one page → progress + done + wait_s (+ fatal)
  POST /history-import/jobs/{id}/cancel
  POST /history-import/jobs/{id}/undo  take back everything this source's imports wrote
"""

import asyncio
import logging
import time

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from tgfetch import history_import as hi
from tgfetch.library import load_library

log = logging.getLogger("tgfetch.history_import")
LIBRARY_TTL_S = 600


class JobIn(BaseModel):
    source: str = Field(max_length=20)
    account: str = Field(max_length=200)
    full: bool = False


class StepIn(BaseModel):
    secret: str | None = Field(None, max_length=80)


def register_routes(app, settings, conn, who_dep, library_loader=None) -> None:
    hi.ensure_schema(conn)
    loader = library_loader or load_library
    cache = {"at": 0.0, "lib": None}

    async def library() -> list[dict]:
        if cache["lib"] is None or time.monotonic() - cache["at"] > LIBRARY_TTL_S:
            cache["lib"] = await asyncio.to_thread(loader)
            cache["at"] = time.monotonic()
        return cache["lib"]

    def own(job_id: int, who: str) -> dict:
        job = hi.get_job(conn, job_id, who)
        if job is None:
            raise HTTPException(404, "no such import")
        return job

    @app.post("/history-import/jobs")
    async def create(body: JobIn, who: str = Depends(who_dep)):
        try:
            job, created = hi.create_job(conn, who, body.source, body.account, body.full)
        except hi.HistoryError as e:
            raise HTTPException(422, str(e)) from None
        from fastapi.responses import JSONResponse
        return JSONResponse(hi.summary(conn, job), status_code=201 if created else 200)

    @app.get("/history-import/jobs")
    async def jobs(who: str = Depends(who_dep)):
        rows = conn.execute("SELECT * FROM history_jobs WHERE user=? ORDER BY id DESC LIMIT 20", (who,)).fetchall()
        return [hi.summary(conn, dict(r)) for r in rows]

    @app.get("/history-import/jobs/{job_id}")
    async def one(job_id: int, who: str = Depends(who_dep)):
        return hi.summary(conn, own(job_id, who))

    @app.post("/history-import/jobs/{job_id}/step")
    async def step(job_id: int, body: StepIn, who: str = Depends(who_dep)):
        own(job_id, who)
        lib = await library()
        try:
            # The request's secret goes straight to the one request that needs it; it is not kept.
            return await asyncio.to_thread(hi.step, conn, job_id, who, lib, body.secret)
        except hi.Busy:
            raise HTTPException(409, "this import is already running") from None
        except hi.HistoryError as e:
            raise HTTPException(422, str(e)) from None

    @app.post("/history-import/jobs/{job_id}/cancel")
    async def cancel(job_id: int, who: str = Depends(who_dep)):
        job = own(job_id, who)
        hi.cancel(conn, job)
        return hi.summary(conn, own(job_id, who))

    @app.post("/history-import/jobs/{job_id}/undo")
    async def undo(job_id: int, who: str = Depends(who_dep)):
        job = own(job_id, who)
        try:
            return await asyncio.to_thread(hi.undo, conn, job)
        except hi.HistoryError as e:
            raise HTTPException(422, str(e)) from None
