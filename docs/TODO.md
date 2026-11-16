# NaviVibe to-do

Things the user hit or asked for. Nothing here is being coded yet. Newest first.

## Added 16 Nov 2026

### Bugs

| # | What the user sees | Notes |
|---|--------------------|-------|
| 1 | **Chart song won't play.** "Raga of Revenge" in Charts has no album cover and doesn't play. Searching for the same song finds it, shows the cover and plays fine. | The chart entry is probably not linked to the library song. Investigation notes are under "Chart playback" below. |
| 2 | **Online search loses the query.** Search a song that's not in the library and switch to online: it jumps straight to the song. Switching to the Album (or another) tab doesn't search again for that type. | Each tab should run its own online search for the current query. A result should open only when the user taps it. |
| 3 | **Phone local songs still have no album cover.** | Embedded art, or `cover.jpg` / `folder.jpg` next to the file, isn't being read or shown for on-device songs. |
| 4 | **Moods are wrong for most songs.** | **Fixed in the app; server package `tool/server/moods-v1/` waits for install.** Smart Playlists read the server labels (`moods` in `/catalog/songs`), the genre-word guess is gone, and "Not this mood" is on the song menu in mood Smart Playlists and mood Flow. Until the package is installed, mood rules match nothing (the catalog has no `moods` yet). |
| 5 | **Flow repeats songs.** | The user mostly hears the same songs again. Check the repeat spacing, the size of the candidate pool and the exploration share on the shuffle server. |
| 6 | **Playlist suggestions are poor.** | "Suggested songs" at the bottom of a playlist don't fit it. Base them on the playlist's own songs (artists, language, mood, Flow neighbours), not on general popularity. |

#### Cause / what to do (research, 16 Nov 2026)

Research only, nothing fixed. Server paths are on subiserver (`TG` = `/opt/tg-fetcher/tgfetch`, `SH` = `/opt/shuffle-server/navivibe`). Everything was read-only.

**#1 Chart song "Raga of Revenge" — Cause / what to do**
- **Cause (confirmed, high confidence).** The earlier guess was wrong: the entry *does* have a `song_id`, but it is dead. `fetch.db` `trending_songs` row `saavn:WZ5FUQGs` is `status=owned`, `nd_song_id=2hfFjUHcMelIcVv8lEIH9H`. In Navidrome that id is the **old file** (`Anirudh_Ravichander_–_Raga_of_Revenge_From__DC_.flac`, album "Raga of Revenge") with `missing=1`. The song now lives under a new id `0RLJDGIPOLKnl1bLYu4WZI` (`Anirudh Ravichander - Raga of Revenge (From  DC ).flac`, album "DC (Original Motion Picture Soundtrack)"); `catalog.db` shows the same pair (old row `missing=1`). So the library cover and the stream both 404 on the old id, and the app shows the chart's cover only when not playable. Title and artist are identical on both rows, so this is not an artist/title mismatch. The file was replaced and re-tagged (the doctor / re-import changed the path and album), which gives Navidrome a new id.
- **Where.** `TG/trending.py:672` (`_resolve`): `if status in PENDING or (status in ("owned","added") and nd_song_id): return song` — an owned id is never re-checked against the library. The matcher itself is `_owned` (`TG/trending.py:632`, uses `library.check` + `same_recording`; `TG/library.py:47` `load_library` reads only `missing = 0` rows, so it would find the new id). The chart API hands the stale id out unchanged at `TG/trending.py:1187` (`song_id = r["song_nd"] or r["nd_song_id"]`).
- **Size of the problem.** 3 of 538 distinct ids in `trending_songs` are dead: this song, "Manchild" (Sabrina Carpenter) and "Kaadhal En Kaviye" (Sid Sriram). It grows whenever a file is re-tagged or replaced. (Also: `trending_entries` holds many duplicate rows per chart/day, harmless but wasteful.)
- **Fix.** Server: in `_resolve`, for owned/added rows with an id, check the id is in `load_library()` ids (missing = 0); if not, clear it and run `_owned` again (it finds the new id by title+artist+length). Do the same check when building the response at `:1187` (drop ids that are not in the library, mark pending). App: keep the planned "Not in library" label and remove the "fall back to song #1" at `trending_providers.dart:96`. A one-off repair for the 3 rows ships with the install package.
- **Tests.** tg-fetcher: an owned row whose id went `missing` is re-pointed to the replacement; one with no replacement becomes `pending`. App: tapping a non-playable entry never starts song #1.
- **Size.** S (server) + S (app).

**#2 Online search jumps to a song; other tabs don't search again — Cause / what to do**
- **What the app does (read, medium confidence).** Path: normal Search screen → no library results → `NoLibraryResults` / `SearchOnlineRow` (`lib/features/online_fetch/ui/search_online_row.dart:31,61`) → `showOnlineSearch` → sheet (`online_search_sheet.dart:34`) or page on Windows. Type is local state `_type` (starts at Songs). `_setType` (`online_search_sheet.dart:70`, same in `online_search_page.dart:57`) sets the type and calls `_search`, which calls `OnlineSearchController.start(q, type:)` (`online_fetch_providers.dart:115`). `_run` increments `_generation` and resets the state to a fresh `base`, so stale `parent`/`artist` cannot leak (they are only set by `openCollection`, which hides the type switch). The app code for switching looks correct.
- **Cause of the "jumps to the song" (high confidence, server).** For a *song* search the worker first runs `check(query)` against the library (`TG/worker.py:212-214`) and, on a hit, finishes the search as `in_library`. The app then shows "Already in your library — <title> — Play" (`online_search_sheet.dart:306-314`) instead of results. `check` treats a query as owned when the title equals a library title or matches phonetically (`TG/library.py:120-130`, 100 / 96 points; `IN_LIBRARY = 90`), **ignoring the artist** because only the title is typed. So a common title (a different "Daavudi", "Pondatti") reads as "you have it" and the search never reaches the bot. Real log rows: searches 599 `daavudi` and 605 `pondatti` ended `in_library` straight away.
- **Cause of "other tabs don't search again" (medium-low confidence).** The server does receive them: searches 594, 597, 611-613 are `album` and ran. Album/artist/playlist/label searches skip the library check (`TG/worker.py:205`) and go to the source with the same text; a song title as an *album* query often returns `no_results` (611-613), and the app then says "Check the spelling, or try Songs" (`online_search_sheet.dart:318-324`), which reads as "it didn't search". Also searches run **one at a time** (`TG/worker.py:844` `claim_search`), so a type switch made while the previous song search waits on a slow bot queues behind it (up to minutes, "Still looking…"). I could not run the app, so I did not reproduce the exact tap sequence.
- **Fix.** (1) Server: an `in_library` verdict must not end the search. Return `done` with the candidates and mark owned ones (`library: in_library`), or add a flag `search_anyway`; only auto-answer "already have it" when the title *and* a typed artist agree. (2) App: replace the "Already in your library" full-screen state with a banner above the results ("You have a song with this name — Play") and never replace the results list; results open only on tap. (3) App: keep a per-type result cache in the controller (`Map<FetchSearchType, OnlineSearchState>`) so switching tabs shows each tab's own result and only searches when that tab has none; show "Searching Albums…" immediately on switch. (4) Server: let list searches (album/artist/playlist) run in parallel with a song search, or cancel the superseded one.
- **Tests.** Server: a title that matches a library song still returns candidates. App: switching Songs → Albums → Songs issues one search per type, keeps each tab's results, never shows the "Already in your library" full-screen state.
- **Size.** M (server S, app M).

**#3 Phone local songs have no album cover — Cause / what to do**
- **How it works.** Android folders are added with the system picker (SAF, `SafFileSource`, `lib/features/local_library/logic/file_source.dart:91`; Kotlin `SafChannel.kt:136` `walk`). The scan (`scanner.dart:25-81`) reads each file's tags with `audio_metadata_reader` (`tag_reader.dart:117`, `getImage: true`), saves the embedded picture (front cover first) under the app's art folder named by content hash (`tag_reader.dart:60`), else uses a `cover`/`folder`/`front`/`album`/`albumart` image in the same folder (`file_source.dart:10`; Kotlin `ART_NAMES` `SafChannel.kt:29`). The path is stored as `coverPath` in the `local_songs` table and mapped in memory (`LocalLibraryIndex`, rebuilt in `local_library_service.dart:200`); `getCoverArtUrl` returns a `file://` URI for `local:` ids (`subsonic_service.dart:224`). MediaStore is not used at all.
- **Likely causes (could not reproduce: no phone connected, so low-medium confidence; ranked).**
  1. *Old scans are never redone.* The re-scan key is only size/modified time of the audio, lyrics and art file (`scanner.dart:14`). A song scanned before its art could be read keeps `coverPath = null` forever, because nothing in the key says which version of the reader produced it. A fix to the reader alone cannot show up on already-scanned songs.
  2. *Failures are silent.* `readMetadata` errors are caught and dropped (`tag_reader.dart:118-120`), so a file the parser cannot open on the `/proc/self/fd/N` path (SAF) simply gets no art and no error.
  3. *Repaint.* Only `SongTile` watches `localIndexRevisionProvider` (`song_tile.dart:107`); album headers, grids, the mini player and Now Playing that call `getCoverArtUrl` do not, so anything built before the index finishes loading stays blank.
  4. *Coverage gaps.* Folder-art names are a short list (`AlbumArtSmall`, `Cover Art`, `art`, `artwork` are missed), no album-level fallback (one track in the album has art → give the album's other tracks the same), nothing from Android's MediaStore / `ContentResolver.loadThumbnail` (Android 10+).
- **Fix (in words).** Add a reader version to the fingerprint so a changed reader rescans songs without art; log and count unreadable art in the scan summary; give the album-level fallback (same folder or same album+artist → reuse the first art found); widen the folder-art names; as a last step ask MediaStore `loadThumbnail` for the file's content URI. Make the shared cover widgets watch the index revision once, centrally. **Before coding: reproduce on the OnePlus** — count rows with `cover_path IS NULL` in the app DB and run a scan with debug logging, to see which of 1–4 applies.
- **Tests.** Scanner: a file with art in a different name, a re-scan after a reader-version bump, an album where only one track has art. Widget: album header repaints when the index loads.
- **Size.** M.

**#4 Moods are wrong for most songs — Cause / what to do**
- **Where labels come from.** Two different sources, and the app mixes them up:
  1. *Server labels* (`SH/catalog/mood_tags.py`): one-time LLM labelling (Groq `openai/gpt-oss-120b`, 15 songs per call, `mood_tags.json`, 2,347 songs, 2,331 of the 2,355 live songs). Each song gets 1–2 of sad / romantic / happy / energetic / calm / devotional / angry. The model sees the title, film, language, key, valence/energy, essentia classifier scores and only the **first 220 characters of the lyrics** (`mood_tags.py:123`, `LYRICS_CHARS`). Flow chips and "describe a mix" use these (`flow_fit`, first label decides).
  2. *App guess* for **Smart Playlists**: `moodFromCatalog` (`lib/features/smart_playlists/data/smart_evaluator.dart:39-55`) looks for words in the genre/bucket text ("love"→romantic, "melody"→calm, "dance"→energetic, first match wins). Its comment says "the server doesn't tag mood directly", which is no longer true, and the server's own docstring warns that "Melody" is a catch-all genre. `/catalog/songs` does not send the server labels to the app.
- **Why wrong (medium-high confidence).** (a) The Smart Playlist rule uses the keyword guess, not the LLM labels: most songs get the wrong mood or none. (b) The server labels are a guess from the title/film plus the first lines: 395 labelled songs (17%) have no lyrics evidence at all. First labels are skewed (sad 762 = 33%, happy 571, romantic 393, energetic 233, angry 218, calm 91, devotional 79). Sampling 22 songs: most are plausible, a few are doubtful (K. Veeramani's Periyar songs "Engey Manakkuthu" labelled devotional/calm; "Thooriga" romantic/calm). Simple contradiction checks flag ~100 songs (41 "sad" at energy > 0.8, 27 "calm" at energy > 0.75, 22 "sad" that the classifier hears as happy). (c) A mood chip matches only the first label, so a song whose true mood is the second never appears. (d) 900 labelled songs are not Tamil, but the prompt is written for Tamil film songs. (e) Labels are never corrected by the user.
- **Fix.** Server: expose labels in `/catalog/songs` (`moods`: list) and use them in the app instead of `moodFromCatalog` (delete the keyword table); re-run `mood_audit --relabel` for the flagged songs; send longer lyrics (the full first verse plus chorus) and an English-song variant of the prompt; add "Not this mood" (long-press on a song in a mood Flow) feeding `mood_tags.json` overrides. App: Smart Playlists mood field reads `moods.first` / any of the first two. **Verify first** which screen the user means (Smart Playlists vs Home mood chips vs Flow); both paths are listed above.
- **Tests.** Server: catalog endpoint returns moods; override beats the LLM label. App: the mood rule matches on server labels, and a song with no label matches nothing (not a keyword guess).
- **Size.** M (server S–M, app S).

**#5 Flow plays repeated songs — Cause / what to do**
- **Rules (`SH/flow.py`).** A batch is 40 % fresh (never played), 50 % familiar and ~10 % exploration (`FRESH_SHARE`, `EXPLORE_SHARE`, lines 40-45). Repeat protection: a song is blocked if it was served **in the same Flow session** (`flow_seen`, line 157), is in the app's `seen` list, or is among the user's **last 50 distinct plays** (`RECENT_PLAYS`, line 45); familiar songs also need no play in the last **6 hours** (`RECENT_HOURS`, lines 44 and 206). The familiar pool is every song the user has played with a skip rate under 60 % (line 208), scored by `log1p(play weight)` plus small Gumbel noise `NOISE = 0.35` (lines 184, 212).
- **Cause (confirmed with real data, high confidence).** The protection is per session and short. `flow_seen` (`/DATA/AppData/navivibe/listening_logs/explore/state.db`) shows each Flow start is a new session of 10–40 songs, and the next session starts with a clean slate apart from the last 50 plays and 6 hours. Because the familiar score is dominated by play count (log1p spans ~0.7–2.9, noise only 0.35), the same favourites win every time. Real numbers: **sandeep** — 422 songs served over 23 sessions but only 191 distinct; 116 of those (61 %) were served in more than one session, one song in 7 sessions (Adadaa Oru, Remo Nee Kadhalan 7×); of songs he had played before, 64 % came back in another session (avg 2.3 sessions each). **admin** — 122 served, 64 distinct over 9 sessions. Pool size is not the limit (sandeep has 445 distinct played songs, 294 in the last 30 days; admin 610). The top 100 favourites made up 42 % (sandeep) / 40 % (admin) of everything served. The fresh part rarely repeats (29 % of never-played songs came back), so the repeats are the familiar half.
- **Fix.** Make the "served" memory per **user**, not per session: a cooldown of 3–7 days for a song Flow served (use `flow_seen.ts`, kept 7 days: `SEEN_KEEP_S`), and a longer cooldown for the same artist/film in a row. Replace `log1p(plays)` by a rank/z-score blended with *time since last heard* and add stronger noise (or sample from the top 3× the needed size). Raise `RECENT_PLAYS` to ~150 and scale the 6 h window to the pool size. Optional setting "Repeat less" in Flow.
- **Tests.** Server: two back-to-back sessions for a user with 400 known songs serve no song twice within the cooldown; with a tiny pool it relaxes instead of returning nothing; top-played songs no longer fill > 25 % of a batch.
- **Size.** S–M (server only).

**#6 Playlist suggestions are poor — Cause / what to do**
- **What drives them.** App: `PlaylistSuggestions` (`lib/screens/playlist_suggestions.dart:44-100`) posts the playlist's song ids to `POST /predict/playlist-suggestions` and shows library songs only. Server: `server.py:1412` → `discover.suggest_for_playlist` (`SH/discover.py:429`) → `fit_playlist` (`SH/discover.py:371`). Score = z(audio similarity to the playlist's **single average**) + z(title-word similarity to the average) + 1.2 × composer overlap + 0.5 × z(log of the *user's own plays*) (`PLAYLIST_W`, line 367). Candidates are filtered only by language share and "score" tracks.
- **Cause (medium confidence; I did not run the live ranking).** One centroid for a mixed playlist matches "average" songs, not any real cluster; no mood; artists/singers are not used (only composer tokens); the plays term (weight 0.5) lifts the user's most-played songs, which feels like popularity; nothing uses Flow/play-session neighbours. The `ids < 2` guard returns nothing for tiny playlists. The app comment says the server has no `exclude`, but the server already supports it.
- **Fix (proposal).** Score each candidate by its best match to *any* playlist song (max / top-k mean similarity, not the centroid); add: share of the playlist's artists/lyricists/singers (like the composer term), language match weighted by the playlist's mix, mood overlap from `mood_tags.json` (the playlist's top moods vs the candidate's), and **Flow neighbours**: songs that follow the playlist's songs in real listening (`song_transitions` in `model_state_*.json`, other users' sessions). Drop or cut the personal-plays term to a tie-breaker (0.1). Show the real reason ("More Anirudh", "Often played after <song>", "Same mood: sad"). Pass `exclude` from the app instead of fetching 60 and filtering.
- **Tests.** Server: a 2-cluster playlist (kuthu + melody) gets suggestions from both clusters; a Tamil-only playlist gets no English songs; suggestions never include playlist songs; mood term works. Offline eval on existing playlists (hit rate on held-out playlist songs) before/after.
- **Size.** M (server).

**#10 Show audio quality in the player — Cause / what to do (feature research)**
- **Is it transcoded?** Not by default. `getStreamUrl` adds `maxBitRate`/`format` only when transcoding is switched on in Settings (`subsonic_service.dart:200-215`, `transcoding_service.dart:76-80,200-215`; defaults: off, original, MP3 if enabled). The audio handler passes the current values (`navi_audio_handler.dart:592-595`). Downloads and the play cache use the plain `stream.view` with no parameters, i.e. the original (`offline_service.dart:304,718`). Navidrome's player rows have no forced transcoding (`transcoding_id` empty, `max_bit_rate` 0), and its profiles are mp3 192, opus 128, aac 256, flac 0. The library is 2,348 FLAC (16–24 bit, 44.1–192 kHz, 249–3,644 kbps), 2 MP3 and 5 WAV.
- **What the app knows.** `Song` has `bitRate` (kbps), `suffix`, `contentType` (`lib/models/song.dart:25-27`, parsed at `:110-114`). It does **not** read `bitDepth` or `samplingRate` (OpenSubsonic fields, present in Navidrome's rows: `bit_depth`, `sample_rate`), nor `channelCount`. Local files give `bitRate` and `suffix` only (`tag_reader.dart:161`).
- **Where to show it.** Now Playing: a small chip in the slot under the title or beside the output/share row (`now_playing_screen.dart:360-370` area, `FlowPill` slot), and the Windows transport bar tooltip. Content: lossless → "FLAC · 16-bit/44.1 kHz" (`bitRate` for lossless is not interesting); lossy → "MP3 · 320 kbps"; transcoded → "MP3 · 192 kbps · transcoded from FLAC"; offline/downloaded → add "Downloaded"; local file → "On this device".
- **Fix (in words).** Add `bitDepth`, `samplingRate` to `Song.fromJson` (+ `toMap`; the Drift mirror stores songs, so a column or a JSON blob and a schema bump from 6). Build a small `AudioQualityLabel` from the song and the *current transcoding values that were used to build the source* (so a mid-song settings change does not lie); lossless set = `flac, alac, wav, aiff, ape, wv`. If bitDepth/sampling rate are missing (older mirror), fetch `getSong` once.
- **Tests.** Label builder: FLAC 24/96, MP3 320, FLAC transcoded to MP3 192 (Settings on), local file, missing fields. Widget: chip hidden when nothing is known.
- **Size.** S–M (app only; Drift migration is the only risk).

### Features

| # | Feature | Notes |
|---|---------|-------|
| 7 | **Invite people to a Jam from inside the app.** | Pick a friend (social list) and send an invite they can accept with one tap, alongside the share link. |
| 8 | **Add from history to the queue, and a clear Queue action.** | History rows get Play next / Add to queue. The queue gets a visible "Clear queue" (keeping the current song), with undo. |
| 9 | **Upload a playlist cover image.** | Pick an image, crop it square, and store it on the server (Navidrome playlist image or our own store). Show it on every platform. |
| 10 | **Show the audio quality in the player.** | Show lossless vs. lossy and the bitrate in kbps (e.g. "FLAC · 16-bit/44.1 kHz" or "MP3 · 320 kbps"). Say when the server is transcoding the stream. |
| 11 | **Complete the album overnight.** | When a song is downloaded, find its album, mainly Indian soundtracks ("Original Motion Picture Soundtrack", "Original Score"). Queue the rest of the album to download at night. It needs a nightly window, a cap, skipping tracks already owned, and a way to see and cancel the queue. Ties in with Weekly Exploration (`docs/feature-research-2026-11.md`, Part B). |

### Chart playback (investigation)

Traced 16 Nov 2026. Not yet confirmed against the server's chart data.

**How it works.** The app never matches a chart song to the library itself. The server sends each chart entry with a `song_id` (or none), and the app trusts it:
- `lib/features/trending/data/trending_models.dart:191`: an entry counts as playable only when it has a `songId`.
- `lib/features/trending/ui/widgets/chart_row.dart:46`: the library cover is used only for playable entries. Other entries show the chart's own `coverUrl`, which here is blank. That is the missing cover.
- `lib/features/trending/ui/chart_actions.dart:11-16`: tapping an entry that isn't playable only shows a toast.
- `lib/features/trending/logic/trending_providers.dart:96`: if the tapped id is missing from the queue, playback falls back to the first song in the chart. This is a second, smaller bug.

Search works because it goes through Navidrome's own text search (`lib/services/subsonic_service.dart:741-760`).

**Cause (confirmed on the server, see bug #1 above).** Not a missing id and not an artist mismatch: the entry's `song_id` points at an old file that Navidrome now marks `missing`; the song was re-imported under a new id. (The guesses written here earlier were wrong.)

**Fix (later).**
- Server: match on the normalised main artist and title (drop "(From …)" and "Original Motion Picture Soundtrack"), and use Navidrome search as a fallback. Re-match unmatched entries whenever the library changes.
- App: label "Not in library" differently from "Downloading soon", and never fall back to song #1.
- Tests: the matcher with Tamil soundtrack credits.

## In progress (16 Nov 2026, Sonnet session "autoplay-history-drag")

- **Autoplay after a song played from search.** The autoplay setting was saved but never read back, so autoplay was off after every app start. Restore it at startup (on by default). When there are no similar songs, fall back to the artist's top songs, then the album, then random songs.
- **Drag from History into the queue**, like reordering the queue. History rows also get Play next / Add to queue (part of item 8).

## Added 16 Nov 2026 (second list)

| # | Item | Notes |
|---|------|-------|
| 12 | **Your scrobble accounts in Settings.** | Each user can add their own Last.fm and ListenBrainz accounts (ListenBrainz user token; Last.fm sign-in). Plays are scrobbled to them, and their past scrobbles can be imported (research Part C). Keep tokens in the encrypted auth box, never in logs. |
| 13 | **Reorder Settings by how often people need them.** | Most-used first: Playback (quality, autoplay, crossfade), Downloads and storage, Appearance, Accounts and scrobbling, Social and Jam, Server, Advanced and diagnostics. Rarely-used items go to the bottom, plus a search box. Apply the same order on Android, TV, Windows and web. |
| 14 | **Fetch songs from a YouTube or YouTube Music playlist link.** | The bot already accepts Deezer and Spotify playlist links (`tg-fetcher/links.py`). Add YouTube in the same way: read only the playlist's track list (titles and artists), match it to the library, and fetch the missing songs through the bot's normal source. Don't download the audio from YouTube: its terms forbid it and the quality is lossy. See "YouTube playlists" below. |

### YouTube playlists via the bot (research)

Researched 16 Nov 2026, read-only. Rule that does not change: YouTube is used **only as a list of names**. No audio, video or stream URL is ever requested from YouTube; every song is searched and fetched through the existing bot (`@deezload2bot`, lossless).

**1. How the bot handles playlist links today**
- App: the "Send a playlist" sheet (`send_playlist_sheet.dart:66`) → `OnlineSearchController.startLink` (`online_fetch_providers.dart:139`). The app checks the link first with `playlistLinkProblem` (`fetch_models.dart:59`), which today answers "Only Deezer and Spotify…" for YouTube. Then `startLinkSearch` posts `{"link": …}` to `/fetch/searches` (`online_fetch_api.dart:85`); the shuffle-server proxy forwards it (`SH/fetch_proxy.py:152`, link cut to 500 characters). The app polls the search, shows every song with an "owned / new" mark, and on confirm `downloadLink` → `POST /fetch/batches {search_id}` → `onlineFetchApi.startLinkBatch`. When the batch is done the **app** builds the user's playlist with their own Subsonic login (`fetch_playlists.dart:51`, `upsertFetchPlaylist`: same-name playlist gets only the missing songs).
- Server (`TG` = `/opt/tg-fetcher/tgfetch`): `api.py` creates a search of kind `link`; `worker.py:296-310` calls `links.parse_link` (`links.py:46`) then `links.fetch_tracks`. Deezer is read from `api.deezer.com/playlist/<id>` (title, ISRC, length, paginated); Spotify from the public embed page `open.spotify.com/embed/playlist/<id>` (`__NEXT_DATA__`). Max 300 tracks. Each track becomes a candidate; `_owned_track` (`worker.py:325`) marks it owned by title+artist+length or ISRC. YouTube is refused in `links.py:60` and the doc string says the bot gives no answer to YouTube links.
- Download: `link_batch` (`api.py:222`) makes a `playlist` batch (queue cap per user, one link at a time). `run_link_batch` (`worker.py:575`) settles owned songs, **sends the link to the bot and presses GET ALL**, collects the files it posts, and imports each (`_take` → `import_job`). Anything the bot did not deliver goes through `_fetch_by_name` (`worker.py:644`): search the bot by name and take the result whose title (and length) matches. If the bot is silent the whole batch is deferred and retried (`MAINT_*`).
- Reusable for YouTube: the track list can be filled by a new reader in `links.py` (returns `Candidate`s with title, artist, length), and `_fetch_by_name` already does "search by name → match → take". What must change: **skip `start_playlist` for YouTube** (the bot would stay silent and the batch would be deferred forever), and use a stricter matcher than title+length (see 4). `TG/trending.py` already has the better matcher (`match_queries` `:410`, `match_score` `:375`, `best_candidate`) used for charts.

**2. Ways to read a YouTube playlist's track list**

| | `ytmusicapi` `get_playlist` | YouTube Data API v3 `playlistItems.list` | Parse the web page |
|---|---|---|---|
| Sign-in | None for public playlists (`YTMusic()` without credentials) | API key only (public playlists) | None |
| Plain YouTube playlists (`PL…`) | Works as a YT Music playlist view (`VLPL…`); tracks of music videos come back clean, ordinary video uploads come back with the video title and the channel as "artist". Not tested here: confirm with a real list before building | Yes, returns video title, channel, position, `videoOwnerChannelTitle` | Yes, but only the first ~100 items without continuation tokens |
| Reliability | Unofficial: breaks when YouTube Music changes its web client; maintained and fixed quickly. Pin the version, test weekly | Official and stable | Fragile: layout and JSON shape change; consent pages |
| Terms | Not an official API; reading public metadata only | Official; needs a Google project, key and "API Services Terms". Metadata use is allowed; don't store it long-term | Scraping is against YouTube's terms |
| Quota | None, but rate-limited by IP | `playlistItems.list` = 1 unit per call of 50 items; default 10,000 units/day (≈ 500,000 songs) | None |
| Audio touched? | No (metadata calls to `music.youtube.com`) | No | No |
| Private / "Mix" / "Liked" lists | Fail (need auth) | Private fail; autogenerated Mixes (`RD…`) not supported | Fail |

  **Recommendation:** `ytmusicapi` first (no key, clean artist/album for YT Music lists, already Python like tg-fetcher), with the Data API as the fallback for plain YouTube playlists if `get_playlist` returns thin data (needs a free API key kept in tg-fetcher's `.env`, never in the app). Don't scrape pages. Run the library in a thread (`asyncio.to_thread`) with a 20 s timeout; cap 300 tracks like the other sites.

**3. Cleaning the titles (rule list, applied in this order; keep the raw title for display)**
1. Unicode-normalise (NFKC), turn `｜`/`｜`/`–`/`—` into `|` and `-`, collapse spaces, drop emoji and `🎵 ▶ ♪`.
2. Channel/artist field: strip a trailing ` - Topic` and `VEVO`, `Official`, ` Music`, ` Records`, ` Audios`, ` Lyrics`; an auto-generated "Topic" channel's name **is** the artist and its title is already clean. Labels (`Sony Music South`, `Think Music`, `T-Series`, `Lahari`, `Saregama`) are **not** artists: use them only to stop treating the channel as the artist.
3. Cut `(From "X")`, `(From 'X')`, `[From X]`, `- From "X"`, `(Original Motion Picture Soundtrack)` and keep X as the *film/album hint*, not in the search title (this is what the library stores: `Raga of Revenge (From "DC")`). Our own `bare_title` (`TG/trending.py:340`) already drops brackets for matching.
4. Remove noise tags in any brackets or after `|`/`-`: `Official (Music) Video`, `Lyric(al) Video`, `Video Song`, `Full Video`, `Audio`, `Audio Song`, `Full Song`, `Official`, `HD`, `4K`, `HQ`, `1080p`, `With Lyrics`, `Lyrics`, `Visualizer`, `Music Video`, `Promo`, `Teaser`, `Trailer`. **Keep** version words that change the song: `Remix`, `Reprise`, `Unplugged`, `Acoustic`, `Live`, `Instrumental`, `Female/Male Version`, `Slowed`, `Reverb`, `Lofi`, `Karaoke`, `Cover` (the matcher compares these on both sides: `_VARIANT_RE`, `TG/trending.py:360`).
5. Split on `|` (and ` - ` when the left part looks like an artist): the first segment is the title; the remaining segments are hints. Classify each hint: a known film/album name from the library or a number like `2024` → film/year; a known artist/composer name from the catalog (`catalog.db` has artists and composers) → artist; anything else dropped. Example: `Raga of Revenge | Leo | Anirudh | Lyric Video` → title `Raga of Revenge`, film `Leo`, artist `Anirudh`, noise `Lyric Video` removed.
6. `Artist - Title` order: if the part before ` - ` equals the channel/known artist, swap (`Anirudh Ravichander - Raga of Revenge`).
7. Strip `ft.`/`feat.`/`featuring`/`x`/`&` second artists out of the title into the artist list; keep the first artist for searching (`split_artists`, `TG/trending.py`).
8. Unicode case, whitespace and trailing punctuation cleanup; if the result is empty or only noise words, or longer than 120 characters, mark the item "couldn't read this title" (no search).
Everything above is plain Python (regexes), unit-tested with a table of real titles (start with 60 from Tamil/Telugu/English playlists, including the "Raga of Revenge | Leo | Anirudh | Lyric Video" and "(From …)" cases).

**4. Matching: cleaned title → bot search**
- Build the same song record the charts use: `{title, artist, duration_s, film}`; YouTube gives the length (use it: `DURATION_SLACK_S` already handles a few seconds; music videos are often longer, so allow a wider slack of ~15 s, or none for videos longer than 1.5× the median).
- Step 1: **owned check** before any bot call: `_owned_track` (`worker.py:325`) with title+artist+length; the cleaned film name also helps (`library.check` takes title and artist). Owned songs only go into the playlist.
- Step 2: for the rest ask the bot with `match_queries(title, artist)` (`TG/trending.py:410`): bare title, then title with bracket words, then `title first-artist`, then `first-artist title` (it times out on some `title artist` queries, so title goes first), through the existing `find_song`/`source.search`. Score every returned result with `match_score` and take `best_candidate`. That already treats a remix, a different artist or a different length as "not this song".
- Several results: take the best score; if two score within a few points (same song on two albums), prefer the one whose album equals the film hint, then the one closer in length, then the first. Never let the user pick per song (a playlist can be 200 songs); instead show the matched title/artist in the preview so a wrong match can be unticked.
- No match: the song stays in the preview as "not found" and in the batch summary ("12 of 40 couldn't be found: …") with the original YouTube title, and is **not** retried that day; trending's rule is reused (`not_found` retried after `RETRY_AFTER_S`). It never falls back to downloading anything from YouTube. The playlist is still created from the songs that landed, in YouTube's order.
- Rate: the bot is single-threaded and slow (≈ 20 s per song, `TRENDING` pacing); a 100-song list takes ~35 minutes and counts against the per-user caps (`max_queued_links`, `job_limits`) and the nightly cap proposed in item 11.

**5. Security (follow `docs/backend/SECURITY.md`, "Input validation")**
- The user supplies a link; the **server** parses it in `links.py` and requests only fixed hosts. Accept exactly: scheme `https`, host in `{youtube.com, www.youtube.com, m.youtube.com, music.youtube.com}`, path `/playlist`, a single query parameter `list` matching `^[A-Za-z0-9_-]{13,64}$` (real ids are `PL` + 32 chars, `OLAK5uy_` + 33 for album playlists; reject `RD…` mixes, `LL`, `LM`, `WL`, `UU…` with a clear message). Also accept `youtu.be/…?list=` and `watch?v=…&list=` by extracting only `list`, then rebuild the canonical `https://music.youtube.com/playlist?list=<id>`; drop every other parameter, the fragment and the credentials part of the URL.
- Never fetch the user's URL itself: the id goes to `ytmusicapi` / the Data API; no redirects followed from user input. Keep the existing 500-character cap, the per-user queue cap and the 300-track cap.
- Treat titles as untrusted text: length-cap, strip control characters, never put them into a shell, SQL (parameters only, as now) or the LLM prompt without the "data, not instructions" wrapper the other prompts use. API key (if used) lives only in tg-fetcher's `.env`; the signed internal token (`signing.py`) and the fetch-access grant apply unchanged.
- Update the app's `playlistLinkProblem` and the sheet text ("Deezer, Spotify or YouTube Music") in step with the server, so a bad paste is caught at once.
- Legal/ToS: reading public metadata only; no downloading, no stream URLs, no cookies, no account. Say so in `SECURITY.md`.

**6. What to build**

| Piece | Where | What | Size |
|---|---|---|---|
| Link parser + reader | tg-fetcher `links.py` | `youtube` site in `parse_link`/`canonical`; `_youtube()` reader via `ytmusicapi` (thread, timeout, 300 cap, skip unavailable/deleted), returns `Candidate`s | S–M |
| Title cleaner | new `tgfetch/titles.py` | the rules in section 3, table-driven tests | M |
| Matching in the batch | `worker.py` `run_link_batch` / `_fetch_by_name` | for a YouTube link skip `start_playlist`; per song: owned check → `match_queries` + `match_score` search → pick; record `not_found` with the original title | M |
| Security + docs | `links.py`, `docs/backend/SECURITY.md`, `fetch_proxy.py` (cap/forward unchanged) | strict URL and id rules, new tests (`list=` injection, `RD…`, extra params, other hosts) | S |
| Install package | `docs/backend`, install script | `pip install ytmusicapi` into tg-fetcher's venv (pin the version), restart tg-fetcher; nothing edited in place | S |
| App | `fetch_models.dart` `playlistLinkProblem`, `send_playlist_sheet.dart`, `search_online_row.dart` | accept the YouTube hosts, new copy ("Deezer, Spotify or YouTube Music"), show the cleaned title and a "not found" row state | S |
| App tests | `test/features/online_fetch` | link parsing table, preview with not-found rows | S |
| Optional | later | Data API fallback with a key; weekly check job that `get_playlist` still works | S |

Total ≈ M–L (about 3 days of work): mostly the title cleaner and the matching tests. Recommended approach: **`ytmusicapi` for the list, reuse the chart matcher and `_fetch_by_name` for the bot, strict link whitelist, no audio from YouTube.** First step before any code: run `get_playlist` on three real lists (one YT Music, one plain YouTube with lyric videos, one with "- Topic" uploads) and keep the outputs as test fixtures.

Sources checked: [ytmusicapi docs](https://ytmusicapi.readthedocs.io/en/1.6.0/reference.html) (public playlists work without credentials), [YouTube Data API quota calculator](https://developers.google.com/youtube/v3/determine_quota_cost) (`playlistItems.list` 1 unit, default 10,000 units/day).

## From the research (`docs/feature-research-2026-11.md`)

Everyday features, ranked. Sizes: S = small, M = medium, L = large.

| # | Feature | Size |
|---|---------|------|
| R1 | Rest a song: Snooze, plus auto-rest for songs you're wearing out | S |
| R2 | Back in rotation: songs you loved and stopped playing | S |
| R3 | Who's listening? Profiles on the shared TV, plus "don't count this" | S–M |
| R4 | Full listening history you can act on | S |
| R5 | Play count and last played on every song | S |
| R6 | Save the queue, and get yesterday's queue back | S |
| R7 | Playlist history and undo | S–M |
| R8 | Seasonal songs stay in season (Deepavali, Pongal, Christmas…) | S–M |
| R9 | Your own start and end points for a song | S |
| R10 | Albums for you, and shuffle by album | S–M |
| R11 | A plain shuffle you can trust | S |

The two big features:

| # | Feature | Size |
|---|---------|------|
| R12 | **Spotify history import** (Part C): match tracks to the library, feed the shuffle server, and put unmatched songs on a Wishlist. Also playlists and Liked Songs, Last.fm/ListenBrainz scrobbles, and YouTube Music Takeout. | M |
| R13 | **Weekly Exploration** (Part B): weekly picks with a preview, Keep or Not for me, Keep downloads with a weekly cap, and untouched picks expire after 2 weeks. | M–L |

Recommended order: R12, then R13, then R1 + R2 + R8. The decisions the user needs to make are at the end of the research doc.
