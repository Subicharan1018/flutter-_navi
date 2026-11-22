# Hard-coded values audit

Scope: `lib/` (488 Dart files), `windows/`, `android/`, `web/`, `tool/`. Read-only; no source touched.
Branch `feature/search-online`. All counts are line counts from `grep -rE` over the stated pattern
(re-runnable; the pattern is given with each count). `lib/core/theme.dart` is the token home, so it is
counted but listed separately from offenders.

## Summary

| # | Group | Count | Priority |
|---|-------|------:|----------|
| 1 | Personal infrastructure in tracked files (Tailscale IP, LAN IP, hostnames) | 6 files | **P0** |
| 2 | Production hostnames baked into app and server defaults | 8 in `lib/`, ~12 in `tool/` | P1 |
| 3 | `Color(0x…)` literals in UI | 111 (26 in theme.dart) | P1 |
| 4 | `Colors.*` literals in UI | 121 | P1 |
| 5 | Timeouts/Durations as raw literals | 261 `Duration(` (132 s/min/h/d, 129 ms) | P2 |
| 6 | Magic spacing/radius numbers | 199 EdgeInsets, 122 SizedBox, 158 radii | P3 |
| 7 | Raw font sizes | 9 `fontSize:` + 41 `naviText(<n>,…)` | P2 |
| 8 | User-facing strings, no l10n | 191 `Text('…')` literals, no `l10n/`, no `flutter_localizations` | P2 |
| 9 | Paging/limit magic numbers | ~20 in services/providers; ~25 default params in ai_shuffle | P2 |
| 10 | Breakpoints outside `PlatformUtils` | 6 | P2 |
| 11 | Platform checks bypassing `PlatformUtils` | 22 in 10 files (+ 66 `kIsWeb`, of which 14 are inside PlatformUtils) | P2 |
| 12 | Package/channel/authority ids | 6 distinct strings, repeated | P3 |
| 13 | Secrets | none found in tracked source (see §1) | – |

Good news first: the app has `ThemeTokens` with 470 uses of `ThemeTokens.of`/`AppThemeTokens`, a single
`Constants` class, `hive_boxes.dart` for storage keys (56 constants), `PlatformUtils` with breakpoints
(`kDesktopBreakpoint = 800`, `kWideScreenBreakpoint = 1200`), and the signing config reads credentials
from `key.properties`/env (`NAVI_KEYSTORE_PASSWORD`, `NAVI_KEY_ALIAS`, `NAVI_KEY_PASSWORD`), so the
signing path is clean.

---

## 1. Personal data and infrastructure (private; by location only)

No API keys, passwords, bearer tokens, or keystores were found in tracked source
(`grep -riE "(api[_-]?key|secret|token|password|bearer)\s*[:=]\s*['\"][^'\"$]{6,}"` hits only
`lib/core/hive_boxes.dart:102,137`, which are storage-key *names*, and a test fixture
`tool/server/history-import-v1/files/tests/test_history_import_v1.py:272`).

Things that identify the owner's network or machine:

| Location | What | Action |
|---|---|---|
| `android/app/src/main/res/xml/network_security_config.xml:5` | A home-LAN IP whitelisted for cleartext; `<base-config cleartextTrafficPermitted="true">` on line 3 already allows cleartext everywhere, so the domain entry is redundant *and* leaks the LAN address | Remove the `domain-config`. **Separately (security):** base cleartext=true is a broad opt-in; consider limiting it or making a debug-only config |
| `tool/export_listens.py:10,14,17,142` | A Tailscale IP plus `subi@…` SSH user and `admin` Navidrome user in docstring/help | Replace with `<host>` placeholders |
| `tool/server/server-fixes-v1/README.md:90,94` | Same Tailscale IP and ssh user | Placeholder |
| `tool/server/lyrics-v1/install.sh:90` | `you@example.com` placeholder (fine) | none |
| `android/local.properties`, `windows/flutter/ephemeral/generated_config.cmake` | Windows user name and SDK paths. **Both are git-ignored / untracked** (`git ls-files` returns nothing; `git check-ignore` confirms local.properties) | none, just never `git add -f` |
| `lib/core/constants.dart:10` | `suggestedServerUrl` prefills the owner's domain in non-public builds (`kPublicBuild` guards it) | Fine as is; move to `--dart-define=NAVIVIBE_SUGGESTED_URL` so the source holds no personal host |

Also noted: `lib/core/constants.dart:5` comment says "Hardcoded server addresses are a security risk"
while the next lines prefill one. Harmless but contradictory.

## 2. Hostnames, URLs, ports

### In `lib/` (all `https?://` hosts: `grep -rhoE "https?://[a-zA-Z0-9.-]+" lib | sort | uniq -c`)

| Host | Where | Proposed home |
|---|---|---|
| `shuffle.subimusic.me` | `ai_shuffle/data/services/shuffle_api_service.dart:45` (already `String.fromEnvironment` with default); error text `shuffle_exception.dart:19`; comments | OK pattern. Move default into `Constants`/`ServiceEndpoints`; the error string should read the configured host, not hard-code it |
| `session.subimusic.me` | `services/session_sync_service.dart:492` (same dart-define pattern) | Same: one `lib/core/endpoints.dart` holding every default |
| `subimusic.me` | `core/constants.dart:10` | dart-define |
| `lrclib.net` | `lyrics/services/lrclib_service.dart:21` | endpoints file |
| `lrc.red`, `betterlyrics.org`, `music.youtube.com` | `lyrics/controllers/lyrics_sources_provider.dart:11,14,18` (enum members carrying URL) | acceptable as enum data; consider moving URL to the services |
| `open.spotify.com` | `online_fetch/ui/send_playlist_sheet.dart:124` (placeholder text) | fine |
| `github.com` | one hit (update source) | `Constants` |

Pattern is mostly good (dart-define overrides exist for shuffle and session). Gaps: lrclib and
update repo have no override; hosts are spread over 6 files instead of one.

### `tool/` (server installers)
* `127.0.0.1:5500`, `:5510`, `:5501` repeated in ~20 `install.sh` health checks
  (`grep -rnE "127\.0\.0\.1:55[0-9]{2}" tool | wc -l`). Ports 5500 (shuffle), 5510, 5501 (session) are
  undocumented constants. Proposed: one `tool/server/ports.env` sourced by installers.
* `https://subimusic.me`, `https://shuffle.subimusic.me`, `https://navidrome.subimusic.me` in
  `lyrics_proxy.py:45/56/65`, `mood_editor.py:29`, install scripts and READMEs. The python files use
  env with a default; the scripts and READMEs hard-code. Same fix.
* `tool/web/server/Caddyfile:1,2,13,20,21,41`: hostnames in comments, CSP inline. CSP `default-src 'self'`
  line 41 will need editing with any new host (e.g. lrclib is fetched cross-origin from the web build:
  verify it is allowed, otherwise lyrics fail on web).

## 3. `Color(0x…)` literals (111)

`grep -rE "Color\(0x" lib | wc -l` = 111. Per file (top): `core/theme.dart` 26 (legit: it *is* the token
file), `player/now_playing_style.dart` 8, `player/player_controls.dart` 7, `widgets/art/navi_icons_extra.dart` 6,
`core/album_palette.dart` 6 (legit: palette data), `widgets/art/navi_icons.dart` 5, `screens/replay/year_story.dart` 4,
`features/share/share_card.dart` 4, `features/month/ui/story/{story_pager,month_summary_card,month_story}.dart` 4 each,
`widgets/ui/dock_ground.dart` 3, `widgets/shell/dock_glass.dart` 3, `widgets/app_scaffold.dart` 3,
`screens/now_playing_screen.dart` 3.

Worst offenders:

* `player/player_controls.dart:253,254,389,460,585,586,679`: `0x40FFFFFF`, `0x99FFFFFF`, `0x24FFFFFF`,
  `0x2EFFFFFF`: white-at-alpha ladders in a widget that is *always on artwork*.
* `player/now_playing_style.dart:33-40`: a second, parallel token set (`textPrimary`, `accent`, `pillIdle`…)
  built from raw hex. Intentional (on-art style) but it duplicates `ThemeTokens` fields by hand.
* `screens/now_playing_screen.dart:234` `0xFF111111`, `:1095` shadow `0x8C000000`, `:1185` `0x14FFFFFF`.
* `widgets/app_scaffold.dart:294,298` glass fills `0x14FFFFFF`, `0x2BFFFFFF`.
* `player/{artwork.dart:74,103, edge_fade.dart:19, full_bleed_art.dart:141, devices_sheet.dart:164}`.
* `screens/{playlist_editor.dart:146, search_screen.dart:327}` and `features/social/ui/{collab_screens.dart:423,
  jam/jam_desktop.dart:199, jam/jam_room.dart:510}`: the same `0x59000000` drag/shadow colour pasted 2-5 times.
* Story/share cards (`features/month/ui/story/*`, `screens/replay/year_story.dart`, `share_card.dart`):
  16 literals; these render to an exported image so they are deliberately theme-independent, but they
  should still be a named `StoryPalette`.

Proposed home: add to `AppThemeTokens` an **on-artwork scale** (`onArtwork` already exists: used in
`flow_pill.dart:37`) with named alphas `onArtworkFaint/Soft/Medium/Strong` (0x14/0x24/0x40/0x99 → 8/14/25/60 %),
a `scrim` and `shadow` colour (`0x59000000`), and a `glassFill/glassFillHi`. Replace the ~45 white-alpha
literals above with them. Keep album_palette/theme/icon files as is. **P1.**

## 4. `Colors.*` literals (121)

`grep -rE "\bColors\.[a-zA-Z]+" lib | wc -l` = 121. Breakdown: `Colors.white` 47 (+15 `.withValues/.withOpacity`),
`Colors.transparent` 42, `Colors.black` 14 (+4 derived), `black54` 2, `white70` 1. **No coloured
Material literals** (`Colors.red/green/blue/…`: 0 hits), consistent with the monochrome canon.

By file: `screens/now_playing_screen.dart` 12, `core/theme.dart` 12, `player/remote_view.dart` 11,
`widgets/mini_player.dart` 6, `widgets/art/smart_context.dart` 5, `player/queue_pane.dart` 5,
`widgets/ui/horizontal_shelf.dart` 4, `widgets/desktop_dialogs.dart` 4, `screens/home_screen.dart` 4,
`player/player_controls.dart` 4, `features/pairing/ui/tv_pair_screen.dart` 4.

* `Colors.transparent` (42) is fine; leave.
* `Colors.white` is correct *on artwork* (now_playing, remote_view, player_controls) but wrong on app
  chrome: `home_screen.dart`, `desktop_dialogs.dart`, `horizontal_shelf.dart`, `tv_pair_screen.dart`,
  `top_bar.dart`: check each; should be `t.textPrimary`/`t.onAccent` so a future light theme works.
  The skill file says six themes exist, so literal white on a themed surface is a real bug risk.
* `player/remote_view.dart:84-262` is 11 white/alpha literals in one widget: the largest single block;
  take its colours from the on-artwork scale above.

**P1** for the non-artwork ones (functional risk), P2 for artwork ones.

## 5. Typography

* `fontFamily:` literal: 1 (`core/theme.dart:343` `'Inter'`); `GoogleFonts.` 0. Clean.
* `fontSize: <literal>`: 9 hits in 9 files (`replay_rows.dart`, `reaction_sheet.dart`, `month_screen.dart`,
  `tv_pair_screen.dart`, `smart_widgets.dart`, `playback_tuning_tiles.dart`, `artwork_page.dart`,
  `now_playing_panel.dart`, `microduck_strip.dart`). Small; route through `naviText`/text tokens.
* `naviText(<number>, …)`: 41 calls with literal sizes, e.g. `screens/now_playing_screen.dart:1101-1107`
  (26/22/18/19/15 for title/artist/composer), `player/remote_view.dart:232,262` (14, 13.5),
  `player/lyrics_pane.dart` 7, `player/queue_pane.dart` 6. Fractional `13.5` suggests ad-hoc tuning.
  Proposed: a `NaviType` scale (`title/subtitle/body/caption/micro`) in theme.dart. **P2.**
* `FontWeight.` appears 171×, mostly via the helper; fine.

## 6. Durations and timeouts

`grep -rE "Duration\((milliseconds|seconds|minutes|hours|days):\s*[0-9]+" lib | wc -l` = 261 (132 with seconds/minutes/hours/days, 129 milliseconds).
Most-repeated: 500 ms ×10, 250 ms ×7, 180 ms ×7, 320 ms ×6, 900/90/260/1500/1400/120 ms ×5.
Hot files: `providers/player_provider.dart` 22, `services/navi_audio_handler.dart` 15,
`widgets/shell/desktop/player_bar.dart` 11, `screens/now_playing_screen.dart` 11, `player/player_controls.dart` 11,
`widgets/mascot/microduck_strip.dart` 8, `core/theme.dart` 8, `services/session_sync_service.dart` 7.

`core/motion.dart` exists but the 129 ms literals show it is not used for most animations.
Proposed: add `NaviMotion.fast(90–120) / base(180–260) / slow(320–500) / hero(900+)` and migrate.

**Network timeouts are scattered with no shared policy** (`grep -rnE "connectTimeout|receiveTimeout|sendTimeout|\.timeout\("`
≈ 45 hits). Examples: 
* `shuffle_api_service.dart:57,58,468` 10/20/40 s
* `online_fetch_api.dart:30-32` 15/40/20 s
* `recognize_api.dart:33,34` 30/45 s
* `lyrics_server_api.dart:64,119` 90 s and 25 s; `lrclib_service.dart:42` 12 s
* `offline_service.dart:311,312,373,374` 15/120/10/30 s
* `web_session.dart:146,239` 20/15 s; `playlist_image_api.dart:36` 60 s; `status_providers.dart:247` 60 s;
  `player_provider.dart:1117,1119` 3 s; `listenbrainz_link.dart:53,96`; `share_api.dart:117`; `update_providers.dart:79` 15 s.
Proposed: `lib/core/net_timeouts.dart` with named `connect`, `quick`, `normal`, `upload`, `longPoll`, applied
per service. Candidates for a user setting: download receive timeout (`offline_service.dart:312`, 120 s) on slow links. **P2.**

## 7. Paging, limits and thresholds

Subsonic/shuffle calls carrying bare numbers:

* `services/auto/car_browser.dart:40,42,63`: `size: 30`, `100`, and batch `500` (twice, as `size` and `page * 500`; must stay equal: one named const).
* `providers/library_provider.dart:479` `size: 24`; `:487` `getAlbums(size: 1000)`: a hard ceiling that silently truncates larger libraries (functional risk).
* `services/subsonic_service.dart:764-766` search `artistCount '10'`, `albumCount '20'`, `songCount '50'`; `:379-380` `'0'`.
* `providers/player_provider.dart:2741-2748` radio seeds `count: 10` ×3.
* `navi_audio_handler.dart:492` cover `size: 300`, `:634,1114` `size: 600` (art sizes should come from the single art-size scale in the platform-ui-rules memory).
* `features/ai_shuffle/**`: defaults `count = 15`, `limit = 20/50/10` repeated across `shuffle_repository.dart:60,101,122,144,193`,
  `shuffle_api_service.dart:132,188,209,233,322` and `shuffle_providers.dart:178,322,460,463`: repository and service
  duplicate each default, so changing one desyncs the other.
Proposed: `Constants.pageSize*`/`SearchLimits`; repository defaults delegate to the service. **P2.**

## 8. Breakpoints outside `PlatformUtils`

`PlatformUtils.kDesktopBreakpoint = 800`, `kWideScreenBreakpoint = 1200` exist, but:
* `screens/now_playing_screen.dart:242` `width >= 900`
* `screens/replay/replay_screen.dart:97` and `widgets/song_tile.dart:102` `>= 1100` (duplicate)
* `widgets/shell/desktop/player_bar.dart:158,184` `< 300`, `>= 200` (local container widths; acceptable but name them)
* `core/layout/window_size.dart:56` `shortestSide >= 600` (tablet cut-off, defined once, fine but unnamed)
* `utils/web_form_factor.dart:25` documents "Matches kDesktopBreakpoint" instead of referencing it.
Add `kWideContentBreakpoint = 1100`, `kNowPlayingSplit = 900`, `kTabletShortestSide = 600` beside the existing ones. **P2.**

## 9. Platform checks outside `PlatformUtils`

`grep -rnE "Platform\.is(Android|Windows|IOS|Linux|MacOS)|defaultTargetPlatform|TargetPlatform\." lib | grep -v platform_utils` = **22** in 10 files:

| File:line | Check | Note |
|---|---|---|
| `features/updates/logic/update_providers.dart:21,26,149` | `Platform.isAndroid` / `isWindows` | use `PlatformUtils.isAndroid/isWindows` |
| `features/updates/logic/update_service.dart:89,105` | same | |
| `features/local_library/logic/download_location.dart:74,78`; `local_library_providers.dart:187`; `ui/download_location_section.dart:50` | same | |
| `features/auto_download/logic/auto_download_service.dart:197-199` | reimplements `isNativeDesktop` via `defaultTargetPlatform` | replace with `PlatformUtils.isNativeDesktop` |
| `main.dart:126` | `Platform.isLinux \|\| isWindows` | |
| `services/navi_audio_handler.dart:55,111,458` | three private re-implementations (`_isAndroid`) | |
| `core/motion.dart:458` | `TargetPlatform.linux \|\| windows` | |
| `core/theme.dart:512-516` | `PageTransitionsTheme` map: legitimate (Flutter API needs it) | leave |

Also `kIsWeb` is used in 66 lines; 14 are inside `platform_utils.dart`; the rest are mainly
`login_screen.dart` 6, `navi_audio_handler.dart` 6, `web_form_factor_scope.dart` 4, `settings_screen.dart` 4,
`settings_provider.dart` 4, `main.dart` 4. Many are legitimate (`kIsWeb` guards before `dart:io`), so only review
the `kIsWeb && Platform.isX` pairs (`update_providers.dart:21,26`, `download_location.dart:74`,
`local_library_providers.dart:187`, `navi_audio_handler.dart:111`), which `PlatformUtils.isX` already folds.
Note `PlatformUtils.isLinux` also excludes `FLUTTER_TEST`, so bypassing it changes test behaviour. **P2.**

## 10. Identifiers (packages, channels, authorities)

* `com.navivibe/android` ×2 (`platform_utils.dart:30`, `services/android_integration.dart:14`) — **duplicate channel
  declaration**, plus `MainActivity.kt:36`; `com.navivibe/saf` (`file_source.dart:127`, `SafChannel.kt:53`);
  `com.navivibe/updates` (`update_service.dart:25`, `UpdateChannel.kt:23`).
* `com.navivibe.navivibe.art` authority: `lib/services/auto/browse_tree.dart:92` and `AndroidManifest.xml:110`;
  `com.navivibe.navivibe.updates` at `AndroidManifest.xml:116`.
* `com.navivibe.audio` notification channel id, `main.dart:180`.
* `applicationId`/`namespace` `com.navivibe.navivibe`: `build.gradle.kts:11,26`, repeated in 9 Kotlin `package` lines (normal).
* Subsonic client `Constants.defaultClient = 'navivibe'`, `apiVersion = '1.16.1'` correctly centralised; used 3× in `subsonic_service.dart`.
Proposed: one `lib/core/channels.dart` declaring every channel name; Kotlin side stays separate (cross-language). **P3.**

## 11. User-facing strings

No `l10n/` directory, no `flutter_localizations`/`intl` generate config in `pubspec.yaml`. `grep -rE "Text\(\s*'[A-Za-z]" lib | wc -l` = **191**
direct literals plus untracked strings in SnackBars/toasts (14 matches of a SnackBar/toast + sentence), sheet titles, errors.
Most literal-heavy: `smart_playlists/ui/rule_editor_screen.dart` 11, `social/ui/jam/jam_room.dart` 9,
`online_fetch/ui/online_search_sheet.dart` 9, `everyday/profile_picker_screen.dart` 8, `updates/ui/updates_screen.dart` 7,
`online_fetch/ui/fetch_activity.dart` 6. Server-ish messages are *already* centralised well in places
(`online_fetch/data/fetch_models.dart:63,93`, `shuffle_exception.dart:19`).
Recommendation: the app is English-only by design, so do **not** introduce ARB files now; instead gather error/empty-state
copy (the strings users can't ignore) into `lib/core/copy.dart` and make exceptions return codes + one mapper. **P2 (copy), P3 (full l10n).**

## 12. Native and web configuration

* `windows/runner/main.cpp:79` opens at `1280×720` while `lib/main.dart:135` sets `Size(1280, 800)`: two sources of truth
  (the Dart one wins but the window flashes at 720). Align or make Dart the only source. Window title `"NaviVibe"` at
  `main.cpp:24,80` and mutex `Local\NaviVibeSingleInstance:45`, AUMID `:55` must stay equal to the installer's: fine but note.
* `android/app/src/main/res/**`: 43 hex colours in XML resources (`grep -rnE "#[0-9A-Fa-f]{6,8}" … | wc -l`); acceptable for
  native resources (widget, splash) but they should match tokens (`#000000` ground, white accent); no check enforces it.
* `web/index.html:10,27` and `web/manifest.json:10,11` hard-code `#000000`/`#000`: correct per canon (black ground), but
  duplicated 4×.
* `android/app/build.gradle.kts`: `compileSdk = 36` literal; min/target come from Flutter: OK.

## Prioritised action list

1. **P0** Remove the LAN IP from `network_security_config.xml:5`; replace Tailscale IP/ssh user in `tool/export_listens.py` and `server-fixes-v1/README.md` with placeholders. Decide whether `base-config cleartext=true` is intended.
2. **P1** On-artwork colour scale + shadow/scrim tokens; migrate the ~45 white-alpha and `0x59000000` literals. Fix non-artwork `Colors.white` (home, dialogs, shelf, TV pair, top bar).
3. **P1** Single `endpoints.dart` (+ dart-define) for every external host; stop hard-coding `shuffle.subimusic.me` in the error string.
4. **P2** `NaviMotion` durations, `NetTimeouts`, paging/search limits, `NaviType` scale, three extra breakpoints, route 22 platform checks through `PlatformUtils`.
5. **P2** Confirm the `getAlbums(size: 1000)` ceiling (`library_provider.dart:487`) against the real library size.
6. **P3** Channel-name constants, spacing/radius scale (199+122+158 call sites: only worth it if a density setting is planned), full l10n.

## Verification

Counts above come from these commands (run at repo root):
`grep -rE 'Color\(0x' lib | wc -l` → 111 · `grep -rE '\bColors\.[a-zA-Z]+' lib | wc -l` → 121 ·
numeric-literal Duration grep (§6) → 261 · `grep -rE 'fontSize:\s*[0-9]' lib | wc -l` → 9 ·
`grep -rE 'naviText\(\s*[0-9]' lib | wc -l` → 41 · `grep -rE "Text\(\s*'[A-Za-z]" lib | wc -l` → 191 ·
platform grep above → 22 · `EdgeInsets` 199, `SizedBox(width|height)` 122, `BorderRadius.circular` 63, `Radius.circular` 95.
Approximations: Duration total is the sum of the two sub-greps (132+129), which can differ by a few from the
single-pattern count because of multi-line constructors; the per-file lists are exact for the stated patterns but
do not follow multi-line expressions (so true counts are slightly higher). Pattern-based greps do not catch values
assigned through variables, so treat the magic-number groups as lower bounds. Not run: `flutter analyze`/tests (read-only audit, no code changed).
