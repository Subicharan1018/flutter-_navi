"""
session-queue-v1: any of a user's devices edits the host's queue (protocol 4).
Virtual time and fake sockets, no network.

    cd /opt/shuffle-server
    venv/bin/python -m pytest navivibe/tests/test_session_queue_v1.py -q
"""

from navivibe import session
from navivibe.tests.test_session_sync import Conn, run, world  # noqa: F401  (fixtures)


def cmd(conn, cmd_id, kind, base=None, **args):
    msg = {"type": "cmd", "cmdId": cmd_id, "cmdType": kind, "args": args}
    if base is not None:
        msg["baseVersion"] = base
    return conn.send(**msg)


def ack(conn, cmd_id):
    found = [m for m in conn.ws.of("ack") if m["cmdId"] == cmd_id]
    return found[-1] if found else None


def host_cmds(conn):
    return [m for m in conn.ws.of("command") if m["action"].startswith("queue_")]


async def pair(host_proto=4, queue=("a", "b", "c", "d"), index=1, **extra):
    """phone hosts `queue` playing `queue[index]`; pc is the controller."""
    phone = await Conn("tok-alice", "phone", "OnePlus CPH2581", proto=host_proto, dtype="phone").open()
    pc = await Conn("tok-alice", "pc", "Windows PC (LAPTOP)", proto=4, dtype="desktop").open()
    hub = session.hub
    await phone.send(type="transfer_playback", device_id="phone", force=True)
    await phone.send(type="state_update", track_id=queue[index] if queue else None, position_ms=0,
                     is_playing=True, queue=list(queue), queue_index=index, epoch=hub.room("alice").epoch, **extra)
    return phone, pc, hub.room("alice")


def version(room):
    return room.version


# ── each command ─────────────────────────────────────────────────────────────

def test_insert_next_lands_after_the_current_song_everywhere(world):
    async def go():
        phone, pc, room = await pair()
        await cmd(pc, "i1", "queue_insert", base=version(room), track_ids=["x", "y"], position="next")
        a = ack(pc, "i1")
        assert a["status"] == "ok" and a["version"] == room.version
        assert room.state["queue"] == ["a", "b", "x", "y", "c", "d"] and room.state["queue_index"] == 1
        sent = host_cmds(phone)[-1]
        assert sent == {**sent, "action": "queue_insert", "track_ids": ["x", "y"], "index": 2, "from_device": "pc"}
        st = pc.ws.last("state")
        assert st["queue"] == ["a", "b", "x", "y", "c", "d"]                   # the controller sees it at once
        assert st["caused_by"] == {"deviceId": "pc", "cmdId": "i1"} and st["version"] == a["version"]
        sent_order = [m["type"] for m in pc.ws.sent if m["type"] in ("state", "ack")][-2:]
        assert sent_order == ["state", "ack"]                                    # the state lands before the ack
        await phone.close(); await pc.close()
    run(go())


def test_insert_at_the_end_and_at_an_index_before_the_current_song(world):
    async def go():
        phone, pc, room = await pair()
        await cmd(pc, "i1", "queue_insert", base=version(room), track_ids=["z"], position="end")
        assert room.state["queue"][-1] == "z"
        await cmd(pc, "i2", "queue_insert", base=version(room), track_ids=["p"], position=0, after_id=None)
        assert room.state["queue"][:3] == ["p", "a", "b"] and room.state["queue_index"] == 2   # still on "b"
        assert host_cmds(phone)[-1]["index"] == 0
        # The song above the drop places it, even on a current version.
        await cmd(pc, "i3", "queue_insert", base=version(room), track_ids=["q"], position=1, after_id="b")
        assert room.state["queue"][:5] == ["p", "a", "b", "q", "c"] and host_cmds(phone)[-1]["index"] == 3
        await phone.close(); await pc.close()
    run(go())


def test_remove_drops_the_song_and_keeps_the_playing_one(world):
    async def go():
        phone, pc, room = await pair(index=2)
        await cmd(pc, "r1", "queue_remove", base=version(room), index=0, track_id="a")
        assert ack(pc, "r1")["status"] == "ok"
        assert room.state["queue"] == ["b", "c", "d"] and room.state["queue_index"] == 1
        assert host_cmds(phone)[-1] == {**host_cmds(phone)[-1], "action": "queue_remove", "index": 0, "track_id": "a"}
        await phone.close(); await pc.close()
    run(go())


def test_the_playing_song_cannot_be_removed(world):
    async def go():
        phone, pc, room = await pair()
        await cmd(pc, "r1", "queue_remove", base=version(room), index=1, track_id="b")
        assert ack(pc, "r1") == {**ack(pc, "r1"), "status": "rejected", "reason": "is_current"}
        assert room.state["queue"] == ["a", "b", "c", "d"] and not host_cmds(phone)
        await phone.close(); await pc.close()
    run(go())


def test_move_reorders_and_follows_the_playing_song(world):
    async def go():
        phone, pc, room = await pair()
        await cmd(pc, "m1", "queue_move", base=version(room), track_id="d", **{"from": 3, "to": 0})
        assert ack(pc, "m1")["status"] == "ok"
        assert room.state["queue"] == ["d", "a", "b", "c"] and room.state["queue_index"] == 2
        sent = host_cmds(phone)[-1]
        assert (sent["from"], sent["to"], sent["track_id"]) == (3, 0, "d")
        await cmd(pc, "m2", "queue_move", base=version(room), track_id="b", **{"from": 2, "to": 3})
        assert room.state["queue"] == ["d", "a", "c", "b"] and room.state["queue_index"] == 3
        await phone.close(); await pc.close()
    run(go())


def test_clear_upcoming_keeps_history_and_the_current_song(world):
    async def go():
        phone, pc, room = await pair()
        await cmd(pc, "c1", "queue_clear_upcoming", base=version(room))
        assert ack(pc, "c1")["status"] == "ok"
        assert room.state["queue"] == ["a", "b"] and room.state["queue_index"] == 1
        assert host_cmds(phone)[-1] == {**host_cmds(phone)[-1], "action": "queue_clear_upcoming", "index": 1, "track_id": "b"}
        before = room.version
        await cmd(pc, "c2", "queue_clear_upcoming", base=version(room))          # nothing left: a no-op
        assert ack(pc, "c2")["status"] == "ok" and room.version == before and len(host_cmds(phone)) == 1
        await phone.close(); await pc.close()
    run(go())


def test_camel_case_names_work_too(world):
    async def go():
        phone, pc, room = await pair()
        await cmd(pc, "k1", "queueInsert", base=version(room), track_ids=["x"], position="end")
        await cmd(pc, "k2", "queueClearUpcoming", base=version(room))
        assert [ack(pc, k)["status"] for k in ("k1", "k2")] == ["ok", "ok"]
        await phone.close(); await pc.close()
    run(go())


# ── stale versions: rebased by id, or refused ────────────────────────────────

def test_a_stale_remove_is_rebased_by_track_id(world):
    async def go():
        phone, pc, room = await pair(index=0)
        seen = version(room)
        # The host's queue changes before the controller's edit arrives.
        await phone.send(type="state_update", queue=["new", "a", "b", "c", "d"], queue_index=1, epoch=room.epoch)
        await cmd(pc, "r1", "queue_remove", base=seen, index=2, track_id="c")    # "c" is at 3 now
        assert ack(pc, "r1")["status"] == "ok"
        assert room.state["queue"] == ["new", "a", "b", "d"]
        assert host_cmds(phone)[-1]["index"] == 3                                 # the host gets the real place
        await phone.close(); await pc.close()
    run(go())


def test_a_stale_remove_of_a_song_that_is_gone_is_refused(world):
    async def go():
        phone, pc, room = await pair(index=0)
        seen = version(room)
        await phone.send(type="state_update", queue=["a", "b", "d"], queue_index=0, epoch=room.epoch)
        await cmd(pc, "r1", "queue_remove", base=seen, index=2, track_id="c")
        assert ack(pc, "r1") == {**ack(pc, "r1"), "status": "stale", "reason": "queue_changed"}
        assert room.state["queue"] == ["a", "b", "d"] and not host_cmds(phone)
        await phone.close(); await pc.close()
    run(go())


def test_a_stale_edit_of_a_song_queued_twice_is_refused(world):
    async def go():
        phone, pc, room = await pair(queue=("a", "b", "c", "c"), index=0)
        seen = version(room)
        await phone.send(type="state_update", queue=["n", "a", "b", "c", "c"], queue_index=1, epoch=room.epoch)
        await cmd(pc, "m1", "queue_move", base=seen, track_id="c", **{"from": 2, "to": 1})
        assert ack(pc, "m1")["status"] == "stale"                                # which "c"? can't tell
        await phone.close(); await pc.close()
    run(go())


def test_a_stale_insert_at_an_index_rebases_on_the_song_above_it(world):
    async def go():
        phone, pc, room = await pair(index=0)
        seen = version(room)
        await phone.send(type="state_update", queue=["n", "a", "b", "c", "d"], queue_index=1, epoch=room.epoch)
        await cmd(pc, "i1", "queue_insert", base=seen, track_ids=["x"], position=2, after_id="b")
        assert ack(pc, "i1")["status"] == "ok"
        assert room.state["queue"] == ["n", "a", "b", "x", "c", "d"]
        await cmd(pc, "i2", "queue_insert", base=seen, track_ids=["y"], position=2)   # no anchor: can't rebase
        assert ack(pc, "i2")["status"] == "stale"
        await cmd(pc, "i3", "queue_insert", base=seen, track_ids=["y"], position=9, after_id="gone")
        assert ack(pc, "i3")["status"] == "stale"
        await phone.close(); await pc.close()
    run(go())


def test_a_stale_move_clamps_its_target_to_the_shorter_queue(world):
    async def go():
        phone, pc, room = await pair(index=0)
        seen = version(room)
        await phone.send(type="state_update", queue=["a", "b", "d"], queue_index=0, epoch=room.epoch)
        await cmd(pc, "m1", "queue_move", base=seen, track_id="b", **{"from": 1, "to": 3})
        assert ack(pc, "m1")["status"] == "ok" and room.state["queue"] == ["a", "d", "b"]
        await phone.close(); await pc.close()
    run(go())


def test_next_and_end_need_no_fresh_version(world):
    async def go():
        phone, pc, room = await pair()
        await cmd(pc, "i1", "queue_insert", base=0, track_ids=["x"], position="next")
        await cmd(pc, "i2", "queue_insert", track_ids=["y"], position="end")
        assert [ack(pc, k)["status"] for k in ("i1", "i2")] == ["ok", "ok"]
        assert room.state["queue"] == ["a", "b", "x", "c", "d", "y"]
        await phone.close(); await pc.close()
    run(go())


# ── refusals ─────────────────────────────────────────────────────────────────

def test_an_older_host_is_refused_and_set_queue_still_works(world):
    async def go():
        phone, pc, room = await pair(host_proto=3)
        await cmd(pc, "i1", "queue_insert", base=version(room), track_ids=["x"], position="next")
        assert ack(pc, "i1")["reason"] == "device_too_old" and room.state["queue"] == ["a", "b", "c", "d"]
        await cmd(pc, "s1", "setQueue", queue=["x", "y"], index=0)              # the whole-queue replace stays
        assert ack(pc, "s1")["status"] == "ok"
        assert phone.ws.last("command")["action"] == "set_queue"
        await phone.close(); await pc.close()
    run(go())


def test_a_host_whose_queue_follows_a_jam_refuses_edits(world):
    async def go():
        phone, pc, room = await pair(queue_locked="jam")
        await cmd(pc, "i1", "queue_insert", base=version(room), track_ids=["x"], position="next")
        assert ack(pc, "i1") == {**ack(pc, "i1"), "status": "rejected", "reason": "queue_locked"}
        await phone.send(type="state_update", queue_locked=None, epoch=room.epoch)   # left the Jam
        await cmd(pc, "i2", "queue_insert", base=version(room), track_ids=["x"], position="next")
        assert ack(pc, "i2")["status"] == "ok"
        await phone.close(); await pc.close()
    run(go())


def test_nobody_playing_and_bad_args_are_refused(world):
    async def go():
        pc = await Conn("tok-alice", "pc", "Windows PC", proto=4, dtype="desktop").open()
        await cmd(pc, "n1", "queue_clear_upcoming")
        assert ack(pc, "n1")["reason"] == "no_active_device"
        await pc.close()
        phone, pc, room = await pair()
        for cid, kind, args in [
            ("b1", "queue_insert", {"track_ids": [], "position": "next"}),
            ("b2", "queue_insert", {"track_ids": [1, 2], "position": "next"}),
            ("b3", "queue_insert", {"track_ids": ["x"], "position": "middle"}),
            ("b4", "queue_insert", {"track_ids": ["x"], "position": 99}),
            ("b5", "queue_move", {"from": 0, "track_id": "a"}),
            ("b6", "queue_insert", {"track_ids": ["x"] * 201, "position": "end"}),
        ]:
            await cmd(pc, cid, kind, base=version(room), **args)
            assert ack(pc, cid) == {**ack(pc, cid), "status": "rejected", "reason": "bad_args"}, cid
        assert room.state["queue"] == ["a", "b", "c", "d"] and not host_cmds(phone)
        await phone.close(); await pc.close()
    run(go())


def test_a_full_queue_refuses_more(world, monkeypatch):
    monkeypatch.setattr(session, "MAX_QUEUE", 5)

    async def go():
        phone, pc, room = await pair()
        await cmd(pc, "f1", "queue_insert", base=version(room), track_ids=["x", "y"], position="end")
        assert ack(pc, "f1")["reason"] == "queue_full"
        await phone.close(); await pc.close()
    run(go())


def test_a_retried_edit_is_applied_once(world):
    async def go():
        phone, pc, room = await pair()
        await cmd(pc, "d1", "queue_insert", base=version(room), track_ids=["x"], position="end")
        await cmd(pc, "d1", "queue_insert", base=version(room), track_ids=["x"], position="end")
        assert ack(pc, "d1")["status"] == "duplicate"
        assert room.state["queue"].count("x") == 1 and len(host_cmds(phone)) == 1
        await phone.close(); await pc.close()
    run(go())


def test_another_users_devices_never_see_the_edit(world):
    async def go():
        phone, pc, room = await pair()
        bob = await Conn("tok-bob", "bob-phone", "Pixel", proto=4).open()
        await cmd(pc, "i1", "queue_insert", base=version(room), track_ids=["x"], position="next")
        assert all("x" not in (m.get("queue") or []) for m in bob.ws.of("state")) and not bob.ws.of("command")
        await bob.close(); await phone.close(); await pc.close()
    run(go())


def test_a_proto4_client_is_clamped_by_an_older_relay_rule_no_more(world):
    async def go():
        c = await Conn("tok-alice", "d", "Pixel", proto=9).open()
        assert session.hub.room("alice").devices["d"].proto == session.MAX_PROTO == 4
        await c.close()
    run(go())
