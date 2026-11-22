# cross-device-v1: start a queue on any of your devices

For `/opt/shuffle-server/navivibe/session.py` (`navivibe-session.service`, :5501,
`wss://session.subimusic.me`). Built on the live file read on 22 Nov 2026 (1029 lines,
session-queue-v1 already installed; 76 session tests passed before, 86 with this).

## Why

Tapping a song on the phone while the Windows laptop plays now sends it to the laptop with
the existing `set_queue` command; that needs no server change. What the server could not do
is start a queue on a device that **isn't playing** (an idle laptop, one minimised to the
tray): `set_queue` is only obeyed by the host. This adds `playOn`, which does it with the
same two-phase hand-over as a normal transfer.

## Install

On the server as subi, from this folder:

    bash install.sh --check     # scratch copy only: applies the patch, runs the tests, installs nothing
    bash install.sh
    sudo systemctl restart navivibe-session

`install.sh` tests the patch on a scratch copy first, backs up `session.py`, patches it
(exact-match, idempotent: re-running changes nothing), runs the session tests on the live
tree, and puts the old file back if any fails. Rollback lines are printed at the end.
Until it is installed the app still works: playing on the device that already plays is
unchanged, and sending to another device answers "Your session server can't do that yet".

## `playOn`

Proto-3 command (the app sends it only when you pick a device that is not playing):

    {"type": "cmd", "cmdId": "…", "cmdType": "playOn",
     "args": {"toDeviceId": "pc", "queue": ["id1", "id2", "id3"], "index": 1,
              "track_title"?, "artist"?, "album"?, "cover_art_id"?, "duration_s"?}}

* The target must be online and speak protocol 3 (`device_offline`, `device_too_old` otherwise).
* If the target is the host already, it is sent `set_queue` (same as before), no epoch change.
* Otherwise the target gets `exec prepare` carrying **the new queue**, loads it paused and says
  `ready`; the current host keeps playing until then, then the room switches (one epoch bump):
  never two devices at once, no silent gap. If nobody is host (or it is gone) the target takes
  it at once.
* The room's queue/track change **only at commit**, so a timeout (`timeout`), a dropped target
  (`target_offline`) or a second play meanwhile (`busy`) leave everything as it was.
* It is a person's gesture: it bypasses the transfer hysteresis, and it carries no `baseEpoch`
  (the intent is absolute: this queue on that device).
* Validation: 1…1000 ids of ≤ 64 chars, `0 ≤ index < len` (`bad_args`).
* `cmdId` retries are applied once (`duplicate`), like every proto-3 command.

Unchanged: protocol 1–4 frames, transfers, `set_queue`, queue edits, per-user rooms.

## Tests

`navivibe/tests/test_cross_device_v1.py`, 10 tests: idle target takes the queue; host keeps
playing until ready, then the epoch moves and the room holds the new queue and position 0; a
target that drops leaves the old queue; target already playing gets `set_queue`; refusals
(offline, empty, out-of-range index, non-string ids, long ids, oversize queue, old build);
second play while loading is `busy`; retried command applied once; another account's device
is unreachable; plain transfers unchanged. On a scratch copy of the live file: 86 passed
(76 existing + 10 new); against the unpatched file 8 of the 10 new tests fail, so they test
the patch.
