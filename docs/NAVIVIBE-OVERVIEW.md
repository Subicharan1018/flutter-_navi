# NaviVibe: everything in the music player (as of 23 Nov 2026, version 2.0.0)

One page that says what exists, where it lives, what is installed on the server, and what is still open.
Written from the repo and from what the build sessions reported. Anything marked **(unverified)** was not checked on a device or on the live server.

## 1. What it is

A music app for a self-hosted Navidrome (subiserver), with its own Python servers for recommendations, fetching songs and live sessions.

| Piece | What it is |
|---|---|
| App | Flutter: Android, Android TV, Windows, web (https://subimusic.me). Self-updating from GitHub releases. |
| Navidrome | The music library and Subsonic API (FLAC library, about 2,500 songs plus the wishlist growing). |
| Shuffle server (`/opt/shuffle-server`, service `navivibe`, :5500) | Smart Shuffle, Flow, moods, weekly mix, rotation, stats, listening logs, imports. |
| Session server (`navivibe-session`, :5501) | "Playing on" across devices, remote control, jam rooms. |
| Fetcher (`/opt/tg-fetcher`, service `tg-fetcher`, :5510) | Gets missing songs: Telegram channels first, the music bot as fallback, wishlists, nightly caps, disk floor. |
| Web server | Caddy in Docker on :8090, serves the web build with Brotli. |

Release pipeline: every push to `main` builds Android, Windows and web and publishes a release (build number = GitHub run number + 100). `publish` waits for the `test` job, so one failing test blocks all updates. Version 2.0.0 is out (v2.0.0+208 and later).

## 2. In the app

**Playing:** Now Playing with lyrics, queue editing (Up Next: reorder, remove, play next), crossfade and speed, sleep timer, Microduck mascot (off by default), peak moments (save the best part of a song, drag its start and end, highlight reel), Fast start (first seconds from a small copy, then the full file), resume where you stopped, network-drop handling, mini player with a quiet "Playing on …" line.

**Library and search:** Home shelves (weekly mix, new in your library, everyday albums), library, artists (artist page with plays, first/latest play, year spine), albums, composers, playlists with covers, favourites, search, search online (fetch a missing song), recognise a song with the microphone, local files import.

**Offline:** downloads with a background foreground service on Android (keeps going when the app is in the background, resumes after a kill), auto-download rules, play cache, download notifications and an "import finished" notice.

**Smart features:** Smart Shuffle (with "why" for each pick), Flow (mood/energy-based queues), moods (mood chips, "Describe a mix"), weekly mix, Weekly Exploration (about 20 songs a week you do not own, 30 s preview, Keep or Not for me), Back in Rotation, Album overnight, smart playlists, discover shelf.

**You and others:** Stats (listening hours, genres, streak, listener type), Replay (year and month), charts/trending, social and People (friend activity, reactions), Jam rooms, share cards, ListenBrainz forwarding, pairing a device with the server address and login.

**Imports (per user):** Spotify playlist via Exportify CSV (up to 20,000 rows), ListenBrainz and Last.fm history, Spotify Extended Streaming History (ZIP parsed on the device; only time, title, artist, album, ms played and end reason are sent; IP and country never leave the phone), YouTube playlists.

**Admin only:** Data queue screen (the hidden weekly queue of songs that still need Spotify's audio features), data-quality tools.

**Settings** are grouped in folders by priority (playback, downloads, replay/flow, import, lyrics, …).

## 3. Server packages and their state (`tool/server/<name>/`)

Installed by the owner (per the sessions' reports; not all re-checked today): `exportify-v1`, `history-import-v1`, `server-fixes-v1`, `moods-v1/v2`, `flow-v1`, `lyrics-v1/v2/v3`, `jam-invites-v1`, `playlist-suggestions-v2`, `reshuffle-v1`, `session-queue-v1`, `rotation-v1`, `album-overnight-v1`, `weekly-exploration-v1`, `channel-fallback-v1`, request-race, start copies (:5530) and the 1 am fake-lossless scan.

Installed on 23 Nov: `cross-device-v1` (start a queue on an idle device), `play-events-v2` (validated, idempotent play events, local hour, server weather, served log), `channels-primary-v1` (Telegram channels first), `library-enrich-v1` (genre/label/date/ISRC from MusicBrainz and Last.fm, a full run started by hand). `AI_ORDER=memory` is set. Old listening rows are tagged (burst and synthetic rows) with backups.

Built, merged, **not installed yet:** `data-queue-v1` (re-check pending), `hybrid-shadow-v1` (Smart Shuffle hybrid recorded next to v3, nothing changes for listeners until `HYBRID_ORDER=on`), `spotify-history-import-v1` (check pending).

Built, **not merged:** weekly-exploration v2 (Monday job for all eligible users, admin-only ListenBrainz hints; branch `claude/weekly-exploration-v2`), the one-queue downloader with default start and finish record (branch `claude/download-queue`).

## 4. Data and Smart Shuffle

- Listening logs are per user (`<user>_listening_log.db`): `play_events`, plus `apple_plays`, `legacy_plays`, `impressions`. Since play-events-v2 each play carries a version, an idempotency key, the local hour and, in new app builds, seconds played, source and slot.
- Findings (`docs/smart-shuffle-bakeoff.md`): for the owner's next song the blend of recency, hour habit and "what usually follows" scores 27.4% top-10, the current v3 15.6%, the legacy model 18.4%, a blend plus learned re-ranker (the hybrid) about 30%. For session openers v3 (28.7%) and the hybrid (29.7%) beat the blend (19.8%).
- Plan: hybrid in shadow first, openers stay on v3; flip rule in `docs/hybrid-shadow-spec.md`.
- Mood and energy: real Spotify features from Exportify for about 2,100 of the ~2,500 library songs (7 of 8 batches done), a calibration model (energy r about 0.89, valence only about 0.71) for the rest, predicted values always marked as predicted.
- The weekly cycle: songs arriving without Spotify data wait in the hidden data queue; once a week the admin exports a 200-song batch, transfers it with Soundiiz (free tier), exports it with Exportify and uploads the CSV.

## 5. Where things live

| What | Where |
|---|---|
| App code | `lib/` (features in `lib/features/`, screens in `lib/screens/`) |
| Server packages | `tool/server/` |
| Library export, sampler, calibration | `tool/exportify/`, `tool/shuffle_eval/` |
| Web server files | `tool/web/server/` |
| Release notes | `release-notes/2.0.0.md` |
| Audits and research | `docs/audit/`, `docs/optimization-research.md`, `docs/smart-shuffle-*.md` |
| Server logs and data | `/DATA/AppData/navivibe/` (listening logs, backups beside each DB) |
| Library | `/DATA/Media/Music` (about 76 GB) |

## 6. What is left (owner)

**Server, in order**
1. `data-queue-v1`: re-copy, `--check`, install, restart `navivibe tg-fetcher`, backfill dry run.
2. `hybrid-shadow-v1`: `--check`, install, restart `navivibe`, fit the first model, look at shadow rows after listening.
3. `spotify-history-import-v1`: `--check`, install, restart `tg-fetcher navivibe`.
4. After merge: weekly-exploration v2 and the one-queue downloader.
5. Navidrome caches (1 GB images, 500 MB transcoding); Ollama home models (3.5 GB left); a pending kernel reboot at a quiet moment.

**Data**
6. Import `Navivibe_sample_01..07.csv` in the app (one at a time, do not start a fetch).
7. The 5,000-row Spotify import: pick the popularity cut-off on the result screen, then Start Fetching.
8. Batch 8 and part of batch 7 came back empty from Spotify (reason being checked).

**Devices**
9. Update to 2.0.0 and try the artist page, Stats, peak-moment handles and the new Import Spotify History row.
10. Connect the OnePlus with adb to test background downloads (script in the session handover). Windows: music-player registration and touchpad tap.

**Decisions**
11. History import: also match the artist against the composer (about 103 plays would match)?
12. Weekly Exploration: all eligible users on Monday, or only the admin.
13. vijay: agree to import his history into his own account.
14. When to flip `HYBRID_ORDER` to `on` for next-song positions.

## 7. Known gaps (unverified items)

Background downloads on a real phone (Doze, OEM battery managers), the Android 15 service time cap, instant-start and resume timings on a device, Android "Open with" for audio files and the media session, installers for the newest packages on the live server, a 50 MB Spotify ZIP on a phone.
