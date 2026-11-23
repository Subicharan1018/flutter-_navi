"""spotify-history-import-v1: the /spotify-import/* proxy (no network: requests is faked, as in test_fetch_proxy)."""

import base64

from navivibe.fetch_signing import sign
from navivibe.hardening import route_class, RATE_LIMITS
from navivibe.tests.test_fetch_proxy import H, FakeResponse, client, fetcher  # noqa: F401  (fixtures)

PLAY = {"t": 1700000000, "ms": 4000, "title": "Neela Megam", "artist": "Aarav Kumar", "album": "Neela",
        "end": "fwdbtn", "sk": True}


def test_needs_a_sign_in_and_download_access(client, fetcher):
    assert client.post("/spotify-import/jobs", json={"format": "extended"}).status_code == 401
    nobody = {"Authorization": "Basic " + base64.b64encode(b"stranger:pw").decode()}
    r = client.post("/spotify-import/jobs", json={"format": "extended"}, headers=nobody)
    assert r.status_code == 403 and fetcher[0] == []


def test_create_goes_on_signed(client, fetcher):
    calls, replies = fetcher
    replies[("POST", "/spotify-import/jobs")] = FakeResponse(201, {"id": 3})
    r = client.post("/spotify-import/jobs", json={"format": "basic", "total": 1200, "junk": 1}, headers=H)
    assert r.status_code == 201
    c = calls[0]
    assert c["json"] == {"format": "basic", "total": 1200}
    assert c["headers"] == {"X-Internal-Token": "tok", **sign("hmac-secret", "admin", True, "POST", "/spotify-import/jobs",
                                                              ts=int(c["headers"]["X-Ts"]))}


def test_bad_bodies_never_reach_tg_fetcher(client, fetcher):
    calls, _ = fetcher
    assert client.post("/spotify-import/jobs", json={"format": "zip"}, headers=H).status_code == 400
    for body in ({}, {"plays": "x"}, {"plays": [PLAY] * 1001}):
        assert client.post("/spotify-import/jobs/1/page", json=body, headers=H).status_code == 400
    assert client.post("/spotify-import/jobs/x/page", json={"plays": []}, headers=H).status_code == 404
    assert calls == []


def test_a_page_passes_only_the_known_fields(client, fetcher):
    calls, replies = fetcher
    replies[("POST", "/spotify-import/jobs/5/page")] = FakeResponse(200, {"fetched": 2})
    dirty = {**PLAY, "ip_addr": "1.2.3.4", "conn_country": "IN", "platform": "android", "spotify_track_uri": "u"}
    r = client.post("/spotify-import/jobs/5/page", json={"plays": [dirty, "junk"]}, headers=H)
    assert r.status_code == 200 and r.get_json() == {"fetched": 2}
    assert calls[0]["json"] == {"plays": [PLAY, "junk"]}
    assert "1.2.3.4" not in str(calls[0]["json"])


def test_get_and_finish_are_forwarded(client, fetcher):
    calls, replies = fetcher
    replies[("GET", "/spotify-import/jobs/5")] = FakeResponse(200, {"id": 5})
    replies[("POST", "/spotify-import/jobs/5/finish")] = FakeResponse(200, {"done": True})
    replies[("GET", "/spotify-import/jobs")] = FakeResponse(200, [{"id": 5}])
    assert client.get("/spotify-import/jobs", headers=H).get_json() == [{"id": 5}]
    assert client.get("/spotify-import/jobs/5", headers=H).get_json() == {"id": 5}
    assert client.post("/spotify-import/jobs/5/finish", headers=H).get_json() == {"done": True}


def test_pages_have_their_own_rate_class_and_a_body_cap_for_a_full_page(client):
    assert route_class("/spotify-import/jobs/5/page", "POST") == "spotify_import"
    assert RATE_LIMITS["spotify_import"] == (20, 1.0)
    big = {"plays": [{**PLAY, "title": "x" * 300, "artist": "y" * 200, "album": "z" * 200}] * 1000}   # ~0.7 MB worst case
    r = client.post("/spotify-import/jobs/5/page", json=big, headers=H)
    assert r.status_code != 413
