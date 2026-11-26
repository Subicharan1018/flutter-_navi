"""
tgfetch/bot_verify.py  (fetch-waits-v1)
───────────────────────────────────────
When the music bot asks for a human check, songs the public channels do not have must WAIT for the owner, not end
`failed` (they did, and had to be retried by hand). And when the owner taps verify, the waiting batches must start at
once, not on the next 30-minute retry or 5-minute probe.

  wake_waiting(conn)   batches parked by "the bot isn't answering" (worker.MAINT_TEXT) run now
  install(client, worker, settings)
                       - the flag clearing (human_check.ON_CLEAR) wakes them
                       - any message or edit from the bot that is not itself a human check clears the flag, so
                         "I tapped verify" is noticed within a second instead of at the next probe
"""

import logging
import time

from tgfetch import db

log = logging.getLogger(__name__)

WAIT_TEXT = ("not on the Telegram channels; the music bot is waiting for a human check — "
             "verify it in Telegram and this song starts by itself")


def wake_waiting(conn) -> int:
    """Batches deferred because the bot did not answer are due now. Returns how many."""
    from tgfetch.worker import MAINT_TEXT
    cur = conn.execute("UPDATE batches SET retry_at=0, updated_at=? WHERE status='queued' AND error=? AND retry_at>?",
                       (time.time(), MAINT_TEXT, time.time()))
    try:
        conn.commit()
    except Exception:
        pass
    return cur.rowcount


def install(client, worker, settings) -> None:
    from telethon import events
    from tgfetch import human_check as hc
    human = getattr(worker.source, "human", None)
    if human is None:
        return
    conn = db.connect(settings.db_path)

    def on_clear():
        n = wake_waiting(conn)
        log.info("bot-verify: the bot answers again; %d waiting batch(es) start now", n)

    hc.ON_CLEAR.append(on_clear)

    async def on_bot(event):
        try:
            if human.flagged and not hc.is_human_check(event.message):
                log.info("bot-verify: the bot sent a normal message while flagged: clearing the human-check flag")
                human.clear()
        except Exception as e:
            log.warning("bot-verify: handler error (%s)", type(e).__name__)

    for kind in (events.NewMessage, events.MessageEdited):
        client.add_event_handler(on_bot, kind(from_users=settings.source, incoming=True))
