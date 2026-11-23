# channels-primary-v1

The wishlist (Exportify) fetch asks the public Telegram channels (`retroaudios`, `HiResTrackscom`) first and the music bot only for what no channel has. Needs channel-fallback-v1 and request-race-v1 (it reuses `channel_fallback` scoring and `human_check`). Built on the live code read on 23 Nov 2026.

## What it does
`tgfetch/channels_first.py`, hooked into `youtube_batch.run` for batches whose link starts with `exportify:` (YouTube lists and the app's own requests are untouched).

| Setting (`.env`) | Default | Meaning |
|---|---|---|
| `FETCH_PRIMARY` | `channels` | `channels` = channels first, bot for the rest; `race` = both at once per song; `bot` = the old behaviour |
| `FETCH_BOT_FALLBACK` | `1` | `0` = a song no channel has is never asked of the bot; it ends `failed` with the reason |
| `CHANNEL_SEARCH_GAP_S` | `6` | one channel search per this many seconds, all songs together |
| `CHANNEL_MAX_MB` | `100` | a post bigger than this is not taken (hi-res posts reach 140 MB) |
| `CHANNEL_MIN_FREE_GB` | `25` | hard stop: below this nothing is downloaded, the song waits (`waiting for disk space`) |
| `CHANNEL_SKIP_EDITS` | `1` | sped-up / slowed / TikTok edits go straight to the bot (0 of 24 such songs were ever found on the channels) |
| `EXPORTIFY_BATCH_SIZE` | `25` | songs per batch (recommended 100 for channels) |
| `EXPORTIFY_GB_PER_HOUR` | `0.51` | disk estimate per hour of music (recommended 0.77 for channels) |

- **Acceptance is `channel_fallback`'s, unchanged**: FLAC, title match 90+, an artist word in caption / file name / performer, remix / live / karaoke only when the song is one. Plus the size cap above.
- **Per song**: owned check first (as before), then channel by channel: the specific query `title artistword`, then the title alone; first acceptable post wins. It is fetched by id and taken through `Worker._take` (FLAC gate, duplicate checks, download) and `import_job`; `jobs.source` = `channel:<name>`.
- **Cache + resume**: every (channel, query) answer is kept in `fetch.db` table `channel_cache` (a hit 30 days, an empty answer 3 days) as the few fields the scoring reads. A restart, a retry, "Try them again" or the same title twice costs no Telegram request. Batches, jobs and states were already resumable; nothing new to resume.
- **Pacing**: a global pacer, one search per gap. FloodWait: `DeezloadSource._call` already waits short ones; a long one (over 300 s) is rested out here (up to 3 times).
- **No channel has it**: the channels are marked tried in `channel_tries` (so the fallback sweeper does not search them again), then the bot is asked, unless `FETCH_BOT_FALLBACK=0` or the bot is waiting for the human check. A skipped song ends `failed`: "not on the Telegram channels (…)", shown in the wishlist like any song that didn't come in; "Try Them Again" asks again later. Songs stay one state each (`queued` → `downloaded` / `failed`).
- **Human check**: while the flag is set the bot is skipped. One request per `BOT_CHECK_PROBE_S` (300 s) still goes through: that is how the flag clears after the owner taps verify (nobody else probes during a wishlist run). If the check appears mid-song, that song fails with the reason instead of holding the batch for 30 minutes. The check is never solved or bypassed.
- **Cancel**: checked before every channel search; the batch's own cancel/retry behave as before.
- **Disk**: the plan's disk guard (floor, `paused_disk`, trimming) is unchanged and independent of the fetch path (tests cover pause and resume); the new `EXPORTIFY_GB_PER_HOUR` makes its estimate match channel files, and `CHANNEL_MIN_FREE_GB` is a last-resort stop.

## Measured (what the server's own record shows; no new Telegram session was used)
`docs/failed-songs-2026-11-16.csv` was not on disk (not in the main checkout or anywhere searched), and a second Telegram login would risk the running service's session, so this is the live data of the channel-fallback sweeper instead: **191 failed jobs = 154 different songs** searched 22 Nov 03:26–05:40 (`channel_tries`, journal).
- Found: **38 of 154 (25 %)**; of the 130 that are not edits **38 (29 %)**; of the 24 edits (sped up, remix, TikTok, female vocals, duet, version) **0**. Per channel: `retroaudios` 30 (79 %), `HiResTrackscom` 8 (21 %). No FloodWait in 3 days of this pace.
- Time: a miss costs a median **24.4 s** (181 consecutive gaps: 4 searches × 6 s); a hit about **45 s** (search, download, tag, scan; fitted over 8 cycles). So `t = (1−p)·24 s + p·45 s` per song.
- Common misses: sped-up / remix / TikTok / "Female Vocals" / "Duet" versions (all 24); old Tamil / Telugu film songs credited to several singers (Ilaiyaraaja era); spelling differences (transliteration). The last is a reading of the list, not measured. These were songs the bot had already failed on, so a normal wishlist should hit more; that rate is unmeasured until the first batch runs.
- File size: channel files average **40 MB** (retroaudios 41.8 MB, HiRes 36.8 MB, max 143 MB; n = 36) against 26.8 MB for the bot's.

## Throughput for ~4,000 songs (projection from the numbers above)
- At 25 % hits: about 30 s a song, 33 h; at 50 %: 35 s, 39 h. Plus the bot for the misses (about 20 s each, if it is not waiting for the check).
- Exportify queues one batch at a time and its timer ticks every 10 minutes, so batch size matters: 25 songs ≈ 12 min of work + up to 10 min idle (about 68 songs/h); 100 songs ≈ 50 min + 10 (about 100 songs/h).
- Recommended for a channels run (set in the app, Wishlist settings): **batch size 100** (`.env`), **songs a night 800**, **only at night off** (the bot's time constraint is gone; the only load is one search per 6 s), keep the 6 s gap. 800 songs ≈ 7 h, so ~3 days for 2,400 songs. Do not lower the gap without watching for FloodWait: it has none at 6 s.

## Disk (read-only on the server, 23 Nov)
Free: **131 GB** on the volume holding `/DATA/Media/Music` (468 GB, 71 % used); floor default 40 GB → **about 90 GB** to use. FLAC from the channels is 40 MB a song, so about **2,250 songs fit above the floor**; lowering the floor to 20 GB gives about 2,750. The doc's cut-off figures (17 / 38 / 58 / 77 GB for 50+ / 40+ / 30+ / 20+) were for the bot's 26–35 MB files; channel files are 1.5× bigger: **26 / 57 / 87 / 116 GB**. With the default floor **choose popularity 40+** (57 GB, about 33 GB spare); 30+ (87 GB) would just reach the floor and pause. The screen's "These N songs need about X GB" is right once `EXPORTIFY_GB_PER_HOUR=0.77` is set: pick the cut-off where X is under about 80. The plan pauses itself at the floor ("Paused: disk is low") and carries on when space returns.

## Not verified
Hit rate on a fresh wishlist (needs the first batch); cache and FloodWait behaviour at the full 4,000 (tests simulate both); the app strings for the new failure reasons were not checked on a phone.

## Install
`bash install.sh --check` (scratch tests only), then `bash install.sh`. Add the `.env` lines it prints, restart. Tests: `tests/test_channels_primary_v1.py` (22): channel hit never touches the bot, query order, same acceptance, size cap, miss → bot, fallback off, human check skip + probe, check mid-song, channel errors, other lists untouched, race, pacing, cache across a restart, flood wait, cancel, low disk, a whole wishlist batch, disk guard pause/resume, env settings, edit skip.
