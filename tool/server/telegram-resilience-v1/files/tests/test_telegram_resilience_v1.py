"""telegram-resilience-v1: the watchdog stops a service whose Telegram login is gone; channel ids resolve after a fresh login."""

import asyncio

import pytest

from tgfetch import channel_fallback as cf, watchdog
from tgfetch.sources.base import SourceError


class FakeClient:
    def __init__(self, connected=True, reconnects=False):
        self.connected, self.reconnects, self.connects = connected, reconnects, 0

    def is_connected(self):
        return self.connected

    async def connect(self):
        self.connects += 1
        if self.reconnects:
            self.connected = True


class Alerts:
    def __init__(self):
        self.sent = []

    def _alert(self, title, text, icon):
        self.sent.append((title, text, icon))


def run(coro):
    return asyncio.run(asyncio.wait_for(coro, 5))


def test_a_dead_connection_stops_the_service_after_the_patience_and_tells_the_owner_once():
    t = [0.0]
    client, w = FakeClient(connected=False), Alerts()

    async def go():
        async def tick(*_):
            t[0] += 100
        real = asyncio.sleep
        asyncio.sleep = tick
        try:
            await watchdog.watch(client, w, gap_s=1, patience_s=250, clock=lambda: t[0])
        finally:
            asyncio.sleep = real
    with pytest.raises(RuntimeError, match="telegram connection lost"):
        run(go())
    assert client.connects >= 2 and len(w.sent) == 1


def test_a_connection_that_comes_back_keeps_the_service_running():
    client = FakeClient(connected=False, reconnects=True)

    async def go():
        task = asyncio.create_task(watchdog.watch(client, None, gap_s=0.01, patience_s=1))
        await asyncio.sleep(0.1)
        done = task.done()
        task.cancel()
        return done
    assert run(go()) is False and client.connects == 1


def test_a_healthy_connection_is_left_alone():
    client = FakeClient(connected=True)

    async def go():
        task = asyncio.create_task(watchdog.watch(client, None, gap_s=0.01, patience_s=0.02))
        await asyncio.sleep(0.1)
        task.cancel()
    run(go())
    assert client.connects == 0


class EntityClient:
    def __init__(self, known):
        self.known, self.dialogs, self.asked = set(known), 0, []

    async def get_entity(self, key):
        self.asked.append(key)
        if key not in self.known:
            raise ValueError("Could not find the input entity")
        return ("entity", key)

    async def get_dialogs(self):
        self.dialogs += 1
        self.known.add(-1001197115414)


def test_a_private_channel_id_loads_the_dialogs_once_after_a_fresh_login():
    c = EntityClient(known=[])
    assert run(cf.resolve(c, "-1001197115414")) == ("entity", -1001197115414)
    assert c.dialogs == 1


def test_a_public_name_goes_straight_through_and_an_unknown_name_still_fails():
    c = EntityClient(known=["FLACsongs"])
    assert run(cf.resolve(c, "FLACsongs")) == ("entity", "FLACsongs") and c.dialogs == 0
    with pytest.raises(SourceError, match="cannot be opened") as e:      # one bad channel skips only itself
        run(cf.resolve(c, "nosuchchannel"))
    assert c.dialogs == 0 and not e.value.retryable
    with pytest.raises(SourceError):
        run(cf.resolve(c, "-100999"))                                    # an id the account is not in
    assert c.dialogs == 1
