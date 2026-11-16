# moods-v2: mood labels you can trust, and a mood editor

For the shuffle server (`/opt/shuffle-server/navivibe`, systemd `navivibe`) on subiserver. It needs
moods-v1, which has been installed since 16 Nov 2026 10:11 UTC. Built on the live code, read
read-only on 16 Nov 2026. Not installed: the user runs `install.sh` and the sudo line.

## How wrong were the labels? (16 Nov 2026, after the moods-v1 relabel)

**The sample.** 60 songs, read-only: 8 per first label plus 4 unlabelled, seed 7. I judged 54 of
them by reading the lyrics and knowing the songs. They are in
`tests/fixtures/mood_reference.json`, each with the first moods a listener would accept.

**Scores.**

| | right | wrong | no label | precision |
|---|---|---|---|---|
| labeller's labels | 45 / 54 (83 %) | 9 | 0 | 83 % |
| labels in use (moods-v2 rules) | 49 / 54 (91 %) | 3 | 2 | 94 % |

**Where the labels went wrong (the 9 misses).**
- **"sad" over-assigned** (4 of 8 "sad" were wrong): upbeat love songs. "Stole My Heart",
  "Sevatha Pulla", "Oru Naalum" and "Kadhalaada" sound happy (valence about 0.6–0.8, the classifier
  hears happy), and their lyrics have no loss or separation words.
- **A title word or a short prayer read as the mood.**
  - "Pudikale Pudikudhu" (*I don't like it*, in a playful love duet) was labelled angry.
  - "Tujh Mein Rab Dikhta Hai" (*I see God in you*, said to a lover) was labelled devotional.
  - "Asalayavale" (a wedding song that opens with a prayer) was labelled devotional.
- **"calm" on fast, loud songs**: "Ponni Nadhi" and "Goindhammavaala".
- No lyrics: 574 of 2,419 songs (24 %) have none, so their label comes from the title, the film
  and the sound only.

**What the rules fix, and what they don't.** The rules fix 6 of the 9: 4 get a right first label,
and 2 lose their label. Still wrong:
- "Goindhammavaala" (calm): it sounds calm;
- "Asalayavale" (devotional): there is real prayer text in the lyrics;
- "Kadhalaada" (sad): it also sounds sad.

No correct first label in the sample was dropped.

**Held-out check.** The rules were tuned on this sample, so I also looked at what they do across
the whole library: 91 of 2,409 labelled songs lose a mood, and 17 end up with no label.

I judged 37 of them myself (40 random ones, minus 3 from the reference set):
- An "energetic: too quiet" rule was wrong 4 times out of 4 (Without Me, Oorum Blood, Ei Suzhali,
  Superman: the energy number misreads rap and folk), so it was removed.
- In the rest, about 3 drops were wrong ("Anxiety", "The One That Got Away", "Pogadhey" lost a
  right "sad"), 3 were unclear, and the others were right: roughly 9 in 10 drops are correct.
- The "sad" rule is now stricter for songs with no lyrics.

**The LLM changes.** The prompt rules and the confidence below only take effect on songs the
labeller labels again (new songs, or `relabel_moods.sh`). Their effect is not in the numbers above
because I can't call the labeller from here. After a relabel, run `mood_eval` to see it.

## What it changes

| # | What | Where |
|---|------|-------|
| 1 | **Evidence rules.** Rules over the labeller's labels drop a mood the sound and the lyrics plainly rule out (each rule needs both to agree):<br>• **sad**: sounds happy (valence ≥ 0.6, the classifier's "happy" at least 0.2 above its "sad"; 0.3 with no lyrics) or loud and bright, and the lyrics have fewer than 2 sadness words;<br>• **angry**: the classifier hears little aggression (below 0.25), valence ≥ 0.6, and no anger words;<br>• **calm**: energy ≥ 0.75, or fast and loud;<br>• **happy**: sounds clearly sad;<br>• **devotional**: only the title sounds devotional while the lyrics exist and say nothing devotional.<br>Thin or conflicting evidence means **no label rather than a wrong one**. The labeller's own file (`mood_tags.json`) is never changed. `mood_tags.load()` returns the labels in use, and `load_raw()` returns the labeller's. | `catalog/mood_quality.py`; `mood_tags.load` |
| 2 | **Confidence.** The labeller now also returns `confidence` (0–1) and `basis` (lyrics / knowledge / sound), kept in `mood_meta.json`. A label below 0.5 is not used. The prompt gains the sample's lessons: no mood from one title word; "sad" only for loss, separation, pain or longing; "devotional" only for prayer or praise. | `mood_tags.py` (`TOOL`, `SYSTEM`), `mood_lyrics.SYSTEM_EN`, `mood_audit.py` |
| 3 | **Admin labels.** An admin's labels (`mood_admin.json`, with `by` and `at`) are every listener's labels and beat both the labeller and the rules. An empty list means "no mood" on purpose. `label_missing` and `mood_audit --relabel/--apply` skip these songs, so a relabel never overwrites them. Listeners' "Not this mood" marks (moods-v1) still apply on top. `/catalog/songs` and its ETag follow all of this. An admin's `gym` label puts the song in the gym chip. | `mood_quality.py`; `mood_tags.py`; `mood_audit.py`; `catalog/api.py` |
| 4 | **The mood editor** at `/moods/editor`. Plain HTML + JS, no build step, monochrome (DESIGN.md), works on a phone.<br>• **Sign-in** goes through Navidrome's own `/auth/login` (the web app's JWT). The page keeps only the token, in `sessionStorage`, never the password.<br>• **The list**: every song with its moods, 50 at a time with infinite scroll. Search by title, artist or film. Filters: a mood, No mood, Flagged (the rules dropped something, or the labeller was unsure), Set by admin. Covers come from Navidrome.<br>• **The selector**: 7 moods + gym, at most 2, in order. Changes show at once, with Undo and clear errors.<br>• **Admins** set moods for everyone. Others can only mark moods "Not this mood" for themselves.<br>• **Page policy**: the API's `default-src 'none'` policy is replaced on `/moods/editor*` only: `script-src 'self'`, no inline script, no framing. | `mood_editor.py`, `mood_editor_static/*`; `server.py` |
| 5 | `relabel_moods.sh` (kept, updated for v2) and `python -m navivibe.catalog.mood_eval` (accuracy on the reference sample, read-only). Neither runs from `install.sh`. | |

The editor is reachable through the tunnel: `shuffle.subimusic.me` goes straight to port 5500
(`/etc/cloudflared/config.yml`). The tunnel has no path rules, and the editor isn't under
`/admin`. I could not see any Cloudflare dashboard rules (WAF or Access); if `/moods/editor` gives
403 from outside, check those.

## API (for the app and the page)

* `GET /moods/me` → `{username, is_admin}`.
* `GET /moods/songs?offset&limit&q&mood&filter` → `{items, total, offset, next_offset, is_admin,
  cover_base}`.
  - `limit` is at most 100, and `mood` is a mood or `none`.
  - `filter` is `flagged` or `admin`.
  - Each item: `id, title, artist, album, film, language, moods, llm, source (admin|llm|none),
    by, at, flags, not`.
* `PUT /moods/songs/<id>` `{moods}` (admins only; 400 for bad moods, 403 for non-admins, 404 for
  an unknown song).
* `DELETE /moods/songs/<id>` (admins only) goes back to the labeller's moods.
* `POST /moods/editor/login` `{username, password}` → `{token, username, is_admin}`.

## Install (on the server, as subi)

```bash
bash install.sh                 # tests (scratch before/after), backup, patch, live tests, auto-restore
sudo systemctl restart navivibe
cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m navivibe.catalog.mood_eval   # optional: the scores
bash relabel_moods.sh           # optional: dry run first, then asks before writing
```

Admins are `NAVIVIBE_ADMIN_USERS` (now `admin`), set in the systemd unit or in `.env`.

Files:
- **New**: `catalog/mood_quality.py`, `catalog/mood_eval.py`, `mood_editor.py`,
  `mood_editor_static/{index.html,app.js,app.css}`, `tests/test_moods_v2.py`,
  `tests/fixtures/mood_reference.json`.
- **Patched** (exact-match, idempotent, `patch_moods_v2.py`): `catalog/mood_tags.py`,
  `catalog/mood_lyrics.py`, `catalog/mood_audit.py`, `catalog/api.py`, `server.py`,
  `tests/conftest.py`.
