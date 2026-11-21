# Media controls: Windows touchpad tap and the vivo notification pill (2026-11)

Status: Windows fix verified by unit tests only (no touchpad/PC run in this session). Vivo fix is reasoned from the code and the audio_service source; **unverified on a vivo** (no phone attached).

## 1. Windows: three-finger tap (Play/pause) ignored

NaviVibe already had a System Media Transport Controls session (`smtc_windows`, `lib/services/windows_smtc.dart`) and a stable AppUserModelID (`NaviVibe`, runner `main.cpp` + `AppNotifier`). Causes found:

1. **Stopped session ignored.** When playback went idle (queue ended, `stop()`, startup before the first play) the session was reported to Windows as `Stopped`, even with a song still loaded. Windows only routes media keys to a session that is Playing or Paused, so the key had nowhere to go; Spotify keeps its session Paused. Now a stopped state with a song loaded is sent as Paused (stopped only when no song).
2. **Double handling when focused.** `lib/core/keyboard_shortcuts.dart` also bound the media keys. With the window focused, one press arrived as an SMTC button and as a Flutter key event, so play/pause could toggle twice (pause, then play).

Changes:
- `lib/services/media_key_gate.dart` (new): `MediaKeyGate`. Once SMTC is up (`smtcActive`, set in `main.dart`) the in-app media-key bindings step aside; the SMTC path also drops the twin of a press within 350 ms (play/pause/toggle are one family; next/previous are separate).
- `lib/services/windows_smtc.dart`: status upgrade described above; optional `gate`.
- If SMTC fails to start, the in-app bindings still work.

Keyboard media keys, touchpad tap, volume flyout and Bluetooth headsets all arrive through the SMTC session, so they work focused, in the background or minimised.

Tests: `test/services/media_key_gate_test.dart` (a press handled once; SMTC play reaches the transport once; in-app steps aside; stopped-with-song is paused), updated `windows_smtc_test.dart`.

**User on the PC:** nothing, except: press play once after a fresh start so the session is created, and make sure Settings > Bluetooth & devices > Touchpad > Advanced gestures keeps three-finger tap = Play/pause. If another player was used last, Windows may send the key to it until NaviVibe has played once.

## 2. vivo (Funtouch/OriginOS): stuck media notification

Causes (from `audio_service` 0.18.19 source and the handler):
1. `androidNotificationOngoing: true`: with `stopForegroundOnPause` the notification stays after pause but is flagged ongoing, so it cannot be swiped. vivo's task killer ends the idle service and the notification is orphaned: stuck, no actions, cannot be dismissed.
2. No `onTaskRemoved`: swiping the app away while paused left the session up.
3. `_broadcastState` kept `playing: true` after the queue completed (just_audio does not clear it), so the pill showed "pause" for a finished queue.

Changes: `androidNotificationOngoing: false` (`main.dart`); `NaviAudioHandler.onTaskRemoved` stops (clearing notification and session) when not playing, playback continues if playing; `playing` reported false when `ProcessingState.completed`.

Already correct: foreground service type `mediaPlayback`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS` (requested via `AndroidIntegration`), `MainActivity : AudioServiceActivity`, stop() ends in an idle state.

**User on the vivo phone:** Settings > Battery > Background power consumption (or High background power consumption) > NaviVibe: allow; i Manager / Settings > Apps > Autostart: enable NaviVibe; lock the app in recents (Multitask, pull the card down / lock icon); notifications allowed for NaviVibe, lock-screen notifications on. Without these, vivo can still kill playback in the background regardless of the app.

Verify on a phone: `adb shell dumpsys media_session` (state should be PAUSED/NONE, not stale PLAYING after queue end) and `adb shell dumpsys notification --noredact | findstr navivibe` after swiping the app away while paused (should be gone).

## Not touched
`player_provider.dart` was not edited.
