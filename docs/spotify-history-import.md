# Import Spotify history

Settings › Import › **Import Spotify History**. Brings a person's Spotify plays into their Smart Shuffle, Flow and Back in
Rotation data, **with real skips**, which the app's own logs lack. Server package: `tool/server/spotify-history-import-v1/`.
App: `lib/features/spotify_import/`.

1. At spotify.com/account/privacy ask for **Extended streaming history** (not "Account data"). Spotify emails a ZIP, from a few days to 30 days later.
2. In the app choose that ZIP (or the `Streaming_History_Audio_*.json` files). The older basic export (`StreamingHistory0.json`) also works.
3. The file is read on the device. The screen shows what it holds and what was left out. Tap **Import**.

## What is read, what is dropped

Read per song played: time, title, artist, album, how long it played, how it ended (`reason_end`) and Spotify's `skipped` flag.
Dropped on the device before anything is sent: IP address, country, platform, connection and offline details, track URIs, podcast
episodes, audiobooks, the video files, and plays made in Private Session. Nothing else is stored; file contents are never logged.

## Skip rule

A play under 30 s that ended with the forward/back button (or that Spotify flags `skipped`) is a skip. A play of 30 s or more, or one
that ran to its end, is a listen, with listen ratio = seconds played / the song's length. A short play that ended another way (logout,
app closed) is left out. In the basic export (no reason) a play under 30 s counts as a skip.

## Matching, duplicates, undo

Songs are matched to the library by clean title and an artist in common (remix / sped-up / live versions never match the plain song).
Matched plays join the person's own listening log (`import:spotify`); songs they listened to that the library lacks go on their Wishlist
(fetched only by the wishlist's own plan and caps). Importing the same file again adds nothing; a play within 2 minutes of the same song
already logged is left out. **Remove Imported History** takes back the plays and the not-yet-fetched Wishlist songs. Only the person's own
data is touched.

## Known limits

Spotify names the album artist (often the composer for film songs) where the library names the singers, so some songs the library has do
not match by artist. A big export is read in a background isolate and sent about 1,000 plays a page; after closing the app, choose the same
file again to resume.
