"""
cross-device-v1: `playOn` starts a queue on any of a user's devices (virtual time, fake sockets).

    cd /opt/shuffle-server
    venv/bin/python -m pytest navivibe/tests/test_cross_device_v1.py -q
"""

from navivibe import session
from navivibe.tests.test_session_sync import Conn, run, world  # noqa: F401  (fixtures)

NEW = ["n1", "n2", "n3"]


def play_on(conn, cmd_id, to, queue=NEW, index=1, **extra):
    return conn.send(type="cmd", cmdId=cmd_id, cmdType="playOn",
                     args={"toDeviceId": to, "queue": queue, "index": index, **extra})


def acks(conn, cmd_id):
    return [m for m in conn.ws.of("ack") if m["cmdId"] == cmd_id]


async def devices(phone_hosts=True, pc_proto=4):
    """phone (a OnePlus) and pc (Windows) of alice; the phone plays [a, b, c] at b."""
    phone = await Conn("tok-alice", "phone", "OnePlus CPH2581", proto=4, dtype="phone").open()
    pc = await Conn("tok-alice", "pc", "Windows PC (LAPTOP)", proto=pc_proto, dtype="desktop").open()
    room = session.hub.room("alice")
    if phone_hosts:
        await phone.send(type="transfer_playback", device_id="phone", force=True)
        await phone.send(type="state_update", track_id="b", position_ms=5000, is_playing=True,
                         queue=["a", "b", "c"], queue_index=1, epoch=room.epoch)
    return phone, pc, room


def test_an_idle_device_takes_the_queue_when_nobody_plays(world):
    async def go():
        phone, pc, room = await devices(phone_hosts=False)
        assert room.state["active_device"] is None
        await play_on(phone, "p1", "pc", track_title="New song", artist="Someone", cover_art_id="cv", duration_s=200)
        assert acks(phone, "p1")[-1]["status"] == "ok"
        s = room.state
        assert s["active_device"] == "pc" and s["track_id"] == "n2" and s["queue"] == NEW and s["queue_index"] == 1
        assert s["is_playing"] is True and s["track_title"] == "New song" and s["position_ms"] == 0
        assert pc.ws.last("state")["active_device"] == "pc"
        await phone.close(); await pc.close()
    run(go())


def test_the_old_host_keeps_playing_until_the_target_has_loaded_the_new_queue(world):
    hub, clock = world

    async def go():
        phone, pc, room = await devices()
        epoch = room.epoch
        await play_on(phone, "p1", "pc", track_title="New song")
        prep = pc.ws.last("exec")
        assert prep["action"] == "prepare" and prep["queue"] == NEW and prep["track_id"] == "n2"
        assert prep["queue_index"] == 1 and prep["position_ms"] == 0 and prep["play"] is True
        assert acks(phone, "p1")[-1].get("pending") is True
        # Nothing moved yet: the phone still hosts its own queue (no gap, never two at once).
        assert room.state["active_device"] == "phone" and room.state["queue"] == ["a", "b", "c"] and room.epoch == epoch
        clock.t += 1
        await pc.send(type="ready", transfer_id=prep["transfer_id"])
        s = room.state
        assert s["active_device"] == "pc" and room.epoch == epoch + 1
        assert s["queue"] == NEW and s["track_id"] == "n2" and s["is_playing"] is True
        assert s["position_ms"] < 2000                                     # from the start of the new song, not the old playhead
        assert phone.ws.last("state")["active_device"] == "pc"            # the phone learns it was deposed
        assert acks(phone, "p1")[-1]["status"] == "ok"
        await phone.close(); await pc.close()
    run(go())


def test_a_target_that_never_answers_leaves_the_old_queue_alone(world):
    hub, clock = world

    async def go():
        phone, pc, room = await devices()
        await play_on(phone, "p1", "pc")
        await pc.close()                                                   # the laptop went away while loading
        assert room.pending is None
        assert room.state["active_device"] == "phone" and room.state["queue"] == ["a", "b", "c"] and room.state["track_id"] == "b"
        assert acks(phone, "p1")[-1]["status"] == "rejected" and acks(phone, "p1")[-1]["reason"] == "target_offline"
        await phone.close()
    run(go())


def test_a_device_that_already_plays_is_told_to_start_the_queue(world):
    async def go():
        phone, pc, room = await devices()
        epoch = room.epoch
        await play_on(pc, "p1", "phone", index=2)
        assert acks(pc, "p1")[-1]["status"] == "ok"
        got = [m for m in phone.ws.of("command") if m["action"] == "set_queue"][-1]
        assert got["queue"] == NEW and got["index"] == 2 and got["from_device"] == "pc"
        assert room.epoch == epoch and room.state["active_device"] == "phone"
        await phone.close(); await pc.close()
    run(go())


def test_refusals(world):
    async def go():
        phone, pc, room = await devices()
        await play_on(phone, "off", "nobody")
        assert acks(phone, "off")[-1]["reason"] == "device_offline"
        await play_on(phone, "empty", "pc", queue=[], index=0)
        assert acks(phone, "empty")[-1]["reason"] == "bad_args"
        await play_on(phone, "range", "pc", index=7)
        assert acks(phone, "range")[-1]["reason"] == "bad_args"
        await play_on(phone, "types", "pc", queue=["ok", 5], index=0)
        assert acks(phone, "types")[-1]["reason"] == "bad_args"
        await play_on(phone, "long", "pc", queue=["x" * 65], index=0)
        assert acks(phone, "long")[-1]["reason"] == "bad_args"
        await play_on(phone, "big", "pc", queue=["t"] * (session.MAX_QUEUE + 1), index=0)
        assert acks(phone, "big")[-1]["reason"] == "bad_args"
        assert room.pending is None and room.state["queue"] == ["a", "b", "c"]
        await phone.close(); await pc.close()
    run(go())


def test_an_old_build_cannot_be_prepared(world):
    async def go():
        phone, pc, room = await devices(pc_proto=2)
        await play_on(phone, "p1", "pc")
        assert acks(phone, "p1")[-1]["reason"] == "device_too_old"
        assert room.state["active_device"] == "phone"
        await phone.close(); await pc.close()
    run(go())


def test_a_second_play_while_one_is_loading_is_told_to_wait(world):
    async def go():
        phone, pc, room = await devices()
        await play_on(phone, "p1", "pc")
        await play_on(phone, "p2", "pc", queue=["z"], index=0)
        assert acks(phone, "p2")[-1]["reason"] == "busy"
        assert room.pending["load"]["queue"] == NEW                         # the first one stands
        await phone.close(); await pc.close()
    run(go())


def test_a_retried_command_is_applied_once(world):
    async def go():
        phone, pc, room = await devices(phone_hosts=False)
        await play_on(phone, "p1", "pc")
        epoch = room.epoch
        await play_on(phone, "p1", "pc")
        assert acks(phone, "p1")[-1]["status"] == "duplicate" and room.epoch == epoch
        await phone.close(); await pc.close()
    run(go())


def test_other_accounts_devices_are_not_reachable(world):
    async def go():
        phone, pc, room = await devices()
        bob = await Conn("tok-bob", "bobpc", "Bob PC", proto=4, dtype="desktop").open()
        await play_on(phone, "p1", "bobpc")
        assert acks(phone, "p1")[-1]["reason"] == "device_offline"
        assert bob.ws.of("exec") == []
        await phone.close(); await pc.close(); await bob.close()
    run(go())


def test_plain_transfers_are_unchanged(world):
    hub, clock = world

    async def go():
        phone, pc, room = await devices()
        await phone.send(type="cmd", cmdId="t1", cmdType="transfer", args={"toDeviceId": "pc", "force": True})
        prep = pc.ws.last("exec")
        assert prep["queue"] == ["a", "b", "c"] and prep["track_id"] == "b"
        await pc.send(type="ready", transfer_id=prep["transfer_id"])
        assert room.state["active_device"] == "pc" and room.state["queue"] == ["a", "b", "c"]
        await phone.close(); await pc.close()
    run(go())
