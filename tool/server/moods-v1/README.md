# moods-v1: mood labels the app can trust

For the shuffle server (`/opt/shuffle-server/navivibe`, systemd `navivibe`) on subiserver. Fixes
TODO bug #4, "Moods are wrong for most songs", on the server side. Built on the live code read on
16 Nov 2026 (read-only). Not installed: the user runs `install.sh` and the sudo line.

## What it changes

| # | Problem | Fix | Where |
|---|---------|-----|-------|
| 1 | The app's Smart Playlists guessed moods from genre words because `/catalog/songs` didn't send the server's labels. | Each song in `/catalog/songs` has `"moods": ["sad", "romantic"]` (the LLM labels, most fitting first, at most 2). A song with no label has no `moods` key. All other fields are unchanged. The ETag also changes when `mood_tags.json` changes. | `catalog/api.py` |
| 2 | The labeller saw only the first 220 characters of the lyrics (often a hum or a hook). | It now gets the first verse plus the chorus: the stanza marked `[Chorus]`/`[Hook]`/`Pallavi`, or else the most repeated stanza, or else the repeated lines. LRC timestamps are removed. If both are short, the next stanzas fill up to about 600 characters, and the cap is 800. Pacing goes from 30 s to 75 s per batch because a batch is now about 8K tokens (Groq free tier: about 8K tokens a minute). | `catalog/mood_lyrics.py`; `catalog/mood_tags.py` |
| 3 | The prompt is written for Tamil film songs, but 645 songs are English. | English songs are batched together and get their own prompt (`SYSTEM_EN`). A mixed batch keeps the general prompt. The same applies in `mood_audit --relabel`. | `mood_lyrics.py`; `mood_tags.py`; `mood_audit.py` |
| 4 | Labels could never be corrected. | **"Not this mood"** per listener, stored on the server (`{log dir}/mood_overrides/<user>.json`, like `flow_prefs`). It beats the LLM label for that listener in Flow mood chips (including the sound-based `gym` chip), Discover / Weekly-mix taste, and the app's Smart Playlists. It is never shared with other listeners. | `mood_overrides.py`; `discover.py` `user_context`; `flow.py` `next_batch`; `server.py` routes |
| 5 | About 100 labels contradict the evidence (`mood_audit`). | `relabel_moods.sh` asks the labeller again about the flagged songs, with the longer lyrics. It does a dry run first and asks before writing (`mood_audit` backs up `mood_tags.json`). **Not run by `install.sh`.** | `relabel_moods.sh` |

## App contract

* `GET /catalog/songs`: per song, optional `moods: [string]` (`sad`, `romantic`, `happy`,
  `energetic`, `calm`, `devotional`, `angry`). A missing key means no label.
* `GET /moods/overrides` → `{"overrides": {"<song_id>": ["sad"]}}`: the caller's marks.
* `POST /moods/not-this` with body `{"song_id": "…", "mood": "sad"}` → `{"ok": true, "song_id",
  "not": ["sad"], "moods": [labels left for the caller]}`. Any Flow mood is allowed, including
  `gym`. Unknown mood or bad id → 400. Login is required (401).
* `DELETE /moods/not-this` with the same fields (body or query) takes the mark back (Undo).

## Install (on the server, as subi)

```bash
bash install.sh                 # tests (scratch before/after), backup, patch, live tests, auto-restore
sudo systemctl restart navivibe
bash relabel_moods.sh           # optional, afterwards: dry run, then asks before writing
```

`install.sh` runs the whole `navivibe/tests` suite on a scratch copy, both before and after the
patch. A test that already failed before doesn't block the install; any new failure does, and so
does any failure in `test_moods_v1.py`. After patching, it runs the suite again on the live tree
and restores the backup if a new failure shows up. Re-running it is safe: the patches are exact
text matches and skip what is already patched.

Files: new `mood_overrides.py`, `catalog/mood_lyrics.py`, `tests/test_moods_v1.py`. Patched
`catalog/mood_tags.py`, `catalog/mood_audit.py`, `catalog/api.py`, `discover.py`, `flow.py`,
`server.py`, `tests/conftest.py` (the tests use a temporary override folder).
