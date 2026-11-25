# match-relaxed-v1

Of 258 songs that failed as "not found" on 24-25 Nov 2026, the channels had no FLAC post for 163, but a post with the same title for ~90; the artist rule alone rejected 59 of those (Spotify names singers, the post names the composer / "Various Artists" / a different spelling / nobody). The strict rule still runs first. When it finds nothing in a channel, a post is also accepted if its title is >= 95 similar, it is not a remix/live/cover/karaoke cut, and either its length is within 3 s of the song's or it names no artist (title of two or more words). A same-title post of a different length is still refused.

`bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`. Also set `CHANNEL_MAX_MB=160` in `.env` (hi-res posts of 105-131 MB were refused at 100).
