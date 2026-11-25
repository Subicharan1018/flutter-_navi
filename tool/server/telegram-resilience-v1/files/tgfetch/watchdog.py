"""
tgfetch/watchdog.py  (telegram-resilience-v1)
─────────────────────────────────────────────
On 24 Nov 2026 the Telegram login died at 13:52 UTC and tg-fetcher kept running, healthy-looking, for eleven hours:
/health said `telegram: false` but nothing acted on it, and every song waited 2½ minutes for a bot it could not reach.

`watch` runs next to the worker. Every WATCHDOG_GAP_S (30) it looks at the connection; when it is down it tries to
connect again, and once it has been down WATCHDOG_PATIENCE_S (300) it raises: the service stops with a clear line in the
journal and systemd restarts it (a login that was revoked then stops at "Telegram session not logged in. Run
spike.login", which is the truth). The owner is told once, through the worker's alert, when it first goes down.
"""

import asyncio
import logging
import os
import time

log = logging.getLogger(__name__)

GAP_S = float(os.getenv("WATCHDOG_GAP_S", "30"))
PATIENCE_S = float(os.getenv("WATCHDOG_PATIENCE_S", "300"))


async def watch(client, worker=None, gap_s: float | None = None, patience_s: float | None = None, clock=time.monotonic):
    gap = GAP_S if gap_s is None else gap_s
    patience = PATIENCE_S if patience_s is None else patience_s
    down_since = None
    told = False
    while True:
        await asyncio.sleep(gap)
        if client.is_connected():
            if down_since is not None:
                log.info("watchdog: Telegram is back after %.0fs", clock() - down_since)
            down_since, told = None, False
            continue
        now = clock()
        if down_since is None:
            down_since = now
            log.warning("watchdog: Telegram connection is down; trying to reconnect")
        try:
            await client.connect()
        except Exception as e:
            log.warning("watchdog: reconnect failed (%s)", type(e).__name__)
        if client.is_connected():
            continue
        if not told and worker is not None:
            told = True
            try:
                worker._alert("Search online", "Telegram is not connected: downloads are paused.", "warning")
            except Exception:
                pass
        if now - down_since >= patience:
            log.error("watchdog: Telegram has been down for %.0fs; stopping so systemd restarts the service", now - down_since)
            raise RuntimeError("telegram connection lost")
