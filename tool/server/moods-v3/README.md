# moods-v3: moods decided from all the evidence, judged by the owner

For `/opt/shuffle-server/navivibe`. Needs moods-v2 and exportify-v1. Built on the live tree read
(read-only) on 23 Nov 2026. Not installed. **Installing changes no label**: the rules are off until
`mood_relabel --write`.

## Correction to moods-v2

The moods-v2 README claims 94 % precision. Don't rely on it. One session judged the 54 songs itself,
tuned the rules on those same songs, and reported the score on them. The owner's spot check found
about 2 wrong in 10. On that set v3 is no better (46 right, 3 wrong, 5 without a label; v2: 49, 3, 2),
so that set can't show whether v3 is an improvement. The accuracy of v3 is **unknown** until the owner
marks the review.

## Where "Thalaivane" got calm + sad

1. **The labeller (LLM), in October.** `["calm", "sad"]` is already in `mood_tags.json.bak-aathi`
   (24 Oct) and has been identical ever since. No tag mapping or lyrics rule produced it.
2. **It had little to go on.** No lyrics (LRCLIB and embedded both failed). `describe()` sent title,
   artist, film, language, key, valence, energy and the essentia scores, but **not the genre**:
   Action / Mass was never sent. What it was sent included essentia "relaxed" 0.62, and valence if it
   was known by then (0.25 now); the October request itself isn't stored, so that part is inference.
3. **It was never asked again.** It has no entry in `mood_meta.json`, so the moods-v2 prompt never
   rated it. Only 63 of 2,471 labels have one.
4. **No v2 rule could catch it.** calm needs energy >= 0.75 (it has 0.69), or energy >= 0.6 *and*
   tempo >= 140 (it has 90). Nothing reads genre tags. sad looks fine to v2, because valence is 0.25.
5. **The Spotify second opinion never ran for it.** Its `spotify_details.db` row is a `libenrich` row
   with every audio number NULL. Its real numbers are in `catalog.db` (`feature_source = spotify`).

**Was anything recomputed after the import?** The stored labels were not: `mood_tags.json` was last
written on 22 Nov 22:05 UTC, before the 23 Nov imports (01:06 and from 08:04), and nothing re-asks on
an import. The labels *in use* are computed at read time and do pick up new numbers: recomputing them
from a snapshot matches the server for 2,461 of 2,461 songs. So stale numbers weren't the problem.
The rules let the label through.

The numbers in `spotify_details.db`: 2,305 rows, 1,782 with energy. With the 453 catalog rows that
came from Spotify, 2,109 of 2,487 songs have real numbers.

## What changes (`catalog/mood_fusion.py`)

A mood must earn its place. Score = the labeller's vote (less without lyrics, more when it rated
itself confident) + the sound + tags + lyric words. Below the bar there is no label.

* **Sound:** Spotify details, else catalog Spotify, else the estimate at 0.6 trust (on 1,656 songs
  that have both, it is off by 0.10 energy and 0.14 valence on average). One source, never a mix.
* **Conflicts (out whatever the score).**
  - calm: an action / mass song; energy >= 0.62; a dance song at 0.52; 0.55 at 125-180 BPM and not
    acoustic.
  - sad: action / mass with energy >= 0.6; valence >= 0.55 or energy >= 0.75, unless the lyrics have
    3 different sad words.
  - happy: valence < 0.28.
  - energetic and angry: energy < 0.4 (energetic spares rap and dance, whose energy number misreads).
  - romantic: an action / mass song with no lyrics.
* **"energetic" can be added**, from Spotify's numbers only: mass with energy >= 0.62, dance with
  0.75, or 0.85 and danceable. No other mood is ever added.
* **Sad before romantic** needs a sad word. 8 of the owner's 10 admin edits removed or demoted "sad".
* **Tempo is only a nudge.** Calm and sad songs here span the same 81-160 BPM (half / double time), so
  "calm needs a low tempo" as a hard rule would not separate them.
* **Low valence alone is not sad here.** Karuppu Vellai (0.09) and The One (0.27) are "energetic, gym"
  to the owner. v3 still says sad for Karuppu Vellai.
* `confidence` orders the labels. It is not a probability until the marks calibrate it.
* The labeller is now told genre and danceability. `mood_audit` gets a reason, `v3_conflict`, for
  labels the sound contradicts and the rated prompt never gave.

The constants were set by hand while looking at the owner's 10 edits and 6 marks and at my old sample,
so none of those counts as a test of v3.

## Dry run on the live data (23 Nov 2026, nothing written)

2,461 songs with no admin label: 2,086 with Spotify's numbers, 374 estimated, 1 with none.

| | now (v2) | v3 |
|---|---|---|
| songs that change | | 907 (525 first labels) |
| labelled | 2,436 | 2,205 (239 lose every label, some gain "energetic") |
| gain "energetic" | | 68 |
| first label sad | 754 | 398 |
| first label romantic | 443 | 622 |
| first label calm | 85 | 78 |
| agree with Spotify's numbers | 79.8 % (417 of 2,062 contradict) | 97.9 % (39 of 1,885) |

The agreement row is **circular**: the rules read those numbers. It shows the rules work as written,
not that the moods are right. 525 changed first labels is a lot; mark the review before turning it on.

## The owner's review

`mood_review build` writes one HTML page (works offline, marks stay in the browser, "Save Marks"
downloads `mood-marks.json`). 101 songs: 40 drawn evenly (the only part that estimates the whole
library; about +/- 13 points), 45 whose label contradicts Spotify, 15 more that v3 changes, and
Thalaivane. No session pre-judged them by ear; "proposed" is only the rules' output.

`mood_review score mood-marks.json` gives right / wrong per group with a 95 % range, for the current,
the proposed and the labels in use. The marks then go in `tests/fixtures/` as the reference set (they
don't exist yet, so this package ships none) and `mood_reference.json` is retired.

## Use

```bash
bash install.sh --check
bash install.sh
sudo systemctl restart navivibe
cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m navivibe.catalog.mood_relabel --list 40
cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m navivibe.catalog.mood_relabel --write   # after the review
cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m navivibe.catalog.mood_relabel --off     # undo
```

`--write` only backs up the labels in use and writes `mood_rules.json`. `mood_tags.json`, admin labels
and "Not this mood" marks are never touched. To also ask the labeller again about the contradicted
labels: `bash relabel_moods.sh --reasons v3_conflict` (the moods-v2 script; dry run first).

Files: new `catalog/mood_fusion.py`, `mood_relabel.py`, `mood_review.py`, `mood_review_page.html`,
`tests/test_moods_v3.py`; patched `catalog/mood_quality.py`, `mood_tags.py`, `mood_audit.py`.
