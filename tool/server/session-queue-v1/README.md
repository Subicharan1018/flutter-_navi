# session-queue-v1: edit the queue from any device

For `/opt/shuffle-server/navivibe/session.py` (`navivibe-session.service`, :5501,
`wss://session.subimusic.me`) on subiserver. Built on the live file read on 16 Nov 2026
(sha256 `9a384c8d…c932bd`, 875 lines, protocol 3; baseline 55 session tests passed, 1 skipped).

Today only the device that plays (the host) can change its queue; a controller could only
replace the whole queue (`set_queue`). This adds protocol 4: four small, acked queue commands
any of the user's own devices can send. The host still owns its player; the server checks
each edit against the host's queue, applies it to the room so every device sees it at once,
and hands the host the resolved edit.

## Install

On the server as subi, from this folder:

    bash install.sh
    sudo systemctl restart navivibe-session

`install.sh` tests the patch on a scratch copy first, backs up `session.py`, patches it
(exact-match, idempotent: re-running changes nothing), runs the session tests on the live
tree, and puts the old file back if any fails. Rollback lines are printed at the end.

## Protocol 4

Connect with `proto=4` (the server clamps higher values; a protocol-4 app on an older server
is clamped to 3 and its queue commands are answered `unknown_type`).

Client → server, as proto-3 commands (`cmdType` also accepts the camelCase names):

    {"type": "cmd", "cmdId": "…", "cmdType": "queue_insert", "baseVersion": 41,
     "args": {"track_ids": ["id1", "id2"], "position": "next" | "end" | 5, "after_id": "id-above" | null}}
    {"type": "cmd", …, "cmdType": "queue_remove", "args": {"index": 4, "track_id": "id"}}
    {"type": "cmd", …, "cmdType": "queue_move",   "args": {"from": 4, "to": 2, "track_id": "id"}}
    {"type": "cmd", …, "cmdType": "queue_clear_upcoming", "args": {}}

Server → host (the device that plays), resolved to real indices:

    {"type": "command", "action": "queue_insert", "track_ids": [...], "index": 3, "from_device": "…", "from_name": "…"}
    {"type": "command", "action": "queue_remove", "index": 4, "track_id": "id", …}
    {"type": "command", "action": "queue_move", "from": 4, "to": 2, "track_id": "id", …}
    {"type": "command", "action": "queue_clear_upcoming", "index": 1, "track_id": "id-playing", …}

Then a `state` broadcast to every device (the new `queue` / `queue_index`, and
`caused_by: {deviceId, cmdId}` so the sender can retire its optimistic copy), then the sender's
`ack` (`version` = that state's version).

### Versions and races

`baseVersion` is the state version the sender last saw.

* **remove / move**: the song must be `track_id`. If it is still at `index`, that's it. If the
  queue moved meanwhile, the server finds the song's one place in the queue and uses that
  (rebased). Gone, or there twice: `ack.status = "stale"`, reason `queue_changed`, nothing changes.
  A stale move whose `to` fell off a shorter queue is clamped to the end.
* **insert at an index**: placed after `after_id` (the song just above the drop point;
  `null` = the very top) when that song is in the queue once, whatever the version. Without a
  usable `after_id` the bare index is used only when `baseVersion` is current; otherwise `stale`.
* **insert `next` / `end`, clear upcoming**: always meant "relative to what plays now", so they
  need no fresh version.
* A retried `cmdId` is answered `duplicate` and applied once (protocol 3 rule).

### Refusals (`ack.status = "rejected"`, `reason`)

| reason | when |
|---|---|
| `no_active_device` | nothing is playing on the account |
| `device_offline` | the host's socket is gone |
| `device_too_old` | the host connected with protocol < 4 (older app); it can still take `set_queue` |
| `queue_locked` | the host reported `queue_locked` (its queue follows a Jam; Jam rules apply there) |
| `is_current` | removing the song that is playing |
| `queue_full` | more than 1,000 songs |
| `bad_args` | missing/invalid ids or positions (≤ 200 ids per insert, ids ≤ 64 chars) |

### State

New state key `queue_locked` (null, or a reason such as `"jam"`), written by the host in its
`state_update`, like the other keys. Older apps ignore it.

Unchanged: protocol 1–3 frames, `set_queue`, `command` (proto 2), transfers, and per-user rooms
(an edit only ever reaches the same account's devices).

## Tests

`navivibe/tests/test_session_queue_v1.py`, 20 tests: each command's result and the frame the
host gets, the playing song's index following every edit, stale removes/moves/inserts rebased
or refused, a song queued twice, an older host refused while `set_queue` still works, a Jam-locked
host, bad arguments, a full queue, retries applied once, other users never seeing the edit.
On a scratch copy of the live tree with the patch (Python 3.10, fastapi 0.136.1): 75 passed,
1 skipped (55 existing + 20 new). `install.sh` was dry-run on a throwaway tree: install, re-run
(0 edits, idempotent) and a failing scratch test (nothing installed, file unchanged).
The app's real client was also run against the patched relay over real WebSockets
(`tools/session_sim/run_sim.py`, `test/integration/session_live_test.dart` scenario Q1, plus the
10 existing scenarios): all passed.
