# telegram-resilience-v1

- `tgfetch/watchdog.py`: if the Telegram connection stays down for 5 minutes (WATCHDOG_PATIENCE_S) the service stops so systemd restarts it, and the owner gets an alert once. Fixes the 24 Nov stall: eleven hours "running" with no Telegram.
- `channel_fallback.resolve()`: a private channel listed by numeric id is found even right after a fresh login (loads the dialogs once).

Needs channel-ids-v1. `bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`.
