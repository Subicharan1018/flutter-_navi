# Feature research, November 2026: everyday wins, Weekly Exploration, and Migration

Research only (14 Nov 2026). Nothing here is built. It follows on from three earlier reports and does not repeat
them:

- `docs/feature-scout-research.md` already proposes: follow an artist → auto-fetch new releases (#1), a quality
  guard (#2), swipe-to-fetch 30 s previews (#3), film/credits pages (#4), an Offline Mixtape (#5), speakers (#6),
  history import (#7, only one paragraph), auto silence trimming (#12), more than one queue (#14), and more.
- `docs/ui-innovation-research.md` covers new UI ideas (Song Score, Mood Atlas, Moments…).
- `docs/smart-shuffle-eval.md` found that the AI ordering in Smart Shuffle shows no measurable gain yet.

Where an idea here builds on one of those, it says so (for example "builds on scout #3").

Effort: **S** = about one session, **M** = 2–4 sessions, **L** = a multi-session project.
Gold-plating risk: **Low** = most people would use it weekly; **Med** = useful, but easy to over-build;
**High** = few people would notice.

**What NaviVibe already has (checked in `lib/` and `docs/backend/ARCHITECTURE.md`), so it is left out:** Flow,
Smart Shuffle, Weekly Mix, Discover ("New in your library" + never-played songs), Trending, Taste and
*never recommend* (a permanent block), smart playlists, Jam, Collab, Blend, Recap, Replay, Month story, Stats,
session sync, Play next, downloads, local files, recognition, lyrics, and the tg-fetcher pipeline (search the
Telegram music bot, rank, download FLAC, tag, move into the library, rescan). Things I looked for and did **not**
find: snooze, a forgotten-favourites shelf, profiles or a guest mode, seasonal handling, per-song start/end times,
saving a normal queue as a playlist (only Jam can save to a Collab), playlist undo or history.

---

## Part A: everyday features people ask for that no player does well

### How I picked them

I kept an idea only if (1) it comes up again and again on the Spotify Ideas board, Reddit or other player forums,
(2) the big services either don't ship it or ship a weak version, and (3) it suits a family-sized server whose
shuffle server already holds every play. I dropped ideas that only a small group would use, and ideas already in
the scout report.

### Ranked shortlist

| # | Feature | Who has it today, and the gap | Effort | Gold-plating risk |
|---|---|---|---|---|
| 1 | **Rest a song: Snooze plus "you're wearing this out"** | Spotify Snooze is manual, 30 days, Premium only | S | Low |
| 2 | **Back in rotation: songs you loved and stopped playing** | YouTube Music built a "Forgotten favourites" shelf; Spotify's On Repeat only looks at recent plays | S | Low |
| 3 | **Who's listening? Profiles on the shared TV, plus "don't count this"** | Spotify's profile idea was closed; its kids-music switch only arrived in Sept 2026 | S–M | Low |
| 4 | **Full listening history you can act on** | Spotify desktop shows 50 tracks; its API caps at 50 | S | Low |
| 5 | **Play count and last played on every song** | Spotify idea "Not Right Now", 943 votes | S | Low |
| 6 | **Save the queue, and get yesterday's queue back** | Spotify users still ask; an idea thread runs 8+ pages | S | Low |
| 7 | **Playlist history and undo** | Spotify can't restore removed songs; the version-history idea is still open | S–M | Low |
| 8 | **Seasonal songs stay in season** | Nobody does it automatically; requests on Spotify, Apple and Roon forums | S–M | Med |
| 9 | **My start and end points for a song** | Spotify idea open for years (54+ pages) | S | Med |
| 10 | **Albums for you, and shuffle by album** | r/spotify "Why does Spotify hate albums?"; several Symfonium requests | S–M | Med |
| 11 | **A plain shuffle you can trust** | Spotify's "Fewer Repeats" (Dec 2025) still uses history; users wanted plain random | S | Med |

#### 1. Rest a song: Snooze plus "you're wearing this out"
- **Evidence.** Spotify added Snooze in 2025: a song stays out of recommendations for 30 days
  ([TechRadar](https://www.techradar.com/audio/audio-streaming/spotifys-new-snooze-button-will-let-you-blacklist-unwanted-songs-for-a-month-and-i-wish-it-had-existed-earlier),
  [9to5Mac](https://9to5mac.com/2025/05/07/spotify-snooze-feature-more/),
  [Spotify newsroom](https://newsroom.spotify.com/2025-09-05/new-user-controls-personalize-listening/)). Spotify
  built it after years of "dislike" requests, and the
  [DISLIKE BUTTON idea](https://community.spotify.com/t5/Live-Ideas/DISLIKE-BUTTON/idc-p/5650062) is still open
  because "hide" works on one playlist only.
- **Where others fall short.** It is manual, Premium-only and always 30 days. Nobody notices for you that you have
  played a song 25 times this fortnight and have started skipping it.
- **NaviVibe fit.** *Never recommend* is permanent. A snooze (2 weeks / 1 month / 3 months) belongs beside it in the
  same menu. The shuffle server can also spot burnout itself: plays per week jumped, then early skips rose. Flow and
  Smart Shuffle would then rest the song quietly and show it once in Taste ("Resting: 4 songs, back on 12 Dec").
- **Effort / risk.** S (one table and a filter in the queue builders; one menu item). Low.

#### 2. Back in rotation: songs you loved and stopped playing
- **Evidence.** YouTube Music worked on a "Forgotten favourites" shelf
  ([Android Headlines](https://www.androidheadlines.com/2022/06/youtube-music-forgotten-favorites-list-section.html)).
  On Spotify a request for this was answered with "use On Repeat", which only looks at recent plays
  ([Spotify Community](https://community.spotify.com/t5/Your-Library/An-automatically-generated-playlist-with-your-recent-favourite/td-p/5332895)).
- **Where others fall short.** Mixes lean on recent listening, so last year's favourites disappear.
- **NaviVibe fit.** Very good. The per-user listening log has every play with `listen_ratio`. Pick songs with many
  full plays more than 3 months ago and none in the last 60 days. Show them as a Home shelf and let Flow use them as
  "comfort" picks. It also works for new users once Part C has imported their Spotify years.
- **Effort / risk.** S. Low.

#### 3. Who's listening? Profiles on the shared TV, plus "don't count this"
- **Evidence.** Spotify's idea "Allow multiple profiles on the same device" was closed for too few votes
  ([idea](https://community.spotify.com/t5/Live-Ideas/All-Platforms-Other-Allow-multiple-profiles-on-the-same-device/idc-p/5033208)),
  but the problem is old and loud: kids' songs fill parents' recommendations and Wrapped
  ([Scary Mommy](https://www.scarymommy.com/parenting/kids-ruin-parents-spotify-wrapped),
  [Spotify Community](https://community.spotify.com/t5/Your-Library/quot-Your-Discover-Weekly-quot-playlist-ruined-by-lullabies/m-p/4868204)).
  Spotify only added a "keep kids' music out of my taste profile" switch in September 2026
  ([BGR](https://www.bgr.com/2262206/spotify-wrapped-recommendation-setting-parents-exclude-kids-music/),
  [Android Authority](https://www.androidauthority.com/spotify-avoid-kids-music-recommendations-wrapped-3711110/)).
  People also ask to switch accounts on a TV without typing with a remote
  ([idea](https://community.spotify.com/t5/Implemented-Ideas/Account-Quickly-switch-between-saved-Accounts/idi-p/1289104/page/34)).
- **NaviVibe fit.** This is the family case exactly: one living-room TV, several Navidrome accounts. Two pieces:
  (a) a "Who's listening?" picker on TV and Windows that remembers each family member's login (phone pairing
  already exists, so a phone can approve the switch); (b) a per-session "Don't count this" switch (guests, kids,
  a party) that still plays but marks plays as excluded, so they stay out of Flow, Replay and Recap.
- **Effort / risk.** S–M (credential storage per profile; one flag on play events). Low.

#### 4. Full listening history you can act on
- **Evidence.** The Spotify idea "I want complete history of all songs" is still open
  ([idea](https://community.spotify.com/t5/Live-Ideas/All-Platforms-I-want-complete-history-of-all-songs/idi-p/5062117/page/4));
  desktop shows only the last 50 tracks
  ([Spotify Community](https://community.spotify.com/t5/Your-Library/Listening-History-on-Desktop/m-p/6373911/highlight/true)),
  and the Web API's recently-played call is also capped at 50
  ([Spotify Community](https://community.spotify.com/t5/Spotify-for-Developers/How-does-last-fm-retrieve-a-user-s-full-listening-history/td-p/5945101)).
- **NaviVibe fit.** The server already keeps everything. A History page grouped by day, with "Play from here",
  "Make a playlist from this evening", and search ("that song on Tuesday night"). It answers the everyday "what
  was that song?" question that recognition can't.
- **Effort / risk.** S (one paged endpoint and one list screen). Low.

#### 5. Play count and last played on every song
- **Evidence.** "Show play count for all songs in mobile app" has 943 votes and the status *Not Right Now*
  ([idea](https://community.spotify.com/t5/Live-Ideas/Show-play-count-for-all-songs-in-mobile-app-not-just-the-popular/idi-p/5612097),
  [most-kudoed list](https://community.spotify.com/t5/Live-Ideas/idb-p/ideas_live/page/7/tab/most-kudoed));
  people still miss it from Google Play Music
  ([Droid Life](https://www.droid-life.com/2021/03/09/another-thing-i-miss-about-google-play-music-play-count-for-tracks/)).
- **NaviVibe fit.** Navidrome already returns `playCount` and `played` on every song. Show them in the song sheet
  and as a quiet second line in tables, and add sort options. Use the shuffle server's count when it is higher
  (imported plays from Part C).
- **Effort / risk.** S. Low.

#### 6. Save the queue, and get yesterday's queue back
- **Evidence.** "Queue: Playlist from current Queue" is a long-running Spotify idea
  ([idea](https://community.spotify.com/t5/Live-Ideas/Queue-Playlist-from-current-Queue/idi-p/1586088/page/8));
  Android Central notes you can't save the playing queue as a playlist
  ([Android Central](https://androidcentral.com/spotify-add-queue)).
- **NaviVibe fit.** Flow and Smart Shuffle build very good queues that vanish. "Save as playlist" in the queue
  pane, plus "Recent queues" (the last 10 queues, kept by session sync) to bring one back. This is the cheap
  version of scout #14 (several named queues); build this first.
- **Effort / risk.** S. Low.

#### 7. Playlist history and undo
- **Evidence.** Spotify's version-history idea is still open
  ([idea](https://community.spotify.com/t5/Live-Ideas/Option-to-Enable-Version-History-for-Playlists/idc-p/5586195));
  staff say removed songs can't be restored
  ([thread](https://community.spotify.com/t5/Your-Library/How-do-I-restore-removed-songs/td-p/5503108)); one user
  lost about 2,100 Liked Songs in one tap with no undo
  ([thread](https://community.spotify.com/t5/Your-Library/I-accidentally-deleted-my-entire-Liked-Songs-library-and-Spotify/m-p/5454549/highlight/true)).
- **NaviVibe fit.** Collab playlists are edited by several family members, and Navidrome keeps no history. The
  shuffle server can snapshot each playlist when the app changes it (and nightly). Add "Recently removed"
  and "Restore this version" on the playlist page.
- **Effort / risk.** S–M. Low.

#### 8. Seasonal songs stay in season
- **Evidence.** Users ask Spotify to hold back songs that are mostly played in December
  ([Spotify Community](https://community.spotify.com/t5/Your-Library/Community-Discover-Christmas-Music-Ends-After-Christmas/m-p/6639298/highlight/true)),
  Discover Weekly fills with holiday songs into February
  ([thread](https://community.spotify.com/t5/Your-Library/Discover-Weekly-Stuck/td-p/4889374/page/2)), and the
  same request appears for Roon
  ([Roon](https://community.roonlabs.com/t/how-can-i-stop-roon-radio-from-playing-holiday-christmas-music-except-at-christmastime/253296))
  and Apple Music, where people work around it by hand
  ([TidBITS](https://tidbits.com/2025/12/15/how-the-music-apps-skip-when-shuffling-option-can-help-or-hinder-holiday-playlists/)).
- **NaviVibe fit.** For this household the seasons are festivals and devotional periods (Deepavali, Pongal,
  Navaratri, Ayyappa season) as well as Christmas. The server can find songs whose plays bunch into the same few
  weeks year after year, then keep them out of shuffle the rest of the year; a manual "seasonal" tag covers songs
  without enough history.
- **Effort / risk.** S–M. Med: detection needs a year or more of history (Part C import helps), so start with the
  manual tag.

#### 9. My start and end points for a song
- **Evidence.** "Custom Start & Ending Times for a Track" has run for years on Spotify, 54+ pages, with no answer
  ([idea](https://community.spotify.com/t5/Live-Ideas/Music-Custom-Start-amp-Ending-Times-for-a-Track/idi-p/40013/highlight/true/page/54)).
- **NaviVibe fit.** Film songs often have long dialogue intros. Scout #12 trims silence automatically; this is the
  personal version ("always start at 0:42"), stored per user on the shuffle server so every device honours it, and
  crossfade uses it.
- **Effort / risk.** S. Med (keep it to two drag handles on the seek bar; no loops or A–B repeat).

#### 10. Albums for you, and shuffle by album
- **Evidence.** "Why does Spotify hate albums?" on r/spotify asks for album-only discovery
  ([thread](https://redlib.belloworld.it/r/spotify/comments/1glxh5a/why_does_spotify_hate_albums));
  Symfonium users ask to shuffle by album and to keep playing album by album
  ([shuffle by album](https://support.symfonium.app/t/unable-to-shuffle-playlist-by-album-title/4617),
  [continuous by album](https://support.symfonium.app/t/allow-continuous-playback-by-album/4334),
  [random albums](https://support.symfonium.app/t/sort-regular-playlist-by-random-album/6658)).
- **NaviVibe fit.** Film soundtracks are albums people play end to end. Add an "Albums for you" shelf (albums
  where you love one or two songs and haven't heard the rest), and "Shuffle albums" (albums in random order,
  songs in order).
- **Effort / risk.** S–M. Med.

#### 11. A plain shuffle you can trust
- **Evidence.** "Option to have a true shuffle" was Spotify's biggest shuffle thread (thousands of votes, 200+
  pages). It was marked Implemented in Dec 2025 with "Fewer Repeats", which still uses listening history, and many
  commenters said that is not what they asked for
  ([idea](https://community.spotify.com/t5/Live-Ideas/All-Platforms-Option-to-have-a-true-shuffle/idi-p/4880594/page/206),
  [follow-up](https://community.spotify.com/t5/Live-Ideas/WE-NEED-PURE-SHUFFLE/idc-p/6764664/highlight/true)).
- **NaviVibe fit.** Keep Smart Shuffle as the default, but make the plain shuffle honest: every song in the list
  plays once before any repeats, even across sessions and devices (remember the "bag" in session sync).
- **Effort / risk.** S. Med (few people check, but the people who do notice care a lot).

### Cut
- **Dislike / hide everywhere:** NaviVibe already has *never recommend*.
- **Discover Weekly quality problems** (too many repeated artists, songs you already know:
  [idea](https://community.spotify.com/t5/Live-Ideas/Improve-discover-weekly-Less-repeat-artists/idi-p/7516193)):
  folded into Part B's rules instead of a separate feature.
- **Dolby Atmos, HiFi, Steam integration:** big on Spotify's board
  ([Spring 2022 review](https://community.spotify.com/t5/Community-Blog/Spring-2022-Ideas-Review/ba-p/5363188)),
  but they don't apply to a self-hosted FLAC library.

---

## Part B: Weekly Exploration with downloads

**Goal.** Each week every user gets a page of new songs picked for them. They hear them first. Songs they keep are
downloaded into the library; everything else disappears on its own. The library grows only with music people
actually want.

### B1. Prior art

| Project | What it does | What to copy | What to avoid |
|---|---|---|---|
| Spotify Discover Weekly / Release Radar | 30 new songs every Monday; new releases from followed artists on Friday | The weekly ritual and fixed day; one short list | Repeated artists and already-known songs (complaints: [less repeat artists](https://community.spotify.com/t5/Live-Ideas/Improve-discover-weekly-Less-repeat-artists/idi-p/7516193), [unusable](https://community.spotify.com/t5/Your-Library/Discover-Weekly-has-become-unusable/m-p/7110287/highlight/true)) |
| [ListenBrainz](https://listenbrainz.org) Weekly Exploration / Weekly Jams | Weekly playlists made by [Troi](https://github.com/metabrainz/troi-recommendation-playground) from your listens; [LB Radio](https://troi.readthedocs.io/en/latest/lb_radio.html) has easy/medium/hard modes (near vs far artists) | The "near and far" mix | Needs MusicBrainz IDs; Tamil coverage is thin (scout #9) |
| [Explo](https://github.com/LumePart/Explo) | Takes ListenBrainz's Weekly Exploration, downloads each song from YouTube or Soulseek, makes a playlist in Navidrome; run it on Tuesdays after LB updates on Monday | The whole loop, and keeping downloads in a separate folder/library ([r/selfhosted](https://redlib.hackliberty.org/r/selfhosted/comments/1g7yz45/explo_spotifys_discover_weekly_for_selfhosted)) | It downloads everything before you hear it; the author says the LB API weekly recommendations are "quite poor" (README) |
| [navidrome-listenbrainz-daily-playlist](https://newreleases.io/project/github/kgarner7/navidrome-listenbrainz-daily-playlist/release/v6.0.0) | Navidrome plugin that makes LB playlists from songs you already own ([guide](https://hn.jakechampion.name/reader/https://chhs1.github.io/blog/2026/01/22/self-hosted-discovery-playlists.html)) | — | No new music at all |
| [Mixarr](https://lemmy.manganiello.tech/post/208182/81203) (Lidarr add-on) | Finds related artists, new releases and charts from Spotify/Deezer/Last.fm/MusicBrainz; **a review queue to approve or dismiss** | Approve-before-download | Works artist by artist (whole discographies), too coarse for a family library |
| [Lidarr](https://wiki.servarr.com/lidarr) | Monitored artists, wanted lists | Wanted list and retries | Whole-album model |
| [slskd](https://www.selfhostyourself.com/services/slskd) / yt-dlp pipelines | Soulseek or YouTube as the download source | — | Legal and quality problems (B3) |

(I could not find a project called "Lidify"; the closest current tool is Mixarr.)

### B2. Where recommendations can come from

| Source | Access | Good for | Limits |
|---|---|---|---|
| **NaviVibe's own history + `catalog.db`** | Already on the server | Seeds (top artists of the last 4 weeks, by full plays), language mix, mood and energy, skips | Can only suggest from what it can find outside the library |
| **Friends and family** (Blend, friend activity) | Already on the server | "Kept by Amma this week": the strongest signal in a family | Only songs already in someone's library or exploration |
| **Deezer public API** | No key ([guidelines](https://developers.deezer.com/guidelines)) | Related artists `/artist/{id}/related`, artist radio `/artist/{id}/radio` ([endpoint list](https://apis.apievangelist.com/store/deezer-artist-api/)), 30 s `preview`, `isrc` and duration on every track ([deezer-python](https://deezer-python.readthedocs.io/en/stable/api_reference/resources/track.html)). Strong Tamil catalogue, and the same IDs the Telegram bot uses | Some artist calls return empty from the server's region (`/artist/{id}/top` did in the Oct 2026 probe), so `related` and `radio` must be checked from subiserver first |
| **Last.fm** `track.getSimilar`, `artist.getSimilar` | Free API key; no published rate limit but "don't make several calls per second" ([method](https://www.last.fm/api/show/track.getSimilar)) | Song-level "people who play X also play Y" | Non-commercial only; commercial use needs an agreement ([ToS](https://www.last.fm/api/tos)) — fine for a family server; cache results |
| **ListenBrainz** | LB Radio API needs a user token ([API](https://listenbrainz.readthedocs.io/en/latest/users/api/core.html), [MetaBrainz blog](https://blog.metabrainz.org/?p=12333)); Fresh Releases ([misc API](https://listenbrainz.readthedocs.io/en/latest/users/api/misc.html)) | English/global music; CC0 data | Needs the user's listens on LB (Navidrome can forward them) and MBIDs; weak for Tamil |
| **MusicBrainz** | 1 request/second ([rate limiting](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting)) | Clean IDs and credits for tagging | Not a recommender |
| **Spotify Web API** | Related Artists, Recommendations and Audio Features are closed to new apps since 27 Nov 2024 ([Spotify blog](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api)); development mode needs a Premium owner and allows 5 users since Feb 2026 ([Spotify blog](https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security)) | Only reading a user's own playlists and likes (Part C) | **Don't build recommendations on it** |
| **Apple iTunes Search API** | No key; `previewUrl` is a 30 s clip ([Apple docs](https://developer.apple.com/library/content/documentation/AudioVideo/Conceptual/iTuneSearchAPI/UnderstandingSearchResults.html)) | Backup previews | No recommendations |

**Recommendation:** NaviVibe's own history for seeds, **Deezer** for candidates and previews (it matches the
fetcher), **Last.fm** for song-level similarity, friends' keeps as a boost, and ListenBrainz only as an optional
extra for users who use it.

### B3. How songs get into the library, stated plainly

| Path | What it is | Legal / ToS position |
|---|---|---|
| **tg-fetcher (already built)**: Telegram bot `@deezload2bot` sends Deezer FLACs | The working path today (`docs/backend/ARCHITECTURE.md`; probe notes in the session notes folder) | The bot downloads from Deezer without a licence. Deezer's terms forbid unauthorised downloads and bypassing its protection ([TorrentFreak on Deezer's terms](https://torrentfreak.com/deezer-tries-to-remove-pirate-downloading-tool-but-under-what-law-190202/), [Deezer takedowns](https://torrentfreak.com/deezer-targets-pirate-apps-maliciously-retrieving-publishing-encryption-keys-210212/)). The copyright in the songs belongs to labels and publishers, so this is copyright infringement in most countries, India included. Weekly Exploration would make this path **automatic and larger**, which raises both the legal exposure and the risk that the Telegram account or bot is banned. |
| yt-dlp from YouTube | What Explo uses by default | YouTube's terms forbid downloads unless YouTube offers a download button ([YouTube ToS](https://m.youtube.com/terms)); the audio is lossy, and music-video uploads often have spoken or video intros |
| Soulseek via slskd | Peer-to-peer; slskd has an API for automation | Shares are mostly unlicensed copies, and Soulseek uploads your own files to others while you download |
| **Buy it**: Bandcamp, Qobuz, 7digital, Amazon MP3, iTunes Store | Licensed files you own | Legal. Slower; not everything is for sale (Tamil film music mostly isn't) |
| **CD rips / existing collections** | Through scout #13 (upload from the browser) | Legal for your own copies in most places |

Practical suggestion: whatever path is used, keep a **per-user weekly cap** (the fetch scheduler already has
`fetch_access` grants) and **download only what the user chose to keep**, never the whole list. That keeps the
volume small (about 5–10 songs per person per week), which suits a family server and the Telegram account. Add
a "Buy" link (Bandcamp/iTunes search) next to Keep, for songs that are on sale.

### B4. Hearing a song before it lands in the library

Two options, both reasonable:

1. **Preview first (recommended for v1).** Play Deezer's 30 s `preview` (or Apple's `previewUrl`) in the
   Exploration page. Nothing is downloaded until the user taps Keep. This is scout #3's preview player, so build it
   once and use it in both places. Previews should be fetched by the server and cached for a short time only;
   don't keep them.
2. **Full songs in a holding library (v2, optional).** Download the top ~10 picks to
   `/DATA/Media/Exploration/` and make it a second Navidrome library. Navidrome 0.58+ supports several libraries
   with per-user access ([docs](https://navidrome.org/docs/usage/features/multi-library/),
   [0.58 notes](https://newreleases.io/project/github/navidrome/navidrome/release/v0.58.0)); Explo users already do
   this ([thread](https://redlib.hackliberty.org/r/selfhosted/comments/1g7yz45/explo_spotifys_discover_weekly_for_selfhosted)).
   Full songs, but it downloads songs nobody keeps.

### B5. Keep and expire rules

- **Keep** (the song moves into the main library): the Keep button, a ♥, adding it to a playlist, or two full
  plays of the full song.
- **Not for me** (gone now): a "Not for me" button, or skipped in the first 30 s twice. This is a strong negative
  signal for the recommender.
- **Expire:** nothing done after **2 weeks** → the pick goes away (the file too, in option 2). Keep a "tombstone"
  so the same song isn't suggested again for 6 months.
- **Never delete a kept song automatically.** If a kept song later goes unplayed for a long time, Back in
  rotation (A2) or Rest (A1) handle it; the library itself only grows.
- A kept song from someone's exploration can go into the **shared** library (everyone sees it) or stay private; see
  the questions at the end.

### B6. Tags and quality

- Kept songs go through the existing tg-fetcher `importer.py` (tags, move, rescan) plus the quality check from
  scout #2.
- Add MusicBrainz IDs when they can be found (beets with the `musicbrainz`, `fetchart` and `lyrics` plugins;
  beets' lyrics plugin can use LRCLIB, [docs](https://docs.beets.io/en/stable/plugins/index.html)). For Tamil
  songs MusicBrainz is often missing, so keep the Deezer metadata (ISRC, album, year) as the base. Use
  MusicBrainz Picard by hand only for fixing mistakes.
- Write ISRC into the file tags: it makes Part C matching and future de-duplication much easier.

### B7. How picks use the shuffle server and Flow

- **Seeds:** the user's top artists and songs of the last 4 weeks by full plays (not just play counts), split by
  language in the same proportions the user listens; Taste and *never recommend* filter everything.
- **Near and far:** about two thirds "near" (Deezer related artists of top seeds, Last.fm similar tracks) and one
  third "far" (artists two steps away, a new language at the rate Flow's language exploration already uses).
  This is LB Radio's easy/medium/hard idea.
- **Rules from the Discover Weekly complaints:** at most 2 songs per artist, nothing the user already owns (reuse
  the library matcher with the version check from `docs/PLAN_NEXT.md` bug 4), nothing tombstoned or snoozed.
- **Extra sources:** followed artists' new releases (scout #1), songs friends kept this week, and the Part C
  wishlist (songs you played a lot on Spotify that aren't in the library). The wishlist will be the best source
  early on.
- **Back into Flow:** a song kept from Exploration is marked as new, and Flow plays it a little more for 2 weeks so
  it gets a fair chance. Every preview listen, Keep and Not-for-me is written to the listening log as an explicit
  signal, which the recommender currently lacks.

### B8. User flow

1. Monday night, after the nightly model run, the server builds each user's Exploration (about 20–25 picks) and
   sends the usual app notification: "Your Weekly Exploration is ready".
2. Home shows an **Exploration** shelf. The page is a simple list (cover, title, artist, a one-line reason such as
   "Like Anirudh · kept by Amma"), with a play button for the preview and two actions: **Keep** and
   **Not for me**. On TV the remote's left/right does Not for me / Keep.
3. "Play all previews" plays through the list hands-free.
4. Keep → a fetch job is queued (shows in the existing fetch activity) → the song appears in the library and in a
   **Kept from Exploration** playlist.
5. Next Monday the old list is replaced; untouched picks expire after 2 weeks.

### B9. Server pieces and app pieces

| Server (shuffle server + tg-fetcher) | App (phone, TV, Windows, web) |
|---|---|
| Weekly job in `scheduler.py`: seeds → candidates → filters → 20–25 picks per user | Exploration shelf on Home and an Exploration page |
| Candidate fetchers for Deezer and Last.fm, with caching and rate limits; server only, so user IPs never reach them | Preview player that does not touch the main queue (shared with scout #3) |
| Preview URL resolver (Deezer links expire, so resolve when asked) | Keep / Not for me buttons; TV remote mapping |
| Keep → fetch job through the existing signed `/fetch` bridge with a weekly cap | "Kept from Exploration" playlist, fetch progress (existing fetch activity) |
| Expiry job, tombstones, signals into the listening log | Settings: list size, languages, "share keeps with family" |
| (v2) holding library and the move into the main library | — |

### B10. Data model sketch (in words)

- **Exploration week:** one row per user per week, with when it was built and a short summary of the seeds used.
- **Pick:** belongs to a week; holds the external IDs (Deezer track ID, ISRC), title, artist, album, duration, the
  source (related artist, similar track, friend, new release, wishlist), the reason text shown to the user, and a
  state that moves from *suggested* → *previewed* → *kept* (with the fetch job ID and later the Navidrome song ID)
  or → *dismissed* or *expired*, with a time for each step.
- **Tombstone:** a normalised artist + title (and ISRC when known) with an "until" date, so dismissed and expired
  songs stay away.
- **Wishlist entry** (shared with Part C): a song the user wants but doesn't own, with where it came from (Spotify
  history, Spotify playlist, manual) and how strongly (play count).

---

## Part C: Migration (bring your Spotify history and more)

### C1. The Spotify exports

| | **Account data** | **Extended streaming history** |
|---|---|---|
| How to ask | Spotify account → Privacy → Download your data; tick "Account data" | Same page; tick "Extended streaming history" (a separate request with its own email confirmation) ([guide](https://takeoutday.org/guides/download-spotify-data)) |
| Wait | Usually a few days (about 5) | **Up to 30 days**, sometimes the next day ([guide](https://freeyourmusic.com/blog/spotify-extended-streaming-history), [Spotify Community](https://community.spotify.com/t5/Other-Podcasts-Partners-etc/Extended-data-been-sent-to-me-Missing-data-from-October-to/td-p/5503310)) |
| History covered | Only about the last year, with few fields (sources disagree on the exact window) | **The whole life of the account** ([Spotify: Understanding your data](https://support.spotify.com/article/understanding-my-data/)) |
| Also inside | Playlists, library (liked songs), search queries, inferences | Only plays |

**Fields in the extended history** (`Streaming_History_Audio_*.json`; older exports used `endsong_*.json`)
([Spotify](https://support.spotify.com/article/understanding-my-data/),
[field notes](https://github.com/Wallerand/spotify-unwrapped),
[Eric Chiang's analysis](https://ericchiang.github.io/post/spotify)):

| Field | Meaning | Use in NaviVibe |
|---|---|---|
| `ts` | When the stream **ended** (UTC) | Time of play; start ≈ `ts − ms_played` |
| `ms_played` | How long it played | Play vs skip; listen ratio once matched to a library song's duration |
| `spotify_track_uri` | `spotify:track:<id>` (null for some rows; episodes use `spotify_episode_uri`) | Grouping; drop episodes and null rows |
| `master_metadata_track_name`, `…_album_artist_name`, `…_album_album_name` | Title, artist, album | Matching |
| `reason_start` | Why it started: `trackdone`, `clickrow`, `fwdbtn`, `autoplay`, … | `clickrow` = chosen on purpose, a stronger "like" |
| `reason_end` | Why it ended: `trackdone`, `endplay`, `fwdbtn`, … | `fwdbtn` early = skip |
| `skipped` | Skipped flag (sometimes null) | Skip signal |
| `shuffle` | Shuffle was on | Down-weight shuffled plays a little |
| `offline`, `offline_timestamp` | Played offline | — |
| `incognito_mode` | Private session | **Drop these rows** (the user chose privacy then) |
| `platform`, `conn_country`, `ip_addr`, `user_agent_decrypted` | Device and network | **Drop at parse time; never store** |

A Spotify Community thread reports thousands of rows with no track metadata in some exports
([thread](https://community.spotify.com/t5/Other-Podcasts-Partners-etc/Extended-Streaming-History-missing-track-metadata/td-p/6269152)),
so the importer must skip them and count them in its report.

### C2. Matching Spotify tracks to the Navidrome library

1. **Exact IDs when we have them.** OpenSubsonic songs can carry `isrc` and `musicBrainzId`
   ([spec](https://opensubsonic.netlify.app/docs/responses/child)), but only if the files are tagged. The
   Spotify history has no ISRC. Getting one means calling Spotify's track API (development mode: the owner needs
   Premium; 5 users max — enough for a family, but fragile
   ([Spotify blog](https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security)))
   or looking the song up on Deezer, whose tracks carry `isrc`. Treat ISRC as a bonus, not the main path.
2. **Normalised artist + title (main path).** Reuse tg-fetcher's `library.py` matcher, which already handles
   Tamil spelling variants (zh→l, ee→i, th→t…), "feat." and version words (remix, live, karaoke, "track by
   track"). Album name breaks ties.
3. **Duration check.** The export has no track length, so look up the Deezer duration for close calls and reject a
   match more than ±10 s off (the same rule as `PLAN_NEXT.md` bug 4).
4. **Ask the user only about the top uncertain ones** (for example the 20 most-played), never thousands.

**Unmatched songs become a Wishlist**, sorted by how much the user played them on Spotify. From the Wishlist the
user can fetch (batch, through the existing playlist-fetch path) or let Weekly Exploration (Part B) offer them a few
at a time. This is the bridge between the two features the user wants.

### C3. What the shuffle server should import

- **Plays** as imported events in each user's listening log, marked `source = spotify` so Stats, Replay and Recap
  can show them or leave them out, and so a re-import never doubles them (key: user + track + `ts`).
- **Per song:** play count, full plays, early skips, `clickrow` share (chosen on purpose), first and last played.
- **Time patterns:** an hour-of-day × weekday table per artist and per language, which is exactly what Smart
  Shuffle's time-of-day mode needs and what new users lack.
- **Seeds for Flow, Smart Shuffle and Back in rotation (A2):** favourites by full plays, eras (what was played most
  in each year), artists that were dropped.
- **Older plays count less:** apply the recommender's time decay so 2019 doesn't outweigh this month.
- **Not into Navidrome's own play counts** by default; keep Spotify history on the shuffle server. (Tools exist that
  write into Navidrome's database, such as [NaviSync](https://github.com/zeroquinc/NaviSync) and
  [navidrome_lastfm_import](https://github.colasdn.workers.dev/Stat1cV01D/navidrome_lastfm_import), but editing
  `navidrome.db` directly is fragile across upgrades.)

### C4. Other things worth migrating

| What | How to get it | Notes |
|---|---|---|
| **Spotify playlists and Liked Songs** | Account data export (playlists + library), or [Exportify](https://www.GitHub.com/watsonbox/exportify) CSV, which includes ISRC and date added | Recreate as Navidrome playlists with the matched songs; the missing songs become a per-playlist Wishlist. NaviVibe can already take public playlist links into the fetcher; Liked Songs have no link, so they need the export |
| **Last.fm scrobbles** | `user.getRecentTracks`, 200 per page, paged with `from` ([method](https://www.last.fm/api/show/user.getRecentTracks)); keep below about 5 requests a second ([archiver notes](https://hexdocs.pm/lastfm_archive/readme.html)) | Just a username; no waiting for an export |
| **ListenBrainz** | LB's own listen export | LB itself has imported Spotify extended history since a 2025 release ([note](https://github-users.yhajoa.workers.dev/r1sim/ListenBrainz-Listening-History-Importer), [GSoC 2025](https://community.metabrainz.org/t/gsoc-2025-importing-listening-history-files/750069)) |
| **YouTube Music** | Google Takeout. Use `watch-history.html`; the JSON can be cut short (6 MB vs 60 MB reported) ([MetaBrainz forum](https://community.metabrainz.org/t/ytm-extractor-import-youtube-music-listens-to-listenbrainz/707619)) | Entries are videos; filter to YouTube Music and strip " - Topic" channel names |
| **Apple Music** | privacy.apple.com → Apple Media Services; up to 7 days; `Apple Music Play Activity.csv` ([guide](https://mystats.music/guides/apple-music-history)) | File names differ between export versions |

Lower priority: Spotify follows (feed scout #1's follow list) and "Your Top Songs 20xx" playlists (good seeds).

### C5. Import pipeline

1. **Request** (user): the app's Import page explains how to ask Spotify for Extended streaming history and that
   it can take up to 30 days.
2. **Upload** (user): drop the zip on the Import page (web and Windows are easiest; phone also fine). It goes
   straight to the shuffle server, behind the normal login, with a size limit and chunked upload because of
   Cloudflare's 100 MB body limit (as noted in scout #13).
3. **Parse** (server, background job): read only `Streaming_History_Audio_*.json`; drop episodes, null-track rows
   and private-session rows; throw away IP, country, platform and user-agent fields straight away.
4. **Group** by track, then **match** (C2) with a cache so repeated tracks are matched once.
5. **Write** imported events and per-song summaries (C3), all under that user only.
6. **Report:** "Imported 48,210 plays of 6,930 songs. 3,100 are in your library. 412 songs you played 10+ times
   are not: see your Wishlist." Offer: "Fetch the top 50" and "Let Weekly Exploration offer them".
7. **Retrain** that user's model in the next nightly run (or right away if cheap).
8. **Delete the uploaded zip** when the job finishes, and keep only the derived rows.
9. **Undo:** "Remove imported Spotify history" deletes every `source = spotify` row for that user.

### C6. Privacy note

- The history file is personal data: years of when and what someone listened to, plus IP addresses and devices.
- It is uploaded only to the user's own subiserver; it is never sent to a third party. Matching lookups (Deezer)
  send only song title and artist, never the user's name or history.
- The raw zip is deleted after import; network and device fields are never stored.
- Imported plays belong to that user only. Friends and Blend see them only through features the user has already
  opted into, and the import page should say so.
- Each user can remove their imported history in one tap.

### C7. Prior art for importers

ListenBrainz now imports Spotify extended history itself (see C4). Community tools such as
[EchoStats](https://spotify-devs.github.io/echostats/user-guide/importing-history/) and
[stats.fm](https://support.spotistats.app/docs/import/spotify-import) take the same zip. Navidrome has no built-in
import ([issue](https://github.com/deluan/navidrome/issues/18)); people use NaviSync or direct database scripts.
NaviVibe's version is different: the history goes to the shuffle server, where it feeds Flow, Smart Shuffle and
the Wishlist, rather than just showing charts.

---

## Recommended next 3

1. **Spotify history import (Part C), M.** It helps every existing feature at once (Flow, Smart Shuffle, Replay,
   Back in rotation), it makes the app useful on day one for a new family member, and its Wishlist is the best
   first source for Weekly Exploration. It needs no new acquisition path.
2. **Weekly Exploration v1, preview first (Part B), M–L.** Build scout #3's preview player once, then the weekly
   job, Keep / Not for me, the 2-week expiry, and Keep → fetch with a weekly cap. Leave the holding library (B4
   option 2) for later.
3. **Rotation pack (A1 + A2, then A8), S each.** Snooze and auto-rest, Back in rotation, then seasonal songs. They
   are all small changes to the same queue builders, everyone would notice them daily, and A2 gets much better
   once the Spotify import is in.

Close fourth: **Who's listening? (A3)**, if the family TV is used by several people every day.

## Questions for the user

1. **Acquisition.** Weekly Exploration would make the Telegram/Deezer path download automatically. Are you
   comfortable with that, or should Keep only add songs to the Wishlist and you fetch by hand? Should a
   "Buy" link be shown when a song is on sale?
2. **Preview or full songs?** Is a 30-second preview enough to decide, or do you want full songs in a holding
   library (more downloads, more storage)?
3. **Shared or private keeps?** When one person keeps a song, should it join the shared library for everyone, or
   stay in their own space until someone else plays it?
4. **Weekly size and cap.** How many picks a week (20? 30?) and how many downloads per person per week?
5. **Languages.** Should Exploration follow each person's current language mix, or push a little toward new ones
   (as Flow's language exploration does)?
6. **Spotify import scope.** Import only plays, or also playlists and Liked Songs? Should imported plays show in
   Replay and Recap, or only feed recommendations?
7. **Who uploads?** Does each family member upload their own Spotify zip, or will you do it for them as admin?
8. **Last.fm / ListenBrainz.** Do any family members have Last.fm or ListenBrainz accounts worth importing?
9. **Seasons.** Which seasons matter in this house (Deepavali, Pongal, Navaratri, Ayyappa season, Christmas)?
10. **TV profiles.** Is the TV shared by several people often enough to build "Who's listening?" soon?
