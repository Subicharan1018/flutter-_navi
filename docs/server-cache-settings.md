# Navidrome cache sizes (owner-run, no app change)

Why: Navidrome keeps resized cover art and transcoded audio in two on-disk
caches. Both default to 100 MB ([options](https://www.navidrome.org/docs/usage/configuration/options/)).
The app asks for covers at several sizes (128/256/512/1024 from lists, plus 64,
300, 600 and 1080 from the player and share), so 100 MB fills quickly and covers
get re-resized. A larger image cache means fewer resizes and faster cover loads;
a larger transcoding cache helps only if clients are served transcoded audio
(fast start, or a max bit rate set in the app).

Suggested values (the server disk is not measured here: check free space first,
`df -h` on the Navidrome data volume; caches are capped, they never grow past
the setting):

| Setting | Default | Suggested | Env var |
|---|---|---|---|
| `ImageCacheSize` | `100MB` | `1GB` (500MB if disk is tight) | `ND_IMAGECACHESIZE` |
| `TranscodingCacheSize` | `100MB` | `500MB` | `ND_TRANSCODINGCACHESIZE` |

Apply one way, then restart Navidrome:

1. **`navidrome.toml`** (in the data folder):
   ```toml
   ImageCacheSize = "1GB"
   TranscodingCacheSize = "500MB"
   ```
2. **Docker / compose environment** instead:
   ```yaml
   environment:
     ND_IMAGECACHESIZE: "1GB"
     ND_TRANSCODINGCACHESIZE: "500MB"
   ```

Restart (pick what matches the install):

```bash
docker compose up -d --force-recreate navidrome
```

```bash
sudo systemctl restart navidrome
```

Check: the startup log prints the loaded configuration (`docker logs navidrome | grep -i cache`),
and the cache folder (`CacheFolder`, default `<DataFolder>/cache`, subfolders
`images` and `transcoding`) fills over a few days of use. A value of `0`
disables a cache, so do not set that.

Nothing in the repo reads these settings; the live values were not checked.
