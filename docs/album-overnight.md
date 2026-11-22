# Album Overnight

When a song you fetched lands in the library, the rest of its **film album** that you do not have is queued to
download at night. Settings › Album Overnight turns it on, sets the limits and shows the queue with Cancel.
(TODO item 11.)

- Server: `tool/server/album-overnight-v1/` (needs exportify-v1). Not installed until the user runs `install.sh`.
  README there has the exact rules, the patches and the install steps.
- App: `lib/features/album_overnight/` (data, logic, ui). Settings › Album Overnight (switch, Film Albums Only, Songs a
  Night, Most Per Album, Queue). Only accounts that may download see it (same rule as Search Online, Import, Weekly Exploration).
- **No second scheduler.** The tracks join one Exportify import per listener named "Album Overnight" (hidden from the
  Exportify screen), so `exportify.tick()` fetches them: night window 1–7 am, per-night cap, 40 GB disk floor, one batch at
  a time, pause and cancel. Same as Weekly Exploration (`docs/weekly-exploration.md`). The Exportify timer must be on.

## What counts as "a song you asked for"

A download that finished after the switch was turned on, for that listener, that is not from Exportify, Weekly
Exploration or a playlist / chart import (a batch of more than 5 songs). Turning it on never mines the old library.

## Finding the album

iTunes Search (public, no key; only a title, artist and album name leave the server). The album is accepted only when the song
that triggered it is in the album's track list, so a different album with the same name is never queued. Default is film
albums only (name says soundtrack / score / motion picture / "From …", or iTunes' genre is Soundtrack, Bollywood, Tamil, Telugu,
Malayalam, Kannada, Marathi, Bengali, Gujarati, Punjabi, Bhojpuri). Singles, compilations (over 40 tracks), tracks under 20 s,
karaoke and instrumental cuts, and anything you own (same matcher as the Exportify import) are skipped.

## Limits (all adjustable in the app except the first two)

| Limit | Value |
|---|---|
| Waiting at once, all albums | 150 tracks (a full queue: the song is looked at again later) |
| Looked at | 5 songs per timer pass; a landed song for 3 days |
| Tracks an album | 25 (5 / 10 / 15 / 25 / 40) |
| Songs a night | 30 (10 / 20 / 30 / 50 / 100); shared with the user's other Exportify fetches |

## See and cancel

The Queue page lists each album with its cover, what it was triggered by, and where its tracks are (waiting for tonight,
on their way, in your library, to try again); tap to see the tracks. **Cancel** drops an album's tracks that are not with
the bot yet and the album is never queued again; a track already in a running batch finishes. **Cancel all** asks first.
Switching the feature off pauses the plan and stops looking at new songs.

## Not built

Albums for bulk imports, a "complete this album" button on an album page, a second album source (MusicBrainz), a
notification when an album is complete.
