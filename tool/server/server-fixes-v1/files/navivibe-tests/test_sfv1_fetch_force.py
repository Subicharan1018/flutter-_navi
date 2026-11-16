"""server-fixes-v1: the /fetch proxy forwards "Search online anyway" (force)."""

import pytest

from navivibe.tests.test_fetch_proxy import H, FakeResponse, client, fetcher  # noqa: F401  (fixtures)


@pytest.mark.parametrize("url,body", [
    ("/fetch/searches", {"query": "pondatti", "force": True}),
    ("/fetch/searches?force=1", {"query": "pondatti"}),
    ("/fetch/searches?force=true", {"query": "pondatti", "kind": "song"}),
])
def test_force_is_forwarded_from_body_or_query(client, fetcher, url, body):
    calls, replies = fetcher
    replies[("POST", "/searches")] = FakeResponse(202, {"search_id": 9})
    assert client.post(url, json=body, headers=H).status_code == 202
    assert calls[0]["json"]["force"] is True and calls[0]["json"]["query"] == "pondatti"


@pytest.mark.parametrize("url,body", [
    ("/fetch/searches", {"query": "pondatti"}),
    ("/fetch/searches", {"query": "pondatti", "force": False}),
    ("/fetch/searches?force=0", {"query": "pondatti"}),
    ("/fetch/searches", {"query": "pondatti", "force": "yes please"}),
])
def test_no_force_unless_asked(client, fetcher, url, body):
    calls, replies = fetcher
    replies[("POST", "/searches")] = FakeResponse(202, {"search_id": 9})
    client.post(url, json=body, headers=H)
    assert "force" not in calls[0]["json"]
