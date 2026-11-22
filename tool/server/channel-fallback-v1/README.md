# channel-fallback-v1

Failed songs are looked for in public Telegram channels (default `retroaudios`, `HiResTrackscom`) instead of the music bot, which now sometimes asks "Verify you are not a robot".

- A song is accepted only when the post is a FLAC, its title matches (90+), and an artist word appears in its caption, file name or performer. Remix, live, karaoke and similar cuts are skipped unless the song itself is one.
- It takes the normal route (`Worker._take` then `import_job`): FLAC gate, duplicate checks, tagging, library scan.
- 20 songs per cycle, one search every 6 s, FloodWait waited out, each song tried once and again after 7 days.
- `CHANNEL_FALLBACK=0` turns it off; `CHANNEL_FALLBACK_CHANNELS` changes the list.
- Install: `bash install.sh` (or `--check` for the scratch tests only). Restart is printed after "Done".
