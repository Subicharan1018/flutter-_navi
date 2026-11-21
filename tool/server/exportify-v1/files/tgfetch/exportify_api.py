"""
tgfetch/exportify_api.py  (exportify-v1)
────────────────────────────────────────
The internal routes behind "Import a Spotify playlist from an Exportify CSV". Same caller rules
as every other route (api.py's `user`: signed by the NaviVibe server, needs download access).
No query strings: the signature covers the path only.

  POST /exportify/imports                  {name, csv}  → 201 the import's summary (+ owned_ids)
  GET  /exportify/imports                  the user's imports (summaries)
  GET  /exportify/imports/{id}             one summary: counts, plan, free space
  GET  /exportify/imports/{id}/songs/{state}/{page}   200 songs a page; state = all | owned |
                                           wishlist | queued | downloaded | failed | skipped_disk
  GET  /exportify/imports/{id}/owned       {"ids": [Navidrome song ids]} for a playlist
  POST /exportify/imports/{id}/estimate    {priority?, min_popularity?, ...} → what a fetch costs
  PUT  /exportify/imports/{id}/plan        {priority, min_popularity, per_night, disk_floor_gb, night_only}
  POST /exportify/imports/{id}/start | pause | cancel | retry-failed
  POST /exportify/imports/{id}/playlist    {playlist_id}: the app made the user's playlist from the owned songs
  DELETE /exportify/imports/{id}
"""

import asyncio
import logging
import time

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from tgfetch import exportify as ex
from tgfetch.library import load_library

log = logging.getLogger("tgfetch.exportify")


class ImportIn(BaseModel):
    name: str = Field("", max_length=200)
    csv: str = Field(min_length=1, max_length=ex.MAX_BYTES)


class PlanIn(BaseModel):
    priority: str | None = None
    min_popularity: int | None = Field(None, ge=0, le=100)
    per_night: int | None = Field(None, ge=1, le=1000)
    disk_floor_gb: float | None = Field(None, ge=1, le=2000)
    night_only: bool | None = None


class PlaylistIn(BaseModel):
    playlist_id: str = Field(min_length=1, max_length=64)


def register_routes(app, settings, conn, who_dep) -> None:
    ex.ensure_schema(conn)

    def free_gb() -> float:
        try:
            return round(ex.free_bytes(settings.library_dir) / 1e9, 1)
        except OSError:
            return 0.0

    def own(import_id: int, who: str) -> dict:
        imp = ex.get_import(conn, import_id, who)
        if imp is None:
            raise HTTPException(404, "no such import")
        return imp

    def out(imp: dict) -> dict:
        return ex.summary(conn, imp, free_gb())

    async def kick(who: str, import_id: int) -> None:
        """Run a tick now (the Start button): the first batch does not wait for the timer."""
        try:
            lib = await asyncio.to_thread(load_library)
        except Exception as e:                    # the library is a bonus check here, never a blocker
            log.warning("exportify: library not read: %s", type(e).__name__)
            lib = None
        ex.tick(conn, settings, user=who, library=lib, force=True, import_id=import_id)

    @app.post("/exportify/imports", status_code=201)
    async def create_import(body: ImportIn, who: str = Depends(who_dep)):
        try:
            rows, stats = ex.parse_csv(body.csv)
        except ex.ExportifyError as e:
            raise HTTPException(422, str(e)) from None
        library = await asyncio.to_thread(load_library)
        iid = ex.store_import(conn, who, body.name, rows, stats["skipped"],
                              lambda unique: ex.match_rows(unique, library))
        ex.prune_old(conn, who)
        res = out(ex.get_import(conn, iid, who))
        res["owned_ids"] = ex.owned_ids(conn, iid)
        return res

    @app.get("/exportify/imports")
    async def list_imports(who: str = Depends(who_dep)):
        rows = conn.execute("SELECT * FROM exportify_imports WHERE user=? ORDER BY id DESC", (who,)).fetchall()
        return [out(dict(r)) for r in rows]

    @app.get("/exportify/imports/{import_id}")
    async def get_import(import_id: int, who: str = Depends(who_dep)):
        imp = own(import_id, who)
        ex.settle(conn, import_id, time.time())
        return out(imp)

    @app.get("/exportify/imports/{import_id}/songs/{state}/{page}")
    async def songs(import_id: int, state: str, page: int, who: str = Depends(who_dep)):
        own(import_id, who)
        if state != "all" and state not in ex.STATES:
            raise HTTPException(404, "no such state")
        return {"songs": ex.songs_page(conn, import_id, state, page), "page": page, "size": 200}

    @app.get("/exportify/imports/{import_id}/owned")
    async def owned(import_id: int, who: str = Depends(who_dep)):
        own(import_id, who)
        return {"ids": ex.owned_ids(conn, import_id)}

    @app.post("/exportify/imports/{import_id}/estimate")
    async def estimate(import_id: int, body: PlanIn, who: str = Depends(who_dep)):
        imp = own(import_id, who)
        try:
            fields = ex.clean_plan(body.model_dump(exclude_none=True))
        except ex.ExportifyError as e:
            raise HTTPException(422, str(e)) from None
        plan = {**ex.get_plan(conn, import_id), **fields}
        plan["night_only"] = bool(plan["night_only"])
        return ex.estimate(conn, imp, plan, free_gb())

    @app.put("/exportify/imports/{import_id}/plan")
    async def put_plan(import_id: int, body: PlanIn, who: str = Depends(who_dep)):
        imp = own(import_id, who)
        try:
            fields = ex.clean_plan(body.model_dump(exclude_none=True))
        except ex.ExportifyError as e:
            raise HTTPException(422, str(e)) from None
        ex.set_plan(conn, import_id, fields)
        return out(imp)

    @app.post("/exportify/imports/{import_id}/start")
    async def start(import_id: int, body: PlanIn, who: str = Depends(who_dep)):
        imp = own(import_id, who)
        try:
            fields = ex.clean_plan(body.model_dump(exclude_none=True))
        except ex.ExportifyError as e:
            raise HTTPException(422, str(e)) from None
        ex.set_plan(conn, import_id, fields)
        ex.start(conn, import_id)
        await kick(who, import_id)
        return out(imp)

    @app.post("/exportify/imports/{import_id}/pause")
    async def pause(import_id: int, who: str = Depends(who_dep)):
        imp = own(import_id, who)
        ex.pause(conn, import_id)
        return out(imp)

    @app.post("/exportify/imports/{import_id}/cancel")
    async def cancel(import_id: int, who: str = Depends(who_dep)):
        imp = own(import_id, who)
        ex.cancel(conn, import_id)
        return out(imp)

    @app.post("/exportify/imports/{import_id}/retry-failed")
    async def retry_failed(import_id: int, who: str = Depends(who_dep)):
        imp = own(import_id, who)
        n = ex.retry_failed(conn, import_id)
        return {**out(imp), "retried": n}

    @app.post("/exportify/imports/{import_id}/playlist")
    async def set_playlist(import_id: int, body: PlaylistIn, who: str = Depends(who_dep)):
        own(import_id, who)
        conn.execute("UPDATE exportify_imports SET playlist_id=? WHERE id=?", (body.playlist_id, import_id))
        return {"ok": True}

    @app.delete("/exportify/imports/{import_id}")
    async def delete(import_id: int, who: str = Depends(who_dep)):
        own(import_id, who)
        ex.cancel(conn, import_id)
        ex.delete_import(conn, import_id)
        return {"ok": True}
