"""home-dc-download-v1: a file on the home DC downloads in parallel on the main connection; other DCs borrow as before."""
import asyncio
from types import SimpleNamespace as NS

from telethon.tl import types

from tgfetch import parallel_download as pd


def doc(size, dc_id):
    return NS(document=types.Document(id=1, access_hash=2, file_reference=b"", date=None, mime_type="audio/flac",
                                      size=size, dc_id=dc_id, attributes=[]))


class Client:
    def __init__(self, home_dc, borrow_ok):
        self.session = NS(dc_id=home_dc)
        self._sender = object()
        self.borrow_ok, self.calls, self.returned, self.borrowed, self.fell_back = borrow_ok, [], [], [], False

    async def _borrow_exported_sender(self, dc):
        if not self.borrow_ok:
            raise ValueError("This occurs when an authorization is tried to be exported for the same data center")
        s = object()
        self.borrowed.append(s)
        return s

    async def _return_exported_sender(self, s):
        self.returned.append(s)

    async def _call(self, sender, req):
        self.calls.append((sender, req.offset))
        n = min(req.limit, SIZE - req.offset)
        return NS(bytes=bytes([req.offset // pd.PART_SIZE % 251]) * n)


SIZE = 5 * pd.PART_SIZE + 123


def run(client, tmp_path, dc_id, monkeypatch):
    async def fallback(*a, **k):
        client.fell_back = True
        return tmp_path / "fallback"
    monkeypatch.setattr(pd, "_fallback", fallback)
    out = asyncio.run(pd.fast_download(client, doc(SIZE, dc_id), tmp_path / "f.flac", connections=4))
    return out


def test_the_home_dc_downloads_in_parallel_on_the_main_connection(tmp_path, monkeypatch):
    c = Client(home_dc=5, borrow_ok=False)
    out = run(c, tmp_path, 5, monkeypatch)
    assert not c.fell_back and out == tmp_path / "f.flac"
    data = out.read_bytes()
    assert len(data) == SIZE
    assert all(data[i * pd.PART_SIZE] == i % 251 for i in range(5))        # every chunk in the right place
    assert {s for s, _ in c.calls} == {c._sender} and len(c.calls) == 6
    assert c.returned == []                                                # the main connection is never "returned"


def test_another_dc_still_borrows_and_returns_its_senders(tmp_path, monkeypatch):
    c = Client(home_dc=5, borrow_ok=True)
    run(c, tmp_path, 2, monkeypatch)
    assert not c.fell_back and len(c.borrowed) == 4 and set(c.returned) == set(c.borrowed)
    assert c._sender not in {s for s, _ in c.calls}


def test_a_failed_borrow_on_another_dc_still_falls_back(tmp_path, monkeypatch):
    c = Client(home_dc=5, borrow_ok=False)
    run(c, tmp_path, 2, monkeypatch)
    assert c.fell_back and c.calls == []
