# blocked-memory-v1

A song the author withdrew is remembered by song, not only by job.

**Problem (22 and 23 Nov 2026):** Deezer track 2546118092 was refused by the bot twice ("The song's author has
prohibited listening to it in most countries"), once per night, because the block lived on the job and the next
night's request was a new candidate with a new job id.

**Change:** the first refusal is stored in `blocked_tracks` (key = normalised title + first artist, plus the
Deezer track id for reference). `Worker.run_job` and the playlist/wishlist path (`youtube_batch.fetch_one`) check it
before asking the bot or a channel; a known song ends `blocked` at once with the stored reason.

Every read and write swallows its own errors: a failed record never fails a download.

- tg-fetcher only. New: `tgfetch/blocked_memory.py`, `tests/test_blocked_memory_v1.py`. Patched: `worker.py`,
  `youtube_batch.py`.
- Install as subi from this folder: `bash install.sh --check`, then `bash install.sh`; then restart
  (`sudo systemctl restart tg-fetcher`).
- To un-block a song that is available again: `sqlite3 /opt/tg-fetcher/data/fetch.db "delete from blocked_tracks where key like 'ta:%name%'"`.
