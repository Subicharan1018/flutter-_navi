# playlist-suggestions-v2: Suggested songs that fit the playlist (TODO #6)

For `/opt/shuffle-server`. Install: `bash install.sh`, then `sudo systemctl restart navivibe`. The app works before and after
(older server: same picks as before, "Refresh" filters repeats on the phone).

Patches `navivibe/discover.py` (new `fit_playlist` / `suggest_for_playlist` appended; the old ones stay above, unused) and
`navivibe/server.py` (`/predict/playlist-suggestions` reads `exclude`, up to 200 ids).

## What changes in the ranking

Old: one average of the playlist, title words, composer overlap, **0.5 x the listener's own play counts** (felt like popularity).
New, all standardised across the candidates:

| term | weight | meaning |
|---|---|---|
| near | 1.0 | audio closeness to the 3 closest playlist songs (not their average), so a kuthu + melody playlist is served from both |
| words | 0.6 | same, on song-name words |
| artist | 1.0 | share of the playlist by the candidate's artist(s): singers count now, "feat." is split |
| composer | 0.8 | share of the playlist by the candidate's composer(s) |
| mood | 0.7 | the playlist's most common moods (`mood_tags.json`) against the candidate's |
| lang | 0.4 | the playlist's language mix; a language under 2 % of it is dropped |
| taste | 0.1 | the listener's plays, tie-breaker only |

Unchanged: songs already in it never come back, the listener's blocked songs, scores only if the playlist has them, at most 4 per
composer and 2 per film. Reason line: "More Anirudh. Close to “X”", "Same mood: sad", or "Close to “X”".

**Not done:** "Flow neighbours" (songs that follow the playlist's songs in other users' sessions, `song_transitions`): that data
is not in this code base's export and I did not want to guess its shape. Offline hit-rate eval on real playlists: not run (needs the live catalog).

## Tests

`navivibe/tests/test_playlist_suggestions_v2.py` (14): two clusters both served and the average song not favoured, a Tamil playlist
gets no English, a mixed one still gets both, nothing in the playlist or excluded, the 2-song floor, artist beats a closer
stranger, singers count, mood lifts and is the reason, own plays only break ties, variety, end-to-end with `exclude`, token
splitting, the route reads `exclude`. With `test_discover` and `test_taste_exclusions`: 35 passed.
