# Import listening history (ListenBrainz and Last.fm)

Settings › Import › **Import Listening History**. Brings a person's past plays into the shuffle server's taste data
so Smart Shuffle, Flow and Back in rotation know them from day one. Server package: `tool/server/history-import-v1/`
(needs exportify-v1 and server-fixes-v1 installed first). App: `lib/features/history_import/`.

## How it works

- **ListenBrainz**: the public listens API, `GET /1/user/<name>/listens` (500 a page, walking back with `max_ts`).
  Only the username is needed: listens are public, so no token is asked for.
- **Last.fm**: `user.getRecentTracks` (200 a page). The person pastes their own API key (free at
  last.fm/api/account/create). It is kept in the app's encrypted auth box and sent with each page request only;
  the server uses it for that one request and neither stores nor logs it.
- **Paged and resumable**: the app asks for one page at a time; the server keeps the cursor in `fetch.db`
  (`history_jobs`). Closing the app, a dropped connection or a restart loses nothing; tapping Resume (or Start with the
  same name) continues. Nothing runs in the background on the server.
- **Rate limits**: one request at a time per service, at least 0.6 s (ListenBrainz) / 0.25 s (Last.fm) apart. A 429 or
  Last.fm's "rate limit exceeded" comes back as "wait N s"; the app counts it down and goes on, and stops after 8 in a
  row (resume later).
- **Matching** (the Exportify matcher): ISRC first (ListenBrainz sometimes has one), then clean title + an artist in
  common + length within 5 s. A remix, sped-up or live cut never matches the plain song.
- **Matched plays** go to the user's listening log (`play_events`, `session_id = import:<source>`, full listen ratio,
  `play_id = imp:<source>:<hash>`), the table the nightly recommender already reads, with its usual time decay. No
  weather, no genre bucket: only what the services know.
- **Unmatched songs** go on the user's Wishlist: an Exportify import named "ListenBrainz history" / "Last.fm history",
  popularity = number of plays (max 100). It is fetched with the same plan, disk floor and nightly cap as any wishlist.
- **Never double counts**: every listen has a fixed id (source, time, artist, title) kept in `history_seen`, which is also
  the play's `play_id`. Re-running, or resuming a page that was written before a crash, adds nothing. A play that is
  within 2 minutes of the same song already in the log (the app's own live play, or the other service's import: Navidrome
  scrobbles to both) is left out as a near duplicate.
- **Incremental**: after a finished import the next one asks only for listens newer than the last (`min_ts` / `from`).
- **Undo**: "Remove Imported History" deletes the imported plays, the song counts and the not-yet-fetched Wishlist songs.

## Privacy

Only the person's own account name (and, for Last.fm, their own key) is sent to ListenBrainz / Last.fm, from the
user's own server. Nothing about the library or other people is sent. Imported plays belong to that user alone.

## Known limits

- A scrobble says "played", not how much: imported plays count as full listens, and skips are not known.
- Two listens in the same second on a page boundary (ListenBrainz `max_ts` is exclusive) could lose one.
- Navidrome scrobbles to the services, so the last few weeks of the history are often also in the app's own log; the near
  duplicate rule removes them, but only within 2 minutes of the same song.
