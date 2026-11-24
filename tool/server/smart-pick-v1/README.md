# smart-pick-v1

Smart Shuffle from a playlist: **the model chooses the songs and the order, familiar songs come first, cold songs last, and a cold song never opens.** Built on the live shuffle server after `play-events-v2` and `hybrid-shadow-v1`. Needs the matching app build (the app change is on the same branch); an old app keeps working unchanged.

## What was wrong (confirmed on the live code, 2026-11-23 evidence)

1. The app picked the first song at random (`Random().nextInt`) and took the first 16 of a random shuffle of the playlist as `candidates`. The server only ordered a random sample (`candidates (16) -> smart_candidates: 16 songs`); it could not choose, so cold songs and low scores (`Hare Rama Hare Krishna` -1.87) got in.
2. Nothing enforced familiar-first. In v3 `recommend()` an explore slot (position 5) is deliberately a never-played song, and songs are drawn by temperature sampling, so a batch is not sorted by score.
3. The server's own playlist branch (`source=playlist`) was never used by the app (no playlist id was sent) and re-read Navidrome twice per request.

## What it does

`/next` for a candidate list (`smart_candidates`) and for a playlist id (`smart_playlist`) now goes through `navivibe/smart_pick.py`:

1. **Opener** (the session has no kept song yet): the v3 *opener* model scores the **familiar** candidates and one is drawn from the top (v3's own opener sampling, temperature `V3_TEMPERATURE_START`, restricted to familiar songs).
2. **The rest**: v3 (+ the listener-memory order, `AI_ORDER=memory` as today) picks and orders songs among the **familiar** candidates by its own scores, chained from the opener; then the **cold** candidates. One cold song closes a batch that is otherwise familiar, so new songs are still heard; if there are not enough familiar songs, cold ones fill the end.
3. Guardrails: no cold opener; at most one cold song in positions 2-7 (unless fewer than six familiar songs exist); artist and film not twice in a row where avoidable; no song twice; the response always has up to `count` songs.
4. **Nobody familiar** (new account, or a playlist of unheard songs): exactly the queue v3 gave before, nothing empty. **Any error**: same. `SMART_PICK=off`: same, everywhere.

**Familiar** = the listener has played the song at least `SMART_PICK_COLD_PLAYS` (3) times **and** last played it at most `SMART_PICK_STALE_DAYS` (30) days ago. From the owner's log (8,525 plays, 2026-04-26 to 11-23), skip rate by the song's earlier plays in session slots 1-7: 0 plays 29.9%, 1 play 25.1%, 2 plays 15.5%, 3-5 plays 15-17%, 10-19 plays 12.6%, 20+ plays 8.1%; the drop is at 3. Recency: a song with 3+ plays whose previous play was within 30 days is skipped 12.7%, 30-60 days 31%, over 60 days 44%. With this rule: familiar songs in slots 1-7 are skipped 10.9%, cold 25.1% (slot 1: 10.4% vs 26.9%).

The model is **not** changed: v3 scores, the hybrid stays in shadow (`HYBRID_ORDER` untouched), `AI_ORDER` untouched.

### Three ways to send the pool (all accepted; an old app's titles keep working)

| field | meaning |
|---|---|
| `candidates` | titles (old apps). Matched by title (+composer) as before |
| `candidate_ids` | song ids (the Navidrome ids the catalog uses): exact, no title matching. Added to `candidates` if both come |
| `playlist_id` (+ `exclude_ids`) | the server reads the playlist itself (Navidrome, cached `SMART_PICK_PLAYLIST_TTL` = 30 s, also the playlist list). `exclude_ids` = songs already queued/played, never picked |

Ids travel through v3 as a private token and are resolved with no title/composer matching (`V3Engine._resolve_titles` accepts it). The response carries `navidrome_id` on every song (it always did) and a new top-level `smart_pick: {"v": 1, "input": "ids|titles|ids+titles|playlist"}`; an old server has no such field, which is how the app knows to send titles. `candidate_ids` is capped at 3000.

### The log

New table `smart_pick_items` in the listener's own log (`served_id, rank, title, plays, days_since, familiar, decision, from_rank`; rank 0 = batch summary, e.g. `opener=yes familiar=40 cold=12`). `decision`: `opener_best_familiar`, `familiar`, `cold_last`, `model_order`. `served_batches` / `served_items` (play-events-v2) are untouched, so play-events-v2 and the hybrid shadow work as before. Erased by `DELETE /me/history`.

## What it patches

`navivibe/server.py` (6 anchored edits), `navivibe/recsys/recommender.py` (`_resolve_titles` accepts the id token) and adds `navivibe/smart_pick.py`. `patch.py` matches each old text **exactly once** or stops with nothing written ("the live code is not what this package was built on"); a second run changes nothing.

## Install (owner, as `subi`; sudo only for the restart)

```powershell
scp -r tool/server/smart-pick-v1 subi@100.99.105.51:~/
```

Check on a scratch copy of the live tree: runs the **whole live suite before** the patch, patches, runs it **again after**, installs nothing:

```bash
cd ~/smart-pick-v1 && bash install.sh --check
```

Install (backs up, patches, runs the whole suite on the live tree, puts every file back if anything fails, does not restart):

```bash
bash install.sh
```

Restart (the start runs `preprocess --full`, wait):

```bash
sudo systemctl restart navivibe
```

```bash
sleep 60; curl -s http://127.0.0.1:5500/ready; echo
```

See the decisions after a shuffle:

```bash
sqlite3 -readonly /DATA/AppData/navivibe/listening_logs/admin_listening_log.db "select s.rank, s.title, s.plays, s.days_since, s.decision from smart_pick_items s join served_batches b using(served_id) order by b.served_at desc, s.rank limit 20;"
```

Switch off without touching code: `SMART_PICK=off` in `/opt/shuffle-server/.env`, restart. Tunables (optional): `SMART_PICK_COLD_PLAYS=3`, `SMART_PICK_STALE_DAYS=30`, `SMART_PICK_PLAYLIST_TTL=30`.

## Rollback

The installer prints it: restore the backup's `server.py` and `recsys/recommender.py`, delete `navivibe/smart_pick.py` and `navivibe/tests/test_smart_pick_v1.py`, restart. The extra table is harmless to the old code.

## Tests

`navivibe/tests/test_smart_pick_v1.py` (30, none skipped): a cold song is never first even when the model scores it highest; familiar first / cold last / one cold closes the batch; at most one cold in positions 2-7; no song twice and count kept; stale songs count as cold; boundaries of "familiar"; artist/film spacing; mid-session (no opener stage); a new listener and an all-cold playlist are not left empty; off, no engine and any error fall back to the plain queue; titles / ids / playlist forms (parsing, caps, exclude, same queue by ids and titles, exact id resolution in v3); decisions logged, erased and never in the response body; the patch is present in `server.py`. The installer runs the whole live suite before and after.

## Measured (offline, on read-only copies of the owner's logs; nothing committed)

See the section "Measured" in the final report of the session (numbers are not repeated here so they cannot drift from `tool/shuffle_eval/smart_pick_eval.py`, which reproduces them: `python smart_pick_eval.py --snapshot DIR`).
