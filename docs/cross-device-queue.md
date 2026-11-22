# Cross-device control: queue and "where does it play"

Owner's report: music plays on the Windows laptop; on the phone the laptop's queue can't be
controlled or replaced, tapping a song plays it on the phone, and switching to Windows from the
phone doesn't work.

## Findings (what happened before this change)

Traced by reading the app (`player_provider.dart`, `session_sync_service.dart`,
`remote_queue_provider.dart`, `queue_actions.dart`, `devices_sheet.dart`) and the **live server file**
(`/opt/shuffle-server/navivibe/session.py`, read-only copy, 1029 lines, session-queue-v1 already on it).
Not run on a real Windows machine; the server behaviour was run on a scratch copy.

| case | what happened | why |
| --- | --- | --- |
| Phone **passive** (Windows plays), tap a song / Play on an album or playlist | The phone **took playback**: Windows was deposed and the song played on the phone. | Every list calls `PlayerNotifier.setQueue` / `playPlaylist` (about 40 call sites). They always act on *this* device; `_ensureActiveDevice` sees a touch, so the claim is allowed and forced. There was no path that sent a queue to the device that plays. |
| Phone passive, **edit** the queue (play next, add, reorder, remove, clear, jump) | Worked **if** the host speaks protocol 4 (session-queue-v1 is installed, and `queue_actions.dart` routes them when passive). | The four edits and `play_track` already went to the host. A host older than protocol 4 answers `device_too_old` with a generic message. |
| Phone passive, **replace** the queue (Play on a list) | Not possible: see row 1. The only whole-queue command, `set_queue`, was never called from the UI. | `set_queue` existed in the client and server but nothing used it. It also changes nothing on screen until the host reports back. |
| Phone passive, tap Windows (the device that plays) in the Playing-on sheet | Nothing: the host's row is disabled. | Correct (it already plays); but there was also no way to say "send new music there", which is what the owner wanted from that row. |
| Phone **active**, Windows idle/minimised, pick Windows in the sheet | A two-phase transfer: the server sends `exec prepare` with the room's queue; Windows loads it and answers `ready`; the server commits. | Works while Windows' socket is up (a minimised window's Dart isolate keeps running; a quit app is `device_offline`). **Failures were silent**: if Windows can't prepare (no song in the room state, load error) nothing is sent back, the server times out after 5 s with `timeout`, and the app showed nothing. Remote buttons showed errors only while the Remote view was open. |
| **Windows → phone** ("Play here", or the phone row) | Works: a forced claim; the server prepares the phone with the host's queue and position. | Position and the whole queue travel (`prepare` carries `position_ms`, `queue`, `queue_index`). |
| Sending a **new** queue to a device that is **not** playing (idle laptop) | Impossible. | `set_queue` is obeyed only by the host (`_onRemoteCommand` returns for a non-host), and the server has no command that starts a queue on another device. |
| Failure feedback | `That didn't work` for most refusals; none for `timeout`, `target_offline`, `busy`. | `CommandResult.message` had no text for them, and the only listener was the Remote view. |

Root cause of the report: **plays were always local**, and the Playing-on sheet could only move what
already plays. Nothing could choose a destination for new music.

## What changed

**Routing** (`lib/providers/play_route.dart`, called from `setQueue` and `playPlaylist`):

1. A play started by a person (a touch or key just happened; automatic code is never routed)
   goes to the **device that plays now** when it isn't this one, as `set_queue` to it. The phone shows the
   new queue in the remote queue view straight away and settles when the host reports it (optimistic with
   reconciliation: a refusal puts the old queue back).
2. A toast says **"Playing on Windows PC"** with a **Play here** action: starts the same songs on this
   device and takes playback (a forced claim, so the other device stops: never both at once).
3. The Playing-on sheet has **"Send new music to"** chips (every device). The pick lasts until playback
   changes hands. A device that isn't playing gets the queue through the new server command `playOn`:
   it loads the queue first, the playing device keeps playing until it is ready, then it takes over.
   "This device" plays here as before.
4. Jam and Flow play here by opening a claim window (`permitClaim`); restore/autoplay have no touch behind
   them and are never routed.
5. Queue edits (play next, add, reorder, remove, clear, jump) already applied to the playing device's
   queue; unchanged.
6. Failures are said in words anywhere in the app (`device went offline`, `didn't answer`, `needs the
   latest NaviVibe`...), through one notice listener on the mini player, not only on the Remote view.
7. Moving playback phone↔Windows is unchanged (it worked); its failures are now visible.

**Server (needs the owner)**: `tool/server/cross-device-v1/` adds `playOn`. Without it everything above works
for the device that already plays; sending to an idle device answers "Your session server can't do that yet".
See that folder's README.

## Verified / not verified

See the end of the session report; summary in the commit message.
