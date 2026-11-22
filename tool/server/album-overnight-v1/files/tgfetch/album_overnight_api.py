"""
tgfetch/album_overnight_api.py  (album-overnight-v1)
────────────────────────────────────────────────────
Internal routes behind Settings > Album Overnight. Same caller rules as every other route (api.py's `user`:
signed by the NaviVibe server, download access needed). No query strings.

  GET  /album-overnight/current              prefs + the queue (albums, their tracks, where each is)
  PUT  /album-overnight/prefs                {enabled?, film_only?, per_night?, max_per_album?}
  POST /album-overnight/albums/{id}/cancel   drop what is not with the bot yet; the album never comes back
  POST /album-overnight/cancel-all
"""

from fastapi import Depends, HTTPException
from pydantic import BaseModel, Field

from tgfetch import album_overnight as ao


class PrefsIn(BaseModel):
    enabled: bool | None = None
    film_only: bool | None = None
    per_night: int | None = Field(None, ge=1, le=1000)
    max_per_album: int | None = Field(None, ge=1, le=100)


def register_routes(app, settings, conn, who_dep) -> None:
    ao.ensure_schema(conn)

    @app.get("/album-overnight/current")
    async def current(who: str = Depends(who_dep)):
        return ao.current(conn, who)

    @app.put("/album-overnight/prefs")
    async def prefs(body: PrefsIn, who: str = Depends(who_dep)):
        ao.set_prefs(conn, who, body.enabled, body.film_only, body.per_night, body.max_per_album)
        return ao.current(conn, who)

    @app.post("/album-overnight/albums/{album_id}/cancel")
    async def cancel(album_id: int, who: str = Depends(who_dep)):
        try:
            return ao.cancel_album(conn, who, album_id)
        except ao.AlbumError as e:
            raise HTTPException(404, str(e)) from None

    @app.post("/album-overnight/cancel-all")
    async def cancel_all(who: str = Depends(who_dep)):
        return ao.cancel_all(conn, who)
