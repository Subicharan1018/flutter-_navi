# Music-player registration: Android, Android TV, web

State at this commit. Most of it already existed; `test/platform/music_player_registration_test.dart` now guards it.

## Android (`android/app/src/main/AndroidManifest.xml`)
- `audio_service` foreground service: `foregroundServiceType="mediaPlayback"`, `android.media.browse.MediaBrowserService` filter (Bluetooth/car/Assistant browse), `MediaButtonReceiver` (`MEDIA_BUTTON`).
- Permissions: `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (Android 14), `POST_NOTIFICATIONS` (Android 13+).
- Music-app registration: own `MAIN` + `DEFAULT` + `APP_MUSIC` filter, `android:appCategory="audio"`.
- Open with: `VIEW` for `audio/*` and `application/ogg` on `content:`/`file:`; routed by `IntentRouter.kt` -> `lib/services/open_intent.dart`. Voice: `MEDIA_PLAY_FROM_SEARCH`.
- Android Auto: `automotive_app_desc.xml` (`uses name="media"`) plus `ArtworkProvider` for cover art.
- Notification: channel `com.navivibe.audio`, transport controls and artwork come from `NaviAudioHandler` via `AudioServiceConfig` in `lib/main.dart`.

## Android TV
- `LEANBACK_LAUNCHER` category, `android:banner="@drawable/tv_banner"`, `android.software.leanback` and `touchscreen` both `required="false"`.
- The TV home shows the media session published by the same `audio_service`.

## Web
- Browser Media Session (metadata + artwork, play/pause/prev/next/seek, position state) is implemented by `audio_service_web` (uses `package:web`), which activates because `AudioService.init` runs on web too. No extra code needed.
- `web/manifest.json`: name, maskable + any icons, `categories: ["music", ...]`, `theme_color`; `index.html` links it and sets `theme-color`.

## Verification
Automated: `flutter analyze`; `flutter test test/platform`.

On a phone (adb):
```
adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.APP_MUSIC
adb shell cmd package query-activities --brief -a android.intent.action.VIEW -t audio/mpeg -d content://x/y.mp3
adb shell dumpsys package com.navivibe.navivibe | grep -i -A3 "APP_MUSIC\|MediaBrowserService"
adb shell dumpsys media_session | grep -i -B2 -A12 navivibe     # while playing
```
Expect NaviVibe in the first two lists; an active session with `active=true`, the metadata title/artist/art and actions incl. skip and seek.

Web: open the site in Chrome, play a song, check `chrome://media-internals` or the OS media overlay, DevTools > Application > Manifest.

Not verified: no device was connected when this was written (`adb devices` empty), so the adb checks above are unrun.
