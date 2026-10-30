# NaviVibe: next round plan (Opus plan, Sonnet build)

Status when written (30 Oct 2026): main = `761cd31` (TV colour fix + CI/CD fixes) pushed; GitHub builds the release.
All Sonnet sessions hit their usage limit; they resume after **10:50 pm IST**. Work starts in the order below.
The user's phone and TV are not connected: device checks wait for the user.

## 1. Bugs the user hit (highest priority)

| # | Bug | Likely cause (to confirm) | Fix | Owner |
|---|-----|---------------------------|-----|-------|
| 1 | Now Playing slider wrong: "Opalite" (~4 min) shows 1-2 min, seeking still plays the whole song; remaining time wrong; mini player bar wrong too; sometimes the bar sticks | Duration taken from the player's stream estimate (transcoded MP3 `estimateContentLength`, VBR headers) instead of the song's real length; position stream not re-subscribed after a track change | One source of truth: `Song.duration` from Navidrome for the bar's length, player position for progress, clamp and re-sync on track change, seek, resume and remote control; the same widget logic for Now Playing and the mini player; tests with a fake player reporting a wrong duration | playback session |
| 2 | Search: double-tap the Search tab should open search with the keyboard up (Spotify behaviour); the clear (X) button is too small | Tab re-tap not handled; field not focused; X is a 16 px icon | Second tap on the Search tab (or tap while already on it) focuses the field and opens the keyboard; X gets a 44-48 px hit area with the same small glyph; widget tests | search-tap session |
| 3 | Back navigation does not follow Android's system back gesture / predictive back | Nested navigators per tab without a root back handler; `PopScope` gaps; predictive back not enabled | Android back: closes sheet, then pops the tab's stack, then goes to Home, then exits; enable predictive back (`enableOnBackInvokedCallback`); iOS swipe-back on pushed pages; tests | tv-desktop session (owns navigation) |
| 4 | "The Fate of Ophelia": the library has the 41 s "Track by Track" commentary, so the real 3-4 min song shows as owned and cannot be downloaded | Owned check matches by title + artist only; the fetcher's ranking accepted a commentary track | Owned check compares length (beyond ±10 s = a different version) and version words (track by track, commentary, interlude, intro, sped up, remix, live, acoustic, instrumental); search shows "Other version in your library"; a "Download this version" action; ranking penalises commentary/track-by-track; the doctor flags such songs | label-search session (tg-fetcher + app) |

## 2. Unfinished work to complete

| Work | State | Remaining | Owner |
|------|-------|-----------|-------|
| Flow / Discover / language exploration (mixes v2) | Server code written, 15 tests failing; one bug found (`_spaced` drops a lone exploration song) | Rebase on live code (keeps Gym), fix tests, backtest + simulation + live sample, app blend strip + explore mark, install script | listen-mixes |
| Wide-screen UI (from the user's screenshots) | Not started | Tinted top bar and side panel (no black frame), capped list width or two-column layout, Replay without card tiles, one back button | tv-desktop |
| Smart Shuffle visual on Now Playing | Not started | Generated Smart Shuffle backdrop + "Playing from Smart Shuffle" header when the queue is Smart Shuffle / Flow / Weekly / Discover | tv-desktop |
| Session sync testing | Protocol 3 live on the server; real-device tests not run | Scenario table on a local server copy with simulated clients now; phone/TV checks when connected | social |

## 3. After those finish (in this order)

1. Download queue (label-search): install the server half, finish the missing pieces.
2. Artist-image MCP server (backend-hardening): fix the 4 failing tests, export, install script.
3. App notifications: diagnose whether in-app notifications (download finished, update available, Jam invites) appear on Android 13+ (permission, channels, foreground service) and Windows; fix.

## 4. Rules for every session

- Merge `feature/search-online` first; analyze + full tests; commit with the Co-Authored-By line; do not push (Opus merges, tests and pushes so GitHub builds).
- Server changes: test in a /tmp copy, leave files + install script in `export/<name>/`; the user runs the install and restart.
- Our own icons only, DESIGN.md (monochrome, no card containers), reduced motion honoured.
- Keep each change small enough to finish in one session window.
