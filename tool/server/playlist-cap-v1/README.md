# playlist-cap-v1

Playlists were cut at 300 songs in three places (`links.py`, `sources/deezload.py`, `youtube_list.py`). The cap is now `MAX_PLAYLIST_TRACKS` (default 3000), so Deezer and YouTube playlists read in full.

**Not fixed here:** a Spotify playlist link is read from Spotify's public embed page, which lists only the first 100 songs (the batch of Susan's 350-song playlist had 99). The bot then delivers every song, but files that match no listed song are skipped. For a Spotify playlist over 100 songs, use an Exportify CSV (Settings, Exportify import), which has no such limit.

Run: `bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`.
