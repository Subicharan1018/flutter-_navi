# Import a Spotify playlist from an Exportify CSV

Settings → Import → **Import a Spotify Playlist**. For accounts that may fetch songs (the same people who
see Search online). Server package: `tool/server/exportify-v1/`.

Why Exportify: Spotify's playlist links can't be used for big playlists. The bot's link reader reads
Spotify's embed page and stops at 300 songs. Exportify gives every row.

## How to export

1. Open [exportify.net](https://exportify.net) and sign in with Spotify.
2. Next to the playlist, press **Export** (one playlist as CSV). Each playlist is its own file.
3. In NaviVibe: Settings → Import → **Choose CSV File** and pick it. The file is up to 8 MB and 20,000 rows.
   (Any file type is offered, because Android hides CSVs that carry an odd type.)

The file can have a byte-order mark, Windows line endings or Windows-1252 text. What counts: **Track Name**
and **Artist Name(s)** (artists separated by `;`). Used when present: ISRC, Album Name, Release Date,
Duration (ms), Popularity and the audio-feature columns. The file is not stored: only the songs it becomes.

## What is matched, and how

Each different song is checked against your library in this order:

1. **ISRC**: the same recording. Exact.
2. **Title + artist + length**: the same clean title, at least one artist in common, and a length within
   5 seconds. "(From …)", "- From …" and "Original Motion Picture Soundtrack" are ignored. The version words
   are compared (remix, reprise, sped up, live, karaoke, unplugged, revival, male / female version …), so a
   remix never matches the plain song, and the plain song never matches a remix.

A song with the right title and artist but another length (within 25 s) stays on the wishlist, and the result
screen says how many ("may already be in your library at a different length"). Repeats in the file (the
same ISRC twice) count once. The same song in two of your imports is fetched once.

Checked by hand on 21 Nov 2026 against the live library (the two Tamil playlists, 6,838 different songs): 866 matched by ISRC, 252 by
title, 5,720 on the wishlist. In 30 random title matches and the 7 whose length differed by more than 3 s,
all were the same song. The 41 wishlist songs with the same title and an artist in common as a library
song were all other versions (karaoke, reprise, remix, lofi, another recording).

## What a fetch costs

* **Disk:** the library is FLAC, about **0.51 GB per hour of music** (about 35 MB a song). Before you start,
  the screen says "These N songs need about X GB; you have Y GB free." For the two playlists above, 5,720
  missing songs are about 210 GB; the server had 134 GB free. Cut-offs by popularity: 50+ is about 17 GB, 40+
  about 38 GB, 30+ about 58 GB, 20+ about 77 GB.
* **Bot time:** about 20 s a song (up to 2 minutes when a song isn't found: it is searched up to 6 ways).
  5,720 songs is more than a day and a half of bot time, so it is spread over nights.
* **The disk floor** (default 40 GB, 20 / 40 / 60 / 100 in the app) is never crossed. When free space falls to the
  floor, the fetch says **Paused: disk is low** and picks up by itself when space is back. A batch is trimmed
  to what fits above the floor.

## Fetching

Settings on the Wishlist screen: **order** (most popular first, the default; or your list's order), **minimum
popularity** (Spotify's 0–100 score), **songs a night** (default 100), **keep free** (the floor), and **only
at night** (1–7 am, so the bot is free in the day; **Start Fetching** always queues the first batch at once).

The server queues one batch of 25 songs at a time, checks again every 10 minutes, and stops for the night when
the cap is used. It is resumable: restart the server and it carries on. **Pause** stops new batches (the
one running finishes). **Cancel Fetch** stops the running batch too; the songs go back to the wishlist.
Songs that didn't come in are listed with why, and tried again after 3 days (twice at most) or at once with
**Try Them Again**. Each song is in one state: in your library, on the wishlist, on its way, fetched, didn't
come in, or waiting for disk.

## What the file does for songs you already have

Every song the file matches also gets its details saved on the server (never in the audio files or Navidrome's tags):
ISRC, popularity, genres, label, release date, and Spotify's audio features. This fills the ISRC for songs that had none,
gives the mood rules a second opinion from Spotify's valence and energy (it can keep or drop a label the labeller gave,
never add one; your own "Not this mood" and admin labels still win), and adds optional fields to the catalog the app
reads. Importing the same file again updates the rows. Who added each song to the Spotify playlist is never read.
Details: `tool/server/exportify-v1/README.md`.

## The playlist

**Make a Playlist** (on the result screen) makes a playlist named after the file from the songs you already
have, in the file's order, under your own login. Press it again later and only the songs that arrived since
are added.

## Not covered (rest of R12)

Spotify streaming history and Liked Songs, Last.fm / ListenBrainz scrobbles, YouTube Music Takeout. The audio
features in the CSV (danceability, energy, valence, tempo …) are stored per ISRC and used for nothing yet.
