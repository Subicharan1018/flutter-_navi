# fetch-waits-v1

- A song the channels lack no longer ends `failed` while the music bot waits for a human check: it waits (`waiting`, "verify it in Telegram and this song starts by itself"). Songs the channels have still download meanwhile.
- `bot_verify.py`: a normal message or edit from the bot while flagged clears the flag, and clearing wakes the batches parked by "the bot did not answer" at once (not on the next 30-minute retry).
- A batch waiting for the verify gives up after a week (`HUMAN_CHECK_GIVE_UP_S`), not a day.
- Channel search names: `Laali Laali - Tamil` / `... - Ao Vivo` / `... | Vol.1` are searched as the plain name; the matcher still decides what is accepted.

Needs channels-primary-v1 and request-race-v1. `bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`.
