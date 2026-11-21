# Auto Downloads and "continue where you left off"

Two related features. Both are bookkeeping: a failure in either must never affect playback.

## Continue where you left off

On every queue change (debounced 2 s), on pause, when Android sends the app to the background and when the Windows window closes, the player writes one JSON string, `queueSnapshot_v1`, to the session Hive box (`lib/player/queue_snapshot.dart`).

It holds: the queue in play order with a compact Song snapshot (so it renders offline), the current index, shuffle, repeat, the source name (playlist/album), the unshuffled order (ids), and the account (`server|username`). The queue is cut to the current song and 100 on each side. One key = one atomic write; a torn write leaves the previous snapshot.

The position is **not** in the snapshot. It stays in `kLastPositionMs` next to `kCurrentTrackId` and is applied only to its own song (`resumeSeekMs`, unchanged): another song starts at 0.

At launch the player loads the snapshot **paused**: mini player and queue show, Play continues at the saved position. Nothing is played or scrobbled while loading.

| Situation | Result |
|---|---|
| Snapshot unreadable, wrong version, any bad entry | Deleted, start clean |
| Different account | Not restored (kept until the new account's queue replaces it) |
| Another device holds the session (`SyncMode.passive`) | Not restored; the remote session is shown instead |
| The listener started something before the restore finished | Not replaced |
| Song removed from the library | Dropped, only after a full library sync has finished (the mirror also holds songs added one at a time while playing, so before that it cannot say what is missing). If the current song is gone, the next one that is left takes its place, from 0:00. Downloaded and local songs are always kept |
| Stale index | Pulled into the queue |

## Auto Downloads

Settings → Downloads & Storage → Auto Downloads. Off by default (it uses storage and data). It reuses `OfflineService` through the downloads provider; there is no second downloader. User downloads and auto downloads share a folder, but auto downloads are recorded in a ledger (`auto_download_ledger_v1`) and **only ledger songs are ever evicted**.

### Which songs
A *completed play* is not skipped before half and lasted 20 s or more (from `play_events`). A song becomes a candidate when:

1. it has **3 completed plays in 14 days**, or
2. **1 play in 14 days and it is liked**, or
3. it is in the **top played**: the 20 most played songs of the last 30 days, with at least 4 plays.

Skipped: songs already downloaded, local-library songs, songs already in the ledger, and songs blocked by *Remove* (30 days) or *Not This* (forever).

### Ranking and eviction score
`score = 10 × plays in 14 days + (14 − days since last play, min 0) + 15 if liked + 8 if top played`.
Highest score downloads first. The same score decides what goes first when room is needed: lowest score, then oldest download. A song is never evicted for one that scores the same or less, so the budget does not churn.

### When it runs
A timer checks every 10 minutes (and once after turning the setting on); it downloads at most 4 songs per pass, **one at a time**, and re-checks the device before every file. It does not run when:

- the setting is off, or the device is offline, or the network type is unknown;
- **on mobile data while Wi-Fi only is on** (default on);
- not charging while *Only While Charging* is on (default on). A desktop that cannot report a battery counts as plugged in; a phone that cannot counts as not charging;
- battery is 20 % or lower and not charging;
- the player is loading or buffering.

### Storage budget
`min(chosen limit, 10 % of the free space available to auto downloads)`. The limit is 512 MB, 1, **2**, 5 or 10 GB. Free space includes what auto downloads already hold, so the budget does not shrink as it fills. Lowering the limit trims the least valuable songs at the next pass. If the platform cannot report free space, only the chosen limit applies.

### What the listener sees
*What It Downloaded* lists the ledger. **Remove** deletes the file and skips the song for 30 days; **Not This** deletes it and never picks it again. A song the listener deletes by hand in Downloads is forgotten by the ledger and skipped for 30 days.

Code: `lib/features/auto_download/` (`logic/auto_download_policy.dart` is the pure rules; `auto_download_service.dart` sequences them; `auto_download_providers.dart` wires settings, history, network and battery).
