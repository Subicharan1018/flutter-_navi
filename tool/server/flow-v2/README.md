# flow-v2: Flow chooses and orders songs by their sound

Flow used to build each batch from three piles (familiar, fresh, new language) and place them with no regard for how the songs sound next to each other. v2 uses Spotify's real energy, valence, tempo and key (2,109 of the 2,487 songs; the rest keep the calibrated guesses and are marked `predicted`) to

* **fit the mood chip**: a song's real numbers are compared with what that mood's labelled songs sound like in this library; songs far outside are dropped and the batch is drawn from the closest fits;
* **keep one artist from filling a batch** (two in eight) **or touching itself** (artist, film, composer);
* **sequence each batch** to keep the jump between neighbours small (energy, valence, tempo, key, track sound), start from the song already at the end of the queue, and lean toward familiar songs first and new ones later (a small effect in the replay: new songs' place in a batch 0.54 to 0.57);
* **mark down familiar songs you often skipped**;
* put `flow: {step, energy, valence, bpm, sound: real|predicted, fit}` on every song, and `flow_v2: {mode, ...}` on the answer.

Evidence, numbers, and what was tried and dropped: `docs/flow-better.md`. Nothing about skips is claimed: smoothness did not predict skips in the owner's data, and Flow's own plays are too few to say (details there).

## The flag: `FLOW_V2=off|shadow|on` (default `off`)

Set in `/opt/shuffle-server/.env`, restart `navivibe`. Read on every request. An unknown value is `off` and is logged once as an error.

| value | `/flow/next` answer | extra work |
|-------|--------------------|------------|
| `off` | exactly the old answer (a test pins it song for song against the unpatched flow.py) | none |
| `shadow` | the old answer plus a `flow_v2: {mode: "shadow"}` block | orders the same songs the v2 way and appends one line per batch to `flow_v2/shadow.jsonl` in the listening-log folder: `old` order, `new` order, `cost_old`, `cost_new`, mood, listener, session, the tail song, which songs were familiar or fresh |
| `on` | v2 selection and order, `flow` on every song | the same log line, `mode: "on"` |

Failures are never silent: a v2 error serves the old order and puts the reason in `flow_v2.error` and in the journal; a log that cannot be written is an error line in the journal; a chip too narrow for the fit rule is relaxed and says so (`flow_v2.relaxed`, a warning). The log stops at 20 MB (one error line).

Besides v2, the patch makes two old fallbacks speak: an unreadable Flow state file (`explore.Store()` failing, which turned off the cooldown and per-session memory) and an unreadable cooldown now write an exception to the journal. Answers do not change.

## Install (owner, as `subi`; sudo only for the restart)

```powershell
scp -r tool/server/flow-v2 subi@100.99.105.51:~/
```

Check on a scratch copy (installs nothing): runs the whole live suite before the patch, patches the copy, runs it again, and fails if any test that passed before fails now. It also runs the Flow tests with each mode.

```bash
cd ~/flow-v2 && bash install.sh --check
```

While `fix-server-tests` is unmerged the live tree has failing tests of its own (8 at last count): the check prints that number "before" and again "after", and only a test that passed before and fails after stops it.

Install (backs up, patches the live `flow.py`, tests the live tree, restores if a test that passed before fails; does not restart):

```bash
bash install.sh
sudo systemctl restart navivibe
```

Behaviour is unchanged until you set the flag. To watch first:

```bash
echo 'FLOW_V2=shadow' | sudo tee -a /opt/shuffle-server/.env
sudo systemctl restart navivibe
```

Read the log (it never contains more than ids and numbers):

```bash
tail -n 3 /DATA/AppData/navivibe/listening_logs/flow_v2/shadow.jsonl
```

## Rollback

`FLOW_V2=off` and a restart stops everything v2 does. To remove the code, the install prints the exact `cp` of the backed-up `flow.py` and the `rm` of the four new files (`navivibe/flow_v2.py`, `tests/test_flow_v2.py`, `tests/flow_v2_golden.json`, `tests/flow_v2_patch.py`), then `sudo systemctl restart navivibe`.

## Refuses loudly

`patch_flow.py` replaces exact text. If the live `flow.py` differs from the text it was made for (another patch, a different version), it prints which edit did not match, exits 2 and writes nothing; `install.sh` then stops before touching anything.

## Offline replay (not installed)

`eval/` holds the harness behind the numbers in the report: it builds a stand-in engine from read-only copies of `catalog.db`, `spotify_details.db`, the mood files and the listening logs, replays Flow queues with the old and the new code, and measures smoothness, repeats, chip agreement and a skip model. See `eval/README.md`.
