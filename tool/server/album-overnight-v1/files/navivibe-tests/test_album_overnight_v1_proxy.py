"""album-overnight-v1: the /exportify/album-overnight/* proxy (no network: requests is faked, as in test_fetch_proxy)."""

import base64

from navivibe import hardening
from navivibe.tests.test_fetch_proxy import H, FakeResponse, client, fetcher  # noqa: F401  (fixtures)


def test_needs_a_sign_in_and_download_access(client, fetcher):
    assert client.get("/exportify/album-overnight").status_code == 401
    nobody = {"Authorization": "Basic " + base64.b64encode(b"stranger:pw").decode()}
    r = client.get("/exportify/album-overnight", headers=nobody)
    assert r.status_code == 403 and fetcher[0] == []


def test_every_route_forwards_to_its_own_path(client, fetcher):
    calls, replies = fetcher
    for method, url, path, body, sent in [
        ("get", "/exportify/album-overnight", "/album-overnight/current", None, None),
        ("put", "/exportify/album-overnight/prefs", "/album-overnight/prefs",
         {"enabled": True, "film_only": False, "per_night": 20, "max_per_album": 10, "junk": 1},
         {"enabled": True, "film_only": False, "per_night": 20, "max_per_album": 10}),
        ("post", "/exportify/album-overnight/albums/7/cancel", "/album-overnight/albums/7/cancel", None, {}),
        ("post", "/exportify/album-overnight/cancel-all", "/album-overnight/cancel-all", None, {}),
    ]:
        calls.clear()
        replies[(method.upper(), path)] = FakeResponse(200, {"ok": True})
        r = getattr(client, method)(url, headers=H, **({"json": body} if body is not None else {}))
        assert r.status_code == 200, (method, url, r.status_code)
        assert calls[0]["path"] == path and calls[0]["method"] == method.upper()
        if sent is not None:
            assert calls[0]["json"] == sent


def test_bad_bodies_never_reach_tg_fetcher(client, fetcher):
    for body in ({"enabled": "yes"}, {"film_only": 1}, {"per_night": 33}, {"per_night": True}, {"max_per_album": "5"},
                 {"max_per_album": 7}):
        assert client.put("/exportify/album-overnight/prefs", json=body, headers=H).status_code == 400
    assert fetcher[0] == []


def test_it_uses_the_fetch_rate_limits():
    assert hardening.route_class("/exportify/album-overnight", "GET") == "fetch"
    assert hardening.route_class("/exportify/album-overnight/cancel-all", "POST") == "fetch_write"
