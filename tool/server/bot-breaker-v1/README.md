# bot-breaker-v1

A silent music bot cost every song about three minutes and a pasted playlist twenty. Now a bot request gets 2 tries of 20 s (`BOT_ATTEMPTS`, `CALL_TIMEOUT_S`); `BOT_FAILS_BEFORE_REST` (3) unanswered requests in a row rest the bot for `BOT_REST_S` (3600 s): every bot call in that hour fails at once with "didn't answer ... will retry", so songs wait (and the batch retries them) while the channel searches carry on. When the hour is up the bot is tried again and one answer closes the breaker. A pasted link waits `LINK_FIRST_FILE_S` (300) for its first file and `LINK_IDLE_S` (240) of silence.

Needs bot-pace-v1. `bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`.
