"""exportify-v1: the /exportify/* proxy (no network: requests is faked, as in test_fetch_proxy)."""

import base64

import pytest

from navivibe import fetch_access, hardening
from navivibe.fetch_signing import sign
from navivibe.tests.test_fetch_proxy import H, FakeResponse, client, fetcher  # noqa: F401  (fixtures)


def test_needs_a_sign_in_and_download_access(client, fetcher):
    assert client.get("/exportify/imports").status_code == 401
    nobody = {"Authorization": "Basic " + base64.b64encode(b"stranger:pw").decode()}
    r = client.get("/exportify/imports", headers=nobody)
    assert r.status_code == 403 and fetcher[0] == []


def test_the_csv_goes_on_signed_and_untouched(client, fetcher):
    calls, replies = fetcher
    replies[("POST", "/exportify/imports")] = FakeResponse(201, {"id": 4, "owned_ids": ["a"]})
    r = client.post("/exportify/imports", json={"name": "mix.csv", "csv": "Track Name,Artist Name(s)\nx,y\n"}, headers=H)
    assert r.status_code == 201 and r.get_json()["id"] == 4
    c = calls[0]
    assert c["json"] == {"name": "mix.csv", "csv": "Track Name,Artist Name(s)\nx,y\n"}
    assert c["headers"] == {"X-Internal-Token": "tok", **sign("hmac-secret", "admin", True, "POST", "/exportify/imports",
                                                              ts=int(c["headers"]["X-Ts"]))}


def test_a_big_csv_is_allowed_a_huge_one_is_not(client, fetcher):
    calls, replies = fetcher
    replies[("POST", "/exportify/imports")] = FakeResponse(201, {"id": 1})
    big = "x" * (2 * 1024 * 1024)                       # well past the 512 KB default, under the route's cap
    assert client.post("/exportify/imports", json={"name": "a", "csv": big}, headers=H).status_code == 201
    huge = "x" * (13 * 1024 * 1024)
    assert client.post("/exportify/imports", json={"name": "a", "csv": huge}, headers=H).status_code == 413
    assert len(calls) == 1


def test_bad_bodies_never_reach_tg_fetcher(client, fetcher):
    for body in ({}, {"csv": ""}, {"csv": 5}, {"csv": "   "}):
        assert client.post("/exportify/imports", json=body, headers=H).status_code == 400
    assert client.put("/exportify/imports/3/plan", json={"priority": "random"}, headers=H).status_code == 400
    assert client.put("/exportify/imports/3/plan", json={"per_night": "lots"}, headers=H).status_code == 400
    assert client.put("/exportify/imports/3/plan", json={"night_only": 1}, headers=H).status_code == 400
    assert client.post("/exportify/imports/3/start", json={"disk_floor_gb": True}, headers=H).status_code == 400
    assert client.post("/exportify/imports/3/playlist", json={"playlist_id": "../x"}, headers=H).status_code == 400
    assert client.post("/exportify/imports/3/explode", headers=H).status_code == 404
    assert client.get("/exportify/imports/3/songs/nope/0", headers=H).status_code == 404
    assert fetcher[0] == []


def test_every_route_forwards_to_its_own_path(client, fetcher):
    calls, replies = fetcher
    for method, url, path, body in [
        ("get", "/exportify/imports", "/exportify/imports", None),
        ("get", "/exportify/imports/7", "/exportify/imports/7", None),
        ("get", "/exportify/imports/7/songs/failed/2", "/exportify/imports/7/songs/failed/2", None),
        ("get", "/exportify/imports/7/owned", "/exportify/imports/7/owned", None),
        ("post", "/exportify/imports/7/estimate", "/exportify/imports/7/estimate", {"min_popularity": 40}),
        ("put", "/exportify/imports/7/plan", "/exportify/imports/7/plan", {"per_night": 50, "night_only": False}),
        ("post", "/exportify/imports/7/start", "/exportify/imports/7/start", {"disk_floor_gb": 30, "priority": "list"}),
        ("post", "/exportify/imports/7/pause", "/exportify/imports/7/pause", None),
        ("post", "/exportify/imports/7/cancel", "/exportify/imports/7/cancel", None),
        ("post", "/exportify/imports/7/retry-failed", "/exportify/imports/7/retry-failed", None),
        ("post", "/exportify/imports/7/playlist", "/exportify/imports/7/playlist", {"playlist_id": "pl-1"}),
        ("delete", "/exportify/imports/7", "/exportify/imports/7", None),
    ]:
        calls.clear()
        replies[(method.upper(), path)] = FakeResponse(200, {"ok": True})
        r = getattr(client, method)(url, headers=H, **({"json": body} if body is not None else {}))
        assert r.status_code == 200, (method, url, r.status_code)
        assert calls[0]["path"] == path and calls[0]["method"] == method.upper()


def test_tg_fetcher_errors_get_one_shape(client, fetcher):
    _, replies = fetcher
    replies[("POST", "/exportify/imports")] = FakeResponse(422, {"detail": "This isn't an Exportify playlist."})
    r = client.post("/exportify/imports", json={"name": "a", "csv": "a,b"}, headers=H)
    assert r.status_code == 422 and r.get_json() == {"error": "This isn't an Exportify playlist."}


def test_exportify_uses_the_fetch_rate_limits():
    assert hardening.route_class("/exportify/imports", "GET") == "fetch"
    assert hardening.route_class("/exportify/imports", "POST") == "fetch_write"
