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

## Calibration sample (the free route moves only about 500 songs)

TuneMyMusic's free tier moves 500 songs in total, so those songs are a **calibration sample**: Spotify's true energy /
valence / danceability for them train a model that predicts the same numbers for the other songs from the audio embedding.
`--sample N` picks the N songs that best cover what the model must predict (deterministic, `--seed` 1):

    python tool/exportify/library_export.py --catalog catalog.db --sample 500 --sample-report --dry-run
    python tool/exportify/library_export.py --catalog catalog.db --sample 500 --out sample_1

Upload `sample_1/navivibe_sample_01.csv` (or `.txt`). A second free batch (Soundiiz, 200 tracks per playlist) adds NEW songs:

    python tool/exportify/library_export.py --catalog catalog.db --sample 200 --exclude sample_1/navivibe_sample_01.csv --out sample_2

`--exclude` takes any earlier export file (ours, or an Exportify CSV), repeatable; songs are matched by ISRC and by clean title +
first artist. `--max-songs` still splits. How it chooses (`tool/exportify/library_sample.py`):

1. Eligible: no remix / sped-up / slowed / live / karaoke / instrumental / version words in the title, 1 to 10 minutes, not spoken
   word, and **not already labelled by Spotify** in the catalog (453 songs have Spotify values already: they are training data
   that exist, so the sample spends its 500 on new ones; `--include-have-spotify` overrides).
2. ISRC songs first; songs without one only if the ISRC pool cannot fill N.
3. The energy x valence plane (the catalog's current estimates) is cut at its own quartiles into 4 x 4 cells with equal quotas,
   served round-robin. Inside a cell the next song is the one farthest in tempo, release year and language from the recent
   picks, minus penalties for composers, genre buckets and languages already above their share of the pool.

On the 23 Nov 2026 catalog (1,808 eligible songs, 1,686 with an ISRC), `--sample 500`: 500 with ISRC, energy quartiles
126 / 131 / 136 / 107, valence quartiles 108 / 132 / 135 / 125, every one of the 16 cells holds 23 to 39 songs, 446 different
composers (at most 4 songs from one), languages en 210 / ta 180 / hi 34 / ml 17 / te 12 ..., all decades from the 1950s.
English is over-represented against the library (about 31 % of the eligible pool, 42 % of the sample) because the grid
quotas and the "farthest song" rule favour the less crowded corners; Tamil is 36 % of the sample against 55 % of the pool.

## After the Exportify export: import side

1. In Exportify export the Spotify playlist(s) made from the sample; in NaviVibe Settings → Import → Import a Spotify Playlist
   (`docs/exportify-import.md`). The server stores each matched song's Spotify features in `spotify_details.db`.
2. Copy the server data (read-only) and fit the calibration. Nothing is written to the server and nothing is applied:

       scp subi@100.99.105.51:/opt/shuffle-server/catalog.db .
       scp subi@100.99.105.51:/opt/shuffle-server/spotify_details.db .
       python tool/shuffle_eval/calibrate_audio_features.py --catalog catalog.db --details spotify_details.db --out calibration_out

   Labels are the Exportify rows plus the catalog songs already marked `feature_source = spotify`. The model is a ridge
   regression on the standardised `effnet_discogs` embedding (1,280 numbers, 2,503 of 2,504 library songs have one), the
   strength chosen by an inner cross-validation. `calibration_report.json` gives, per feature, 5-fold out-of-fold Pearson r,
   MAE and R2 (each labelled song is predicted by a model that never saw it) beside the catalog's current estimate on the songs
   where that estimate is independent of Spotify. `proposed_features.csv` lists every song with its current value, the proposed
   value and Spotify's value where known, for review. Applying them to the server (and to the recommender's inputs, which
   needs the temporal backtest first) stays the owner's decision.
3. Already measured on the 453 songs that have Spotify values today (cross-validated, no new data): energy r = 0.86 (MAE 0.069),
   valence r = 0.73 (MAE 0.119), danceability r = 0.72 (MAE 0.070). The earlier held-out check of the current calibration on 695
   Exportify songs gave r = 0.75 energy and 0.64 valence, so the embedding model looks better already, but the two numbers come
   from different song sets and are not a controlled comparison; the new report gives the like-for-like "before vs after" once
   the sample is imported.

## First batch result (23 Nov 2026) and the second batch

The owner's Exportify export of the first free batch (495 rows) was read directly, with no server import:
`python tool/shuffle_eval/calibrate_audio_features.py --catalog catalog.db --exportify My_playlist.csv --out calibration_out`.
The CSV itself is never committed (it names the Spotify account in `Added By`, which is never read either).

* **Matched:** 485 of 495 rows (442 by ISRC, 43 by title + artist + length). The other 10 are Spotify's own versions of a title
  (for example "Give Us Hope - Live", "Vaaji Vaaji") that the library does not have under that name.
* **Labelled songs now:** 814 with an embedding (the 453 the catalog already had from Spotify, plus 361 new; 124 of the 485 matched
  songs already carried Spotify values in the catalog, so "before" is measured on the 361 whose current value is an estimate).
* **Cross-validated (5-fold, out-of-fold), embedding ridge vs the catalog's current estimate, on those 361 songs (Pearson r / MAE):**

  | feature | catalog now | embedding model | all 814 labelled |
  |---|---|---|---|
  | energy | 0.80 / 0.104 | 0.89 / 0.078 | 0.88 |
  | valence | 0.68 / 0.146 | 0.71 / 0.139 | 0.72 |
  | danceability | 0.61 / 0.096 | 0.73 / 0.080 | 0.75 |
  | acousticness | 0.68 / 0.171 | 0.85 / 0.123 | 0.84 |
  | loudness (dB) | 0.66 / 1.92 | 0.85 / 1.33 | 0.87 |
  | tempo (bpm) | 0.05 / 21.4 | 0.24 / 24.1 | 0.25 |

  Valence barely improves: it is the hard one to hear in audio. Tempo cannot be learned from this embedding (r 0.24), but the
  catalog's own `bpm` agrees with Spotify's tempo up to half or double time (r 0.92, MAE 4.7 once folded), so keep `bpm`.
* **Coverage of the library by the 814 labelled songs:** energy quartiles low to high 188 / 167 / 182 / 277, valence 268 / 175 / 183 / 188
  (high-energy and low-valence songs are over-represented; the emptiest cells are energy Q2 x valence Q4, 26 of 140, and Q2 x Q3, 36 of 163);
  221 of 893 composers, but 56 % of library songs have a labelled composer; **language is the biggest gap: Tamil 85 % of the labelled set
  against 62 % of the library, English 7 % against 27 %**; decades 1950s to 1990s about 1 % labelled against 5 % of the library; in the embedding
  space only 29.5 % of the other library songs are as close to a labelled song as labelled songs are to each other (90th percentile
  distance 0.50 against a typical 0.30). Weakest groups: the 1960s and 1980s, "Asian Music" genres, Hip Hop.
* **A second batch is worth it.** `--fill-gaps` picks the eligible ISRC songs farthest (audio embedding, 40 principal components) from every
  labelled song and from each other, with a composer penalty:

      python tool/exportify/library_export.py --catalog catalog.db --sample 200 --fill-gaps --exclude My_playlist.csv --out batch2

  200 songs (117 English, 56 Tamil, 9 Hindi; valence mostly Q3 to Q4, all decades, 195 different composers), none in the first file. Simulated
  with their current estimates standing in for Spotify's, they lift the share of the library inside the typical labelled gap from 29.5 % to
  46.1 % and the 99th-percentile distance from 0.84 to 0.50. `--exclude` takes the Exportify CSV directly (ISRC first, else clean title +
  same version words + an artist in common + length within 5 s, the exportify-v1 rules, re-implemented in `tool/exportify/spotify_match.py`
  because the server's version imports server packages). Upload `batch2/navivibe_sample_01.csv` (one playlist of 200) to Soundiiz.
* Proposals only: `calibration_report.json`, `coverage.txt` and `proposed_features.csv` (current / proposed / Spotify value for every song, all six
  features) are in the shared notes folder. Nothing is applied to the server.
