# Export the whole library for Spotify (so Exportify can read it back)

Goal: get every library song into Spotify playlists, then export those with Exportify
(`docs/exportify-import.md`) to get Spotify's energy / valence / danceability / tempo / acousticness for the whole
library. `tool/exportify/library_export.py` makes the files for a playlist-transfer service. It only reads.

## Run it

Needs Python 3.9+ (standard library only). Easiest: copy the shuffle server's catalog (it has an ISRC for most songs).

    scp subi@100.99.105.51:/opt/shuffle-server/catalog.db .

    python tool/exportify/library_export.py --catalog catalog.db --dry-run

    python tool/exportify/library_export.py --catalog catalog.db --out library_export

Optional, more ISRCs (once exportify-v1 has made it): `--details spotify_details.db`.
Straight from Navidrome instead (credentials from the environment, never typed on the command line or printed):

    $env:NAVIDROME_USER = "<user>"; $env:NAVIDROME_PASSWORD = "<password>"; python tool/exportify/library_export.py --subsonic http://100.99.105.51:4533 --dry-run

The dry run prints the song count, how many have an ISRC, and how many playlists / files would be written.
On a copy of the live catalog (23 Nov 2026): 2,483 songs, 2,261 with an ISRC, 1 playlist, 2 files.

Output in `library_export/`: `navivibe_library_01.csv` (columns `title, artist, album, album artist, duration,
isrc`; UTF-8 with BOM; `duration` in seconds) and `navivibe_library_01.txt` (`Artist - Title` per line). More
playlists are numbered `_02`, `_03` ... at most 9,500 songs each (Spotify's cap is 10,000). `--formats csv,txt,m3u8`
chooses; `--max-songs` changes the split. Songs without a title are dropped; the same ISRC (or title + artist + length)
counts once.

## Upload

1. [TuneMyMusic](https://www.tunemymusic.com/transfer/file-to-spotify) → Upload file → pick `navivibe_library_01.csv`
   (or `.txt`) → Spotify. Its page lists M3U, M3U8, PLS, XSPF, WPL, XML, CSV and TXT, and says it splits a playlist over
   10,000 tracks by itself.
2. Or [Soundiiz](https://soundiiz.com/tutorial/import-excel-to-soundiiz): Import playlist → from file (CSV).
3. In Exportify, export those playlists and import the CSVs in NaviVibe as usual.

## What was verified and what was not

Verified: the two services' own pages name CSV and TXT as accepted file types for uploading a playlist (TuneMyMusic
page read 23 Nov 2026; Soundiiz's tutorial page names CSV (Excel) import; third-party guides add TXT/M3U/XSPF).
The script itself: 11 tests (splitting at the cap, CSV quoting of commas / quotes / line breaks, Tamil and other
Unicode, ISRC cleaning, Subsonic paging and that the password is never in a printed URL), and a dry run on a copy of
the live catalog.

Not verified: neither service documents which **column headers** a CSV needs, so the CSV uses plain names
(title / artist / album ...) and I could not upload one. If a service does not read the columns, use the `.txt`
file (`Artist - Title`, the format TuneMyMusic documents for text), which matches by name and artist only. Match rate
(Tamil film songs on Spotify), service free-tier limits and account login were not tested. The Subsonic source was
tested against a fake server only, not live Navidrome.
