# Weekly Exploration

Each week the app offers about twenty songs the listener does not own, picked from what they play. They hear the first
30 seconds, then **Keep** (the song is fetched into the library at night) or **Not for me** (gone, not suggested again).
Songs left alone go after two weeks. Research and the questions this answers: `docs/feature-research-2026-11.md` Part B (R13).

- Server: `tool/server/weekly-exploration-v1/` (needs exportify-v1). Not installed until the user runs `install.sh`.
- App: `lib/features/weekly_exploration/` (data, logic, ui). Home shelf, the page, Settings › Weekly Exploration.
- Only accounts that may download see it (same rule as Search Online and Import).

## How a week's list is picked

1. **Taste ("seeds")**, made by the shuffle server (`navivibe/weekly_exploration.py`) on the first open of a week:
   the top artists of the last 4 weeks by **completed plays** (not skipped before half = 1 point; heard past the skip
   line but not to half = 0.2; skipped = 0), at least 2 points, at most 8, each with the language they are played in.
   A quiet listener (fewer than 3 such artists) gets a 120-day window. The seeds carry **names only**: no song ids,
   no times, no user name goes to any outside service.
2. **Candidates**, made by tg-fetcher (`tgfetch/weekly_exploration.py`), all public APIs with no key:
   - *More from* the 3 most played artists (iTunes Search, their songs).
   - *Like X*: artists Deezer lists as related to a seed (names only), then their songs.
   - *Two steps out*: related artists of the 4th/5th related artist, so one step further than the "near" ones.
   - *Suggested by ListenBrainz*: up to 20 recommendations from the listener's own ListenBrainz account, only when
     Navidrome holds their ListenBrainz key (Settings › ListenBrainz). Read-only on Navidrome's database; the key
     goes to `api.listenbrainz.org` only, never logged or stored.
3. **Filters**, in this order of cost: a remix, karaoke, live, sped-up or instrumental cut (`library_sweep.versions`)
   is not "a new song"; shorter than 60 s or longer than 10 min; an artist the listener marked *never recommend*;
   anything **owned** (same matcher as the Exportify import: clean title + an artist in common + length within 25 s,
   so even a "maybe owned" song is skipped); anything already on one of the listener's wishlists or imports; anything
   tombstoned (Not for me, or expired: 6 months); anything already in the list.
4. **Selection**: 20 picks. One third "far", two thirds "near". Places are shared out across languages in proportion
   to the listener's own language mix (largest remainder; a language the listener plays is never dropped). **At most
   2 songs an artist**, taken one artist at a time so nobody runs the list. Far picks are spread through the list
   (every third place), not left for the end. A short pool is topped up from the other group.
5. **Order** is the pick order. Same inputs, same list (there is no random step).

A second open in the same week tops up to 20 and never repeats a pick. A build runs in a background thread (about
40 throttled outside calls: iTunes allows about 20 a minute, so it takes about a minute) and the page shows
"Finding songs for you" and asks again every 6 s.

## Keep, Not for me, expiry

| Action | Result |
|---|---|
| Keep | The pick joins one import named **Weekly Exploration** per listener (`exportify_imports`, hidden from the Exportify screen). `exportify.tick()` fetches it: the **same** night window (1–7 am), per-night cap, 40 GB disk floor and one batch at a time as the Spotify wishlist. There is no second scheduler. |
| Weekly cap | Settings › Downloads a Week (0, 3, 5, **10**, 15, 25). Keeps handed to the queue in the last 7 days count. A Keep over the cap stays *kept* and waits (the row says "waiting its turn"); `release_waiting()` queues it as room appears, from the timer pass, after a Keep, and when the cap is raised. |
| Not for me | Gone now; the song is tombstoned for **6 months**. Two on one artist in 90 days rest the artist for 90 days. Undo is in the toast. A song already on its way (queued) cannot be passed. |
| Expire | A pending pick untouched for **14 days** goes (the timer pass and every page load do it) and is tombstoned for 6 months. A kept pick is never expired and is shown for 30 days with its download state. |
| Landed | When the fetch settles, the row says "In your library" and plays it from the library. |

## Decisions made (the open questions at the end of the research doc)

| Question | Chosen default | Why |
|---|---|---|
| 1 Acquisition | Keep fetches automatically, at night, under the weekly cap and the disk floor. No Buy link yet. | The path already exists and is paced; Keep is a deliberate tap, so the volume stays small. The legal note in B3 still stands. |
| 2 Preview or full songs | 30 s preview (iTunes `previewUrl`), no holding library. | Nothing is downloaded that nobody keeps. |
| 3 Shared or private | **Private**: a kept song goes in the shared library (Navidrome has one library) but only the keeper sees it in their Exploration. "Kept by Amma" boosts are not built. | Keep it small first. |
| 4 Size and cap | 20 picks, 10 downloads a week, adjustable 0–25 in Settings. | Matches "5–10 a week" in B3. |
| 5 Languages | Follows each listener's own mix; the "far" third is where new artists come from. No forced new language. | Flow already has language exploration. |
| Preview source | iTunes, not Deezer. From subiserver Deezer hides tracks and previews (`readable:false`, empty `preview`, empty track lists; only artist search and `related` answer), so Deezer gives names and iTunes gives songs. | Probed read-only on 21 Nov 2026. |
| Previews on the device | The app plays the Apple CDN link directly on its own player (the queue is paused, not touched). The server does not proxy audio. | A public 30 s clip: only the device's IP reaches Apple's CDN, as it does for covers. "Wi-Fi only previews" (default on) keeps mobile data out of it. |
| Why in tg-fetcher | The picking lives next to the library matcher, `fetch.db` and `tick()`. The shuffle server only sends taste. | One store, one transaction for Keep. |

## Not built (on purpose)

- A "Kept from Exploration" playlist, a notification when the list is ready, TV remote left/right, and the
  "plays a little more in Flow for 2 weeks" boost for kept songs.
- Using moods and Spotify's audio features (`spotify_details.db`) to rank candidates: outside candidates have no mood or
  audio features, and the evaluation needed first is in `docs/exportify-import.md` (Proposals). Spotify details already
  feed the owned songs' moods; they are not a signal here.
- Friends' keeps, followed artists' new releases, and a Buy link.
- Not-for-me as a learning signal for the recommender beyond the tombstones above.
- A Monday job: the list is made on the first open of the week (lazily), not at 06:00.

## Privacy

Outside calls carry an artist or song name and nothing else (tested). Previews and covers come from Apple's CDN
(`*.mzstatic.com`, `*.apple.com` over https only; anything else is dropped before it reaches the app).

## Checked on 21 Nov 2026

Tests on a scratch copy of the live code (Windows; 9 shuffle-server tests that fail there — ffmpeg, v3 replay, a
state-file path — and 1 tg-fetcher concurrency test fail for platform reasons, not these patches): see
`tool/server/weekly-exploration-v1/README.md`. Not verified live: the real iTunes and Deezer answers through a full
build, the ListenBrainz hints, a real Keep and night fetch, and the app on a phone or Windows against the server.
