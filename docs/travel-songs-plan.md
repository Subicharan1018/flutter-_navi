# Songs on my trips: listening history + Google Timeline

Goal: pick a date and see, on a map, where you were and which songs played along the way, with album covers.
Scope of this document: the **export** (done) and the **plan** for combining. The viewer is not built.

## 1. Export the listening history (done)

`tool/export_listens.py` reads Navidrome's `scrobbles` table (one row per play: user, song, time) read-only.
Nothing on the server changes. Standard library only.

```powershell
# live server over ssh (Tailscale must be up)
python tool/export_listens.py --ssh <user>@<host> --user <your navidrome user> --out listens

# one date range (UTC days, end inclusive)
python tool/export_listens.py --ssh <user>@<host> --user <user> --from 2026-11-01 --to 2026-11-22 --out listens

# with album covers (password from the environment, never typed on the command line)
$env:NAVIDROME_PASSWORD = "..."
python tool/export_listens.py --ssh <user>@<host> --user <user> --out listens `
    --covers listens_covers --navidrome-url http://<host>:4533
```

Without ssh, copy `/DATA/AppData/navidrome/data/navidrome.db` and use `--db navidrome.db`.

Output (`listens.csv` and `listens.json`), one row per play:
`played_at_utc, played_at_epoch, title, artist, album, album_artist, duration_s, song_id, album_id, cover_id`
(+ `cover_file` with `--covers`). `cover_id` is `al-<album_id>`, the id Subsonic `getCoverArt` takes.

Things to know:
- `played_at` is when Navidrome counted the play, roughly when the song had been heard, not when it started.
  For a start time use `played_at_epoch - duration_s` (a skipped song is counted only if it played long enough).
- Times are UTC. Convert to the place's time zone before matching (India is UTC+5:30, no daylight saving).
- Only plays from NaviVibe/other Navidrome clients are here. Music played in other apps is not.
- Covers are downloaded once per album (300 px JPEG), named `al-<album_id>.jpg`.
- The cover download path has not been run against the live server (it needs your password); the history export has.

## 2. Export the Google Timeline

Timeline now lives on the phone, not in Google's servers or Takeout.

1. Phone: Google Maps, profile picture, **Your Timeline**, the three dots / settings, **Export Timeline data**.
2. Save `Timeline.json` and copy it to the PC. It stays on your machine; do not upload it anywhere.
3. It only has the days the phone kept Timeline on (and not days removed by auto-delete).

Two layouts exist, a loader should accept both:

| Layout | Look for |
|---|---|
| New on-device export | top-level `semanticSegments`: each has `startTime`, `endTime` (ISO with offset) and one of `visit` (`topCandidate.placeLocation.latLng`, e.g. `"13.08°, 80.27°"`), `activity` (`start`/`end` `latLng`, `distanceMeters`, `topCandidate.type` such as `IN_PASSENGER_VEHICLE`, `WALKING`) or `timelinePath` (list of `{point, time}`) |
| Older (Takeout, "Records"/Semantic Location History) | `timelineObjects`: `placeVisit` (`location.latitudeE7/longitudeE7`, `duration.startTimestamp/endTimestamp`) and `activitySegment` (`startLocation`, `endLocation`, `waypointPath`, `activityType`) |

Times in the new export carry their own UTC offset; use it as the local time at that place.
Coordinates are `lat°, lng°` strings in the new layout and integers x 1e7 in the old one.

## 3. Combine them (plan)

Join on time, nothing else.

1. **Load plays**: `listens.json`, compute `start = played_at_epoch - duration_s`, `end = played_at_epoch`.
2. **Load Timeline** into a flat list of intervals: `{start, end, kind: visit|travel, mode, from, to, path[]}`.
   A travel segment's path is its `timelinePath` points (or waypoints; or the straight line `from -> to`).
3. **Select a date**: take the local calendar day (the time zone of the Timeline segments for that day), keep intervals and plays that overlap it.
4. **Match each play to a place**:
   - the play's midpoint falls in a `visit` interval: the song belongs to that place;
   - it falls in a travel interval: place it along the path by linear interpolation of the time between the surrounding path points (or by time fraction of the straight line);
   - it falls in a gap: use the nearest interval within 10 minutes, else "somewhere".
5. **Group**: consecutive plays in the same trip/visit become one card: "Chennai to Madurai, 5 h 10 min, 3 songs per hour", with the song list and covers.
6. **Trip soundtrack**: for a trip, list plays in order, top artist/album, total minutes of music, the song playing at the longest stretch of the route.

Edge cases to decide when building: songs spanning a segment boundary (use the midpoint), the same song replayed (show a count), a play while stationary (shows at the visit), offline plays that Navidrome recorded late (their time is the submission time; may be off), and days with no Timeline data (show the songs on a timeline with no map).

## 4. The viewer (not built; options)

| Option | Effort | Good for |
|---|---|---|
| A. One local HTML file (Leaflet + OpenStreetMap tiles, date picker, reads the two JSONs from disk) | S | Fastest; private; no server |
| B. A screen in NaviVibe ("Soundtrack of your trips") using the same join | M-L | Phone/Windows/TV; needs the Timeline file imported on the device |
| C. Python script that writes a static HTML per day | S | Sharing a single trip as a page |

Recommended first step: option A, because it needs no server and keeps the location data on your PC.
Map tiles come from OpenStreetMap over the network; for fully offline use, draw the path without tiles.

## 5. Privacy

Location history is sensitive. Keep `Timeline.json` and the combined output on your computer, do not commit them to the repository
(add `Timeline.json`, `listens.*` and `listens_covers/` to `.gitignore` before working with them), and do not paste coordinates into chats or issues.

## 6. Order of work

1. Export Timeline from the phone; open the file and check which layout it is and which dates it covers.
2. Run the listens export for the same dates.
3. Check the time zones on one known trip by hand (a song you remember at a place).
4. Build the join + viewer (option A).
