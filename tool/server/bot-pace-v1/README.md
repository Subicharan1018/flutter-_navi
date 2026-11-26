# bot-pace-v1

The music bot was asked its inline searches back to back: three queries per song about a second apart, song after song, and it answered with empty lists ([0, 0, 0] in the new not-found log lines, 25 Nov 2026). Now every bot search waits `BOT_SEARCH_GAP_S` (default 4 s) after the previous one, and a song is tried with `BOT_QUERIES_PER_SONG` (default 2) spellings. Set `BOT_SEARCH_GAP_S=0` for the old behaviour.

`bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`.
