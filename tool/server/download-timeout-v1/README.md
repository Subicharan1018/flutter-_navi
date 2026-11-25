# download-timeout-v1

A channel download is cancelled after `CHANNEL_DOWNLOAD_TIMEOUT_S` (default 5 minutes, or 60 s + 5 s per MB for big files). The job goes back to `waiting` and the song falls through to the bot / next run. Fixes the 25 Nov freeze: the worker sat on one DC5 connection for six hours with every health check green.

Needs channels-primary-v1. `bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`.
