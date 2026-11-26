# import-limit-v1

`exportify.prune_old` keeps at most `MAX_IMPORTS` imports per user and deletes the oldest (with their songs) each time the user imports. The limit is now `EXPORTIFY_MAX_IMPORTS` (default 20, unchanged). Needed to load 62 playlists for one user without the next import pruning them.

Set `EXPORTIFY_MAX_IMPORTS=200` in `.env`, `bash install.sh --check`, `bash install.sh`, then `sudo systemctl restart tg-fetcher`.
