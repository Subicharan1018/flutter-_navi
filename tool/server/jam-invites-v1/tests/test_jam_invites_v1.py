"""
Invite a friend into a Jam: who may invite whom, what the friend sees, and that
joining or declining clears the invite.

    cd /opt/shuffle-server
    venv/bin/python -m pytest navivibe/tests/test_jam_invites_v1.py -q
"""

import functools

import pytest
from flask import g, jsonify, request

from navivibe import jam, jam_invites
from navivibe.tests.test_social import Api, alice, app, bob, carol, clock, opt_in  # noqa: F401  (fixtures)


def fake_auth(f):
    @functools.wraps(f)
    def wrapper(*a, **kw):
        user = request.headers.get("X-User")
        if not user:
            return jsonify({"error": "auth"}), 401
        g.username = user
        return f(*a, **kw)
    return wrapper


@pytest.fixture(autouse=True)
def _routes(app, clock):
    store = jam_invites.InviteStore(jam.store, clock=clock)
    jam_invites.register_jam_invite_routes(app, fake_auth, jam.store, store)
    return store


def make_room(a, mode="jam"):
    return a.post("/social/jam", {"mode": mode}).get_json()["jam"]["code"]


def invite(a, code, to):
    return a.post(f"/social/jam/{code}/invite", {"to": to})


def inbox(a):
    return a.get("/social/jam/invites").get_json()["invites"]


def test_an_invited_friend_sees_it_and_one_join_clears_it(alice, bob):
    opt_in(alice, bob)
    code = make_room(alice)
    r = invite(alice, code, "bob")
    assert r.status_code == 200 and r.get_json() == {"invited": "Bob"}
    got = inbox(bob)
    assert len(got) == 1
    assert got[0]["code"] == code and got[0]["from"] == "alice" and got[0]["mode"] == "jam" and got[0]["members"] == 1
    assert got[0]["expires_at"] > got[0]["at"]
    assert bob.post("/social/jam/join", {"code": code}).status_code == 200
    assert inbox(bob) == []


def test_only_a_member_can_invite_and_the_code_stays_private(alice, bob, carol):
    opt_in(alice, bob, carol)
    code = make_room(alice)
    assert invite(bob, code, "carol").status_code == 403
    assert inbox(carol) == []
    assert invite(alice, "ZZZZZZ", "carol").status_code == 410


def test_a_member_can_pass_the_invite_on(alice, bob, carol):
    opt_in(alice, bob, carol)
    code = make_room(alice)
    bob.post("/social/jam/join", {"code": code})
    assert invite(bob, code, "carol").status_code == 200
    assert inbox(carol)[0]["from"] == "Bob"


def test_both_people_need_social_features(alice, bob):
    code = make_room(alice)
    assert invite(alice, code, "bob").status_code == 403            # alice has it off
    opt_in(alice)
    assert invite(alice, code, "bob").status_code == 404            # bob never did
    assert invite(alice, code, "nobody").status_code == 404
    assert invite(alice, code, "").status_code == 400


def test_not_yourself_not_someone_already_inside(alice, bob):
    opt_in(alice, bob)
    code = make_room(alice)
    assert invite(alice, code, "alice").status_code == 400
    bob.post("/social/jam/join", {"code": code})
    assert invite(alice, code, "bob").status_code == 409


def test_a_full_room_takes_no_more_invites(alice, bob, monkeypatch):
    opt_in(alice, bob)
    monkeypatch.setattr(jam, "MAX_MEMBERS", 1)
    code = make_room(alice)
    assert invite(alice, code, "bob").status_code == 409


def test_invites_expire_and_die_with_the_room(alice, bob, clock):
    opt_in(alice, bob)
    code = make_room(alice)
    invite(alice, code, "bob")
    clock.t += jam_invites.INVITE_TTL_S - 1
    alice.get(f"/social/jam/{code}")                                  # keeps the room alive
    assert len(inbox(bob)) == 1
    clock.t += 2
    assert inbox(bob) == []
    code2 = make_room(alice)
    invite(alice, code2, "bob")
    assert len(inbox(bob)) == 1
    alice.post(f"/social/jam/{code2}/end")
    assert inbox(bob) == []


def test_decline_removes_only_that_invite(alice, bob, carol):
    opt_in(alice, bob, carol)
    code = make_room(alice)
    invite(alice, code, "bob")
    invite(alice, code, "carol")
    assert bob.post(f"/social/jam/{code}/invite/decline").get_json() == {"declined": True}
    assert inbox(bob) == [] and len(inbox(carol)) == 1
    assert bob.post("/social/jam/ABCDEF/invite/decline").status_code == 200    # unknown code is harmless


def test_resending_refreshes_instead_of_stacking_and_is_throttled(alice, bob, clock):
    opt_in(alice, bob)
    code = make_room(alice)
    assert invite(alice, code, "bob").status_code == 200
    assert invite(alice, code, "bob").status_code == 429
    clock.t += jam_invites.PAIR_GAP_S + 1
    assert invite(alice, code, "bob").status_code == 200
    assert len(inbox(bob)) == 1 and inbox(bob)[0]["at"] == clock.t


def test_hourly_cap_per_sender(alice, app, monkeypatch):
    monkeypatch.setattr(jam_invites, "HOURLY_MAX", 3)
    apis = [Api(app, n) for n in ("u1", "u2", "u3", "u4")]
    opt_in(alice, *apis)
    code = make_room(alice)
    assert [invite(alice, code, f"u{i}").status_code for i in range(1, 5)] == [200, 200, 200, 429]


def test_a_friend_holds_at_most_a_few_invites(app, bob, monkeypatch):
    monkeypatch.setattr(jam_invites, "INBOX_MAX", 2)
    hosts = [Api(app, f"h{i}") for i in range(3)]
    opt_in(bob, *hosts)
    assert [invite(h, make_room(h), "bob").status_code for h in hosts] == [200, 200, 429]
    assert len(inbox(bob)) == 2


def test_signed_out_is_refused(app):
    c = app.test_client()
    assert c.get("/social/jam/invites").status_code == 401
    assert c.post("/social/jam/ABCDEF/invite", json={"to": "x"}).status_code == 401


def test_the_invites_route_does_not_shadow_the_room_route(alice):
    assert alice.get("/social/jam/invites").get_json() == {"invites": []}
