# Session sync (live cross-device playback)

What it is: one account, several devices (phone, laptop, TV). One of them is **playing**
(the host); the others show what it plays and control it. "Play here" or picking a device
moves playback across, carrying the playhead.

Code: server `navivibe/session.py` (FastAPI, port 5501, `wss://session.subimusic.me/ws/session`);
app `lib/services/session_sync_service.dart`, `lib/providers/session_sync_provider.dart`,
the sync parts of `lib/providers/player_provider.dart`, UI in `lib/player/` (`devices_sheet.dart`,
`remote_view.dart`, `playing_on.dart`).

## Model

The server is the single source of truth. Each signed-in user has one **room**:

| field | meaning |
| --- | --- |
| `epoch` | bumped only when the host changes (transfer commit, failover) |
| `version` | bumped by the server on every state change; clients never write it |
| `active_device` | the device producing audio, or none |
| track, queue, queue index, `position_ms`, `position_at_server_ms`, `is_playing` | what is playing; the position is true at the stamp |

Roles are derived, never self-declared: **host** (the one `active_device`), **controller** (online,
sends commands, silent), **passive** (online, shows state). A device becomes host only through an
explicit transfer or a "play here" gesture, never because a remote state arrived.

Rooms are keyed by the **authenticated username (lower-cased)**. A device id is per install and means
nothing outside its room: the same id under two accounts is two unrelated devices.

## Protocol

JSON text frames over one WebSocket. Connect: `wss://…/ws/session?token=…&device_id=…&device_name=…&device_type=…&proto=3`.
`token` is base64(`user:password`) (what the app sends) or a Navidrome JWT. A rejected token is refused
before the upgrade (HTTP 403) or closed with 4001. The server downgrades unknown `proto` values and
speaks to each socket at the level it asked for, so installed builds keep working.

| proto | who | what they get |
| --- | --- | --- |
| 1 | oldest builds | `state` (flat), `pong`. `transfer_playback`, `state_update`, `ping`, `get_state`. |
| 2 | previous builds | + `devices`, `command`/`command_result`, `release_playback`. |
| 3 | current | + versioned state, `cmd`/`ack`, two-phase transfer, `exec prepare`/`ready`, NTP-style `pong`. |

### Client → server
* `ping{t0}`: answered with `pong{t0, server_t}` (server ms).
* `state_update{track_id, position_ms, is_playing, queue, …, epoch}`: only from the host. A frame with another
  `epoch`, or from a non-host, is ignored and answered with the real state.
* `transfer_playback{device_id, device_name?, force?}` (proto 1/2): immediate hand-over.
* `cmd{cmdId, cmdType, baseVersion?, args}` (proto 3). `cmdType`: `play pause toggle seek next prev setQueue volume playTrack transfer`.
  `transfer` args: `toDeviceId`, `force?`, `baseEpoch?`.
* `ready{transfer_id}`: a prepared target says it has loaded the song.
* `release_playback`, `get_state`, `get_devices`.

### Server → client
* `state{epoch, version, server_time, position_at_server_ms, …fields, payload{same}}`: flat for old builds, under `payload` for new ones.
* `devices{payload:[{id, name, type, active, host, last_seen_s}]}` (proto ≥ 2), pushed on every change.
* `command{action, …}`: a controller's order, to the host (proto ≥ 2).
* `ack{cmdId, status: ok|rejected|stale|duplicate, reason?, pending?, version, epoch}`.
* `exec{action: prepare, transfer_id, epoch, position_ms, track_id, queue, queue_index, play}`: to a transfer target.
* `pong{t0, server_t}`, `command_result{ok, action, reason?}` (proto 2 replies).

## Invariants

1. Only the server bumps `version`. Only a committed transfer or a failover bumps `epoch` and changes `active_device`.
2. Absolute commands (play, pause, seek, volume) are last-writer-wins by arrival. A transfer is a compare-and-swap on
   `epoch`: if the client's `baseEpoch` is not current the answer is `stale` and the client adopts the server's state.
   This closes the transfer-versus-play race. Spotify's own documentation says execution order of near-simultaneous
   calls is not guaranteed.
3. **Echo suppression.** The player emits intents only from user actions. Applying a remote `state` goes through a path
   that sends nothing (no claim, no command, no report). A device in "passive" mode may not claim without a touch
   (`UserActivity`) or an explicit permit window (Jam). See the echo test below.
4. Only the host reports. A deposed device that still plays stops at the next state naming another host and never sends `play`.
5. Hysteresis: a second transfer within 1.5 s of one is rejected unless `force` (a person's latest gesture). An unforced
   self-claim within 8 s of another device's claim is rejected too. Claims from a person carry `force`.
6. Idempotency: the server remembers `cmdId` for 2 minutes; a repeat gets `ack duplicate` and is not applied again. The
   client resends unacknowledged commands (transfers, and anything under 15 s old) with the same id after a reconnect.
7. Accounts never mix: the room comes from the login, the token is dropped on sign-out (`resetAccount`), and a
   socket reports only for itself (a late close of an old socket cannot tear down its successor).

## Transfer

Proto-3 target: the server sends `exec prepare` (position projected to now, track, queue, play flag). The **old host keeps
playing**. The target loads the song paused at that position and answers `ready`. The server then bumps `epoch`, switches
`active_device`, broadcasts, and acks `ok`. If no `ready` arrives in 5 s, or the target drops, the transfer is rolled back
(`ack rejected timeout / target_offline`) and nothing changed, so there is no audible gap and no half-moved state.
Transfer to an offline device is refused at once (`device_offline`). Proto 1/2 targets get an immediate switch.

## Position

Each ping gives an offset sample `serverT − (t0 + t1)/2`. The client keeps the lowest-RTT of the last eight and eases to it
(`ClockEstimator`). Playing: `position = position_ms + (nowDevice + offset − position_at_server_ms)`, clamped to the duration;
paused: `position_ms`. Controllers redraw from the formula; the host's reports stamp the server fix. With ±5 s of device clock
skew and lopsided latency the error stays under 300 ms (tested).

## Heartbeats and reconnect

* Client pings every 25 s (three quick ones at 2/4/6 s after connecting, to settle the clock). Cloudflare's tunnel drops quiet
  WebSockets after about 100 s, so a quiet socket would otherwise die. No pong within 10 s of a ping means the socket is
  half-open: close and reconnect.
* Server closes a socket silent for 60 s and marks the device offline.
* Backoff: `0.5 s · 2^n`, capped at 30 s, full jitter, floor 200 ms; the counter resets after 30 s of stable connection.
  Auth failures retry quickly three times, then back off like everything else, so a wrong password cannot hammer the server.
* On connect the server sends the full state (small; no replay). The client reconciles: if it thinks it is host and the
  snapshot says otherwise, it stops; if the snapshot says it is host and playing but it is silent, it resumes from the
  interpolated position.

## Failure cases

| case | behaviour |
| --- | --- |
| host disappears | 20 s grace for it to come back; then the session is **paused at the last interpolated position**, `epoch + 1`, and nobody is drafted to take over. Controllers say "play here". |
| two devices play at once | the first claim wins; the second gets `claim_cooldown` / `stale` and adopts the server state. |
| socket drops mid-command | the command is resent with its id after reconnect; applied once. |
| half-open peer | server drops it after 60 s; a client notices in 10 s. |
| unknown / old build | speaks proto 1/2; never sent new frame types. |

## UI

* **Playing on** chip on Now Playing ("Playing on Android TV (MiTV-MOOQ1)" or "This device is the host") and a remote mini player
  on every non-host device (their song, play/pause/next sent to the host).
* **Devices sheet**: every connected device with its real name (`device_info_plus`: model, `Android TV (model)`,
  `Windows PC (computer name)`), type icon, `This device`, `Host · playing now`, last seen when quiet, tap to transfer; offline and
  connecting states with *Try again*.
* **Remote control view** replaces Now Playing while another device plays: its cover, title, live playhead, seek, previous/play/next, volume, *Play here*.

## Tests

* Server (`navivibe/tests/test_session_sync.py`, `test_session_proto3.py`): per-user isolation incl. same device id under two accounts and
  username casing; transfer races (two at once, during pause, play during transfer), compare-and-swap, timeout and drop rollback,
  deposed-device reports, failover, grace reconnect, half-open sockets, 50-reconnect storm without a double-applied command, old builds
  next to proto 3, hysteresis and the claim guard. Virtual time, fake sockets.
* App (`test/services/session_protocol_test.dart`, `session_v3_test.dart`, `test/providers/player_provider_sync_test.dart`, `test/goldens/remote_test.dart`):
  account switch (token, orphan socket, in-flight connect), pings with `t0`, clock estimator under skew, ack/stale/duplicate, resend after
  reconnect, version ordering, prepare/ready, **echo** (applying remote state sends nothing), reconcile after restart, backoff and
  heartbeat timing (fake async), claim gate (no touch, touch, permit window).

## Not done yet

* A separate `hello` frame (`lastVersion`, `lastEpoch`) and a distinct `report` frame: the token rides the URL and the host reports with
  `state_update` plus `epoch`. Behaviour is the same; a later cleanup.
* `volume`, `shuffle`, `repeat` are not part of the shared session state yet (volume is a command).
* Android: the host's socket surviving screen-off and Doze relies on the audio service's foreground service; a 10-minute screen-lock soak
  on real hardware is still to be run.

## Sources

* Spotify Web API, *Transfer Playback*: https://developer.spotify.com/documentation/web-api/reference/transfer-a-users-playback
  (transfer is asynchronous; ordering of near-simultaneous calls is not guaranteed).
* Spotify Web API, *Rate limits*: https://developer.spotify.com/documentation/web-api/concepts/rate-limits
* Cloudflare, *WebSockets*: https://developers.cloudflare.com/network/websockets/ and community threads on the roughly 100-second
  idle timeout of proxied WebSockets (from the design research; not re-verified here).
