# Features other players have that NaviVibe lacks (26 Nov 2026)

Research only: **nothing here is built**. Pick the ones you want.

## How this was checked

Each candidate was searched for in `lib/` and `android/app/src/main/` before it was listed. "Not found" means the
search for its names and APIs came up empty or hit only unrelated code; it is not a line-by-line audit. The
comparison is with Spotify, Apple Music, YouTube Music and open-source Subsonic clients (Symfonium is closed source
but is the usual Android benchmark; Tempus, Ultrasonic, DSub, Amperfy, Feishin, Supersonic). The client survey
builds on the earlier `feature-scout-research.md` (14 Nov) and `feature-research-2026-11.md`. A few web searches
on 26 Nov added little: they confirmed internet radio and star ratings in some clients, not much else, so the
competitor claims below rest mostly on general knowledge of those apps.

**Left out because NaviVibe already has it:** equalizer and loudness normalisation (this branch), crossfade,
gapless, speed, sleep timer, queue editing and saved queues, downloads and auto-download, play cache, smart
playlists, folders, lyrics (synced, translate), search in long playlists, Android Auto, home-screen widgets, voice
"play X on NaviVibe", like/shuffle/repeat buttons on the notification, device hand-over, Jam, Blend, Recap, Replay,
stats, history, share cards and links, imports, song recognition, thumbs up/down, never-recommend, profiles,
Windows media keys, tray and mini player. Autoplay already continues with similar songs.

**Left out because another session is on it:** film and credits pages, swipe-to-fetch previews, Wrapped, Now
Playing and desktop UI work.

## Ranked list

Effort: **S** about one session, **M** 2–4 sessions, **L** a multi-session project.
Platforms: **P** Android phone, **TV** Android TV, **W** Windows, **Web**.

| # | Feature | What it does | Effort | Platforms | Server work |
|---|---------|--------------|--------|-----------|-------------|
| 1 | **Offline mode switch** | One switch: play and show only downloaded music, use no data. The status page already has an "Offline mode" line, but the value behind it is fixed to off, so there is no way to turn it on. | S | P, TV, W | none |
| 2 | **Start radio** (song, artist, album, playlist) | An "endless mix from this" item in menus. The similar-songs logic exists for Autoplay; there is no button to start from a chosen item. | S | all | none (Flow or Smart Shuffle could improve it) |
| 3 | **Select many songs on phone** | Long-press to tick several songs, then queue, add to playlist, download or remove at once. Today only the desktop table can. | M | P, TV | none |
| 4 | **Headphone and car behaviour** | Resume when Bluetooth headphones or the car connect (off by default), and remember the equalizer preset and normalisation per output. Builds on the new equalizer. | M | P | none |
| 5 | **Cast to speakers and TVs** | Chromecast first; DLNA/Sonos/AirPlay later, or all of them through a Music Assistant server. The most visible gap against every competitor. Caveat: casting bypasses the app's equalizer, and the speaker must be able to reach the server. | L (M for Chromecast only) | P, W (Web: Chrome only) | none for Chromecast; a container for Music Assistant |
| 6 | **Follow artists and composers: new releases** | A "New for you" shelf and notification when a followed artist or music director releases something; optionally fetch it. | M | all | fetcher: follow list and daily check |
| 7 | **Complete this album** | The album page shows the songs you do not have, with "Fetch the rest". | S–M | all | track-list lookup |
| 8 | **Artist About and similar artists** | Biography and "fans also like" on the artist page (`getArtistInfo2`). Often empty for Tamil artists without a good data source. | S (app), M with a better source | all | Navidrome agents |
| 9 | **App shortcuts and Quick Settings tile** | Long-press the app icon for Search, Shuffle all, Downloads, Recognize; a tile for "recognise this song". | S | P | none |
| 10 | **Skip silence at the start and end** | Skips dead air, so crossfade starts on music. A manual start/end point per song exists; nothing automatic does. | S (server-measured), S (Android only, on device) | all with server data | silence measurement |
| 11 | **Internet radio** | Stations from Navidrome, including Tamil FM streams, with the title shown. | S–M | all | add stations in Navidrome |
| 12 | **Playlist export and import (M3U / CSV)** | Take a playlist out, or bring one in as a file. Spotify CSV and YouTube imports exist; there is no export. | S | P, W, Web | none |
| 13 | **Star ratings (1–5)** | Show and set Navidrome stars. Today thumbs up and down write 5 and 1 behind the scenes. | S | all | none |
| 14 | **Tap-to-sync lyrics editor** | Add timing to plain lyrics line by line and publish to LRCLIB. Useful for Tamil songs without synced lyrics. | M | P, W | optional store |
| 15 | **Audio output picker** | Choose the speaker or headphones from Now Playing (Android's output switcher; a device list on Windows). | S (Android), M (Windows) | P, W | none |
| 16 | **Tamil (and other) interface language** | All app text is English only; there is no translation framework. | L | all | none |
| 17 | **Wake to music** | An alarm that starts a playlist. Android limits make it fiddly to do reliably. | M | P | none |
| 18 | **Car mode screen** | Large controls for phones mounted in cars without Android Auto. | S–M | P | none |
| 19 | **Wear OS controls or app** | Media controls already show on watches; a real app with offline songs is the missing part. | L | watch | none |
| 20 | **Bookmarks for long tracks** | Remember the position in concerts and medleys (Subsonic bookmarks). | S | all | none |
| 21 | **Discord status (Windows)** | "Listening to …" on Discord. | S | W | none |

## Not worth it (my view)

- **Podcasts and audiobooks:** Navidrome has no podcast support, and this is a music library.
- **Folder browsing, visualizers, Canvas-style videos:** little use with a well-tagged library.
- **Vocal removal (Apple Music Sing):** needs heavy server processing for each song.

## My suggestion

Start with **1, 2 and 9** (small, expected everywhere, no server work). Then **3** and **4**. Take **5** as its own
project if you have speakers or a cast-capable TV; **6** and **7** if "the library fills itself" matters most.
