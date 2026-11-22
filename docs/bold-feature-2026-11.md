# Bold feature, November 2026: the Artist page becomes "The Run"

## Scan

| Screen | State | Verdict |
|---|---|---|
| Search online, Smart Shuffle, Replay, Windows mini player, lyrics | redone this month | leave |
| Now Playing | lyrics and player critiqued and rebuilt (docs/player-ui-critique-2026-11.md) | leave |
| Album page | another session ("Complete the album overnight") is on it | avoid collision |
| Playlists, Jam | "Playlist suggestions + Jam invite" session is on it | avoid collision |
| Settings, History, Queue saves, Rotation, Scrobble import | in flight in sibling sessions | avoid collision |
| Stats | big figures and charts, already strong | leave |
| Home | shelves; busy with Discover/Weekly work | leave |
| **Artist page** | 212 lines: portrait, Top Songs, then a flat "Albums" shelf | **weakest page, untouched, high value** |

The Artist page is the one place where the app knows a lot and shows nothing.
It has the full discography with years (`Album.year`), and the app's own
listening database (`play_events` joined to `song_metadata`) knows every play
of every song. The page shows neither the shape of a career nor the
listener's relationship with it. For this audience (Tamil film music, where an
artist is a music director with 30 years of scores) the career is the story:
Ilaiyaraaja in the 80s, Rahman from 1992, Anirudh now.

## The idea: The Run

Two additions, one idea, both read from data already on the device:

1. **With you** (typographic, no cards). Your plays, your listening time, "since
   Mar 2022", last played, and your most played song by this artist.
   Only real numbers; if you have never played them, the block does not
   appear (no empty-state marketing).
2. **The Run** replaces the flat Albums shelf for any artist with 2+ albums.
   - A **career strip** across the top: one bar per year from first to latest
     release, height = songs released that year. Years you have listened to
     are white, the rest `accent-dim`. Static, drawn once, no animation.
   - A **year spine**: each year is a row (big tabular numeral, hairline
     spine, the covers released that year). Under every cover a hairline fills
     to your share of plays for that album, so the page shows at a glance
     which era you actually live in. Tap the year to play that year's albums.

Why it fits NaviVibe: monochrome (white vs dim), no containers (hairlines and
numerals, like the Replay month ledger), honest (every figure comes from the
play log), and the art-size scale is kept (covers derive from `ArtSize.tile`).

## Performance rules

- One `customSelect` per artist (autoDispose, indexed by song id), no stream.
- Career strip is a `CustomPaint` painted once. There is no controller, so
  nothing runs when the page is idle (desktop idle CPU stays flat).
- Year rows build lazily as slivers; a 100-album artist builds only visible
  rows.

## Not doing

- Fetching extra artist metadata or bios (needs server work, invents claims).
- Animated career scrubber (an always-on frame loop is banned on desktop).
