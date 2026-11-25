# channel-ids-v1

A channel in `CHANNEL_FALLBACK_CHANNELS` may be a numeric id (private channels have no @name):
`CHANNEL_FALLBACK_CHANNELS=-1001197115414,FLACsongs,retroaudios`. Telethon needs an int for an id, so `channel_fallback.ref()`
turns a numeric string into one; the four `get_entity` calls in channel_fallback.py and channels_first.py go through it.

Needs channels-primary-v1. `bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`.
