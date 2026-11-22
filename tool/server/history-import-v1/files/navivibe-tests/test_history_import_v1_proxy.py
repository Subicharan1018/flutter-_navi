"""history-import-v1: the /history-import/* proxy (no network: requests is faked, as in test_fetch_proxy)."""

import base64

from navivibe.fetch_signing import sign
from navivibe.tests.test_fetch_proxy import H, FakeResponse, client, fetcher  # noqa: F401  (fixtures)

KEY = "0123456789abcdef0123456789abcdef"


def test_needs_a_sign_in_and_download_access(client, fetcher):
    assert client.get("/history-import/jobs").status_code == 401
    nobody = {"Authorization": "Basic " + base64.b64encode(b"stranger:pw").decode()}
    r = client.get("/history-import/jobs", headers=nobody)
    assert r.status_code == 403 and fetcher[0] == []


def test_create_goes_on_signed(client, fetcher):
    calls, replies = fetcher
    replies[("POST", "/history-import/jobs")] = FakeResponse(201, {"id": 3})
    r = client.post("/history-import/jobs", json={"source": "lastfm", "account": " sample_user ", "full": True}, headers=H)
    assert r.status_code == 201
    c = calls[0]
    assert c["json"] == {"source": "lastfm", "account": "sample_user", "full": True}
    assert c["headers"] == {"X-Internal-Token": "tok", **sign("hmac-secret", "admin", True, "POST", "/history-import/jobs",
                                                              ts=int(c["headers"]["X-Ts"]))}


def test_bad_bodies_never_reach_tg_fetcher(client, fetcher):
    calls, _ = fetcher
    for body in ({}, {"source": "spotify", "account": "x"}, {"source": "lastfm"}, {"source": "lastfm", "account": ""},
                 {"source": "lastfm", "account": "x" * 201}):
        assert client.post("/history-import/jobs", json=body, headers=H).status_code == 400
    assert client.post("/history-import/jobs/1/step", json={"secret": "short"}, headers=H).status_code == 400
    assert client.post("/history-import/jobs/1/step", json={"secret": ["x"]}, headers=H).status_code == 400
    assert client.post("/history-import/jobs/1/nope", headers=H).status_code == 404
    assert client.post("/history-import/jobs/x/step", json={}, headers=H).status_code == 404
    assert calls == []


def test_the_key_goes_through_once_and_is_not_logged(client, fetcher, caplog):
    import logging
    caplog.set_level(logging.DEBUG)
    calls, replies = fetcher
    replies[("POST", "/history-import/jobs/5/step")] = FakeResponse(200, {"fetched": 200, "done": False, "wait_s": 0})
    r = client.post("/history-import/jobs/5/step", json={"secret": KEY}, headers=H)
    assert r.status_code == 200 and r.get_json()["fetched"] == 200
    assert calls[0]["json"] == {"secret": KEY}
    assert KEY not in caplog.text
    replies[("POST", "/history-import/jobs/5/undo")] = FakeResponse(200, {"removed_plays": 4})
    assert client.post("/history-import/jobs/5/undo", headers=H).get_json() == {"removed_plays": 4}
    replies[("GET", "/history-import/jobs/5")] = FakeResponse(200, {"id": 5})
    assert client.get("/history-import/jobs/5", headers=H).get_json() == {"id": 5}
