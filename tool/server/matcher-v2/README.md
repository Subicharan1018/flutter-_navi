# matcher-v2: one song matcher for every importer

"Is this outside song one the library already has?" was answered by two hand-kept copies of the same rules
(`library_sweep.Index.find` on the server, `tool/exportify/spotify_match.py` offline) that disagreed (the offline one
dropped `(…)` differently and compared names with another similarity). It missed real matches (the library credits the
composer, Spotify the singers; a `(From "…")` film tag; 7 s of length) and still accepted a few wrong ones.
This package is **one file**, `files/tgfetch/song_match.py` (standard library only), used by the server's
`library_sweep.Index` and by the offline tools (byte-identical copies, checked by `tests_repo/test_parity.py`).
**Nothing about ISRC matches changed** (they are exact and checked first). Nothing is installed on the server by
this branch: you run `install.sh` yourself.

## What a match is now

`Index.match(title, artist, duration, slack, album=None, isrc=None)` → `Match(song, confidence, rule, delta)` or `None`.

| confidence | meaning | what the importers do |
|---|---|---|
| `isrc` | same ISRC | as before |
| `strong` | title + same version words + an artist in common + length within the caller's slack (**the old rule**), or the composer **and** the film agree, or the film agrees and the length is within 3 s | auto-accepted, as before |
| `fuzzy` | title + same version words + one good reason the old matcher could not see (composer / film agrees, a few more seconds, a looser spelling) | **shown, never merged silently** (below) |

`Index.find(title, artist, duration, slack[, album=, fuzzy=])` keeps the old call and answer (the library song or
`None`) for `isrc` / `strong`; `fuzzy=True` adds the fuzzy ones.

Where fuzzy shows up: Exportify lists it as the row's **"maybe"** (`similar_id`, the field that already existed; the row
stays `wishlist`, never `owned`); the history imports do not count it as a match (nothing is wrongly merged into someone's
history); Weekly Exploration treats it as owned (does not suggest a song you probably have).

## What changed in the rules (each one measured alone and together)

| # | rule | what it does |
|---|---|---|
| `versions` | more words that make another recording | `edit`/`radio edit`, `edition`, `mix`, `piano`, `orchestral`, `medley`, `rework`, `flip`, `bootleg`, `stripped`, `violin`, `flute`, `rap`, `trap`; plus a library title that says `(Background Score)` never matches a plain song. Only inside the matcher: `library_sweep.versions()` (used to build stored song keys) is untouched. |
| `len` (a) | length tolerance that scales with evidence | still the caller's slack (5 s) for `artist`; 5 s < Δ ≤ 15 s **and** ≤ 8 % of the song gives `fuzzy` (`artist+length`); never beyond 15 s; never when version words differ (97 s vs 313 s fails). |
| `names` (c, b) | name matching | `G. V. Prakash` = `G. V. Prakash Kumar` (shorter is a prefix, ≥ 2 tokens), `SS Thaman` = `Thaman S` (initials aside), `Sirkazhi` = `Dr. Seerkazhi S.`, `Jayashri` = `Jayasree`; a single first name is never enough (`Anirudh` ≠ `Anirudh Ravichander`); a name in `(feat. X)` counts. |
| `role` (b) | composer / lyricist / album artist | the credited name may also be the library's composer, lyricist or album artist (Spotify credits the composer, the library the singers). Only `fuzzy`, or `strong` together with the film. A writers' list as composers (`A; B; C`, a pop cover credits the original artist) does not count on its own. |
| `film` (b) | the film | `(From "X")` in a title, the album (`… (Original Motion Picture Soundtrack)`), the library's film / album. Spelling-tolerant (`Vinnathaandi` / `Vinnaithaandi`). An album named like the song is not a film. Film + length ≤ 3 s is `strong`; film alone is `fuzzy`. |
| `spell` (c) | transliteration | the old phonetic key (`aa`/`a`, `ee`/`i`, `zh`/`l`, `th`/`t`, doubled letters) is kept; a wider fold (`d`/`t`, `g`/`k`, `b`/`p`, `ae`/`e`, …) gives `fuzzy` only; `Dude – Orchestral Suite` = `Dude Orchestral Suite`. |
| `guard` (e) | same title, different song | a language tag that differs (`[TELUGU]` vs `(Tamil)`) rejects; no artist / composer in common and a different film (one side certain: an OST marker or a From tag) rejects; same credit but another film, matched only the wide-name way, is `fuzzy`. |
| `tie` (d) | several library songs share the title | surer rule, then the film that agrees, then the closest length (old: closest length, else the longest). |

Tried and **left out** because it could not be shown safe: *an exact title + length within 2 s with no artist / film evidence*
(3 right, 3 wrong on the gold set: two unrelated "Ghostbusters" of the same length); the library's `language` column as a
guard (it is wrong for some songs: it rejected a true Telugu match); `Background Score` as a plain version word (it
would have refused 39 library songs whose ISRC proves they are the Spotify "– Background Score" tracks).

## The gold set (not in the repo: your files)

4,140 labelled pairs, built from data on this PC. Nothing here depends on the new matcher to be "right":

| group | pairs | label | where it comes from |
|---|---|---|---|
| `hand` | 141 + 131 | same / different | the 298 library songs that share a title with a row/play the old matcher rejected; I read and labelled each (26 I could not tell are not scored) |
| `isrc_pos` | 1,677 | same | Exportify rows whose ISRC is in the library (22 of them differ in version words: refused by design, listed separately) |
| `isrc_neg` | 124 | different | same title, **different ISRC**, no same-artist-and-length duplicate |
| `old_accept` | 992 | same (assumed) | what the old matcher accepted (non-ISRC rows 104, Vijay's history 888); I read 50 random ones: 49 clearly the same song, 1 (*Water Packet*, credited to a different composer) plausible |
| `syn_*` | 1,075 | different | made from the library: 400 plain songs with a version word added (remix, sped up, live, karaoke, reprise, cover, unplugged, lofi, instrumental, slowed), 139 the other way round, 500 the same song with its length moved by 22 s – 216 s, 36 same title / different song inside the library |

`files/tests/fixtures/matcher_gold.json` is the **committed** fixture: 37 made-up pairs (15 same, 22 different; no real
titles, artists or films) with one pair per kind of mistake; `tests/test_matcher_v2.py` runs it.

## Measured (positives: `pos s+f / total` = strong + fuzzy found; FP = wrong ones accepted as strong + fuzzy)

| matcher | hard set (141 same / 131 different) | ISRC set (1,655 same / 124 different) | 1,075 synthetic negatives (FP) | old matches kept |
|---|---|---|---|---|
| **old** (`library_sweep`) | 0 / 141 found, FP 0 | 1604 / 1655, FP 0 | **5** | 992 / 992 |
| v2 with every rule off (parity) | identical to old | identical | 5 | 992 / 992 |
| + `versions` alone | 0 | 1604, FP 0 | **0** | 988 (4 old wrong ones now refused) |
| + `len` alone | 2f | 1604 + 3f, FP 2f | 5 | 992 |
| + `names` alone | **50s**, FP 1s | 1619 | 5 | 992 |
| + `role` alone | 27f | 1604 + 6f, FP 1f | 5 | 992 |
| + `film` alone | 1s + 132f, FP 3f | 1628 + 1f, FP 1s | 5 | 992 |
| + `spell` alone | 0 | 1606 + 1f | 5 | 992 |
| + `guard` alone | 0 | 1604 | 5 | 991 (1 Hindi-vs-Tamil refused) |
| + `tie` alone | 0 | 1604 | 5 | 992 |
| **all rules, strong only** (`find()` default) | **77s** of 141, FP **0** | **1628** of 1655, FP **1** | **0** | 987 |
| **all rules, strong + fuzzy** | 77s + 61f = 138 of 141, FP 2f | 1628 + 8f, FP 1s | 0 | 987 |

Precision / recall on the independent labels (hard + ISRC sets together):

| | precision | recall |
|---|---|---|
| old | 0.997 | 0.882 |
| v2 `strong` only | 0.999 | 0.938 |
| v2 `strong` + `fuzzy` | 0.998 | 0.976 |

By rule (gold set): `artist` strong 1671 right / 0 wrong; `composer+film` strong 29 / 1; `film+length` strong 5 / 0;
fuzzy: `film` 59 / 1, `artist+length` 5 / 0, `composer` 2 / 0, `artist+spelling` 1 / 0, `artist, other film` 0 / 1.
The 5 of the 992 old matches that are no longer `strong`: "Dusk Till Dawn – Radio Edit" and "On The Floor – Radio Edit" (a
different cut: the price of the new `edit` version word), "Sugar Baby" (Hindi album vs the Tamil file), and two the old
matcher got **wrong**: "Like a Prayer" vs its "Battle Royale Mix", "Oorum Blood – Orchestral" vs the plain song. On the
synthetic negatives the old matcher accepted 5 wrong pairs, v2 none. The one `strong` false positive left on the ISRC set
is "Rowdy Baby": the library holds the Telugu release, the row is the Tamil one, composer and film agree.
**The length that real same-recording pairs differ by** (ISRC set): 97.6 % within 1 s, 99.2 % within 3 s, 99.8 % within 5 s;
so 5 s is right for `strong` and the 15 s ceiling is a `fuzzy`-only extra. The tie-break showed **no measurable change** on
the gold set (1774 / 1776 right either way); it only reorders candidates that were accepted already.

## On the real data

* **`merged.csv`, the 16 unmatched rows**: 3 of the 3 matcher misses are found: *Vaaji Vaaji* (`strong`, film + same 347 s),
  *Every Breath You Take* (`fuzzy`, 7 s), *Often* (`fuzzy`, 15 s). *Kaadhal En Kaviye – Cover* (313 s vs a 97 s song) stays unmatched.
  The other 12 are not in the library (two are close: *Pallikattu Sabarimalaikku* is 19 s apart, beyond the ceiling).
* **Vijay's history** (2,997 distinct songs, 15,930 plays): the old matcher matched 888 songs (7,679 plays). New: **78 more songs
  (650 plays) as `strong`** (51 by the name rules, 27 composer + film), **74 more (516 plays) as `fuzzy`** (66 by film alone).
  Unmatched songs 1,957 (7,085 plays) are simply not in the library.
* **Exportify rows** (1,801 deduped): 1,677 by ISRC, 104 by title as before, 3 new, 17 not in the library.

## The review file you should eyeball

`C:\Users\yoges\Documents\matcher-v2-review.csv` (outside the repo, 57 pairs, with a `same song? y/n` column): the 3 merged.csv
rows, every kind of `fuzzy` rule, 24 `strong` ones. It is a sample of the *newly* matched, not of everything.

**Risk, plainly.** I read all 78 new `strong` history pairs: every one looked right. Two I caught while building were
wrong and are `fuzzy` now (*Wildest Dreams*: the library file is a string-quartet version that credits the original artist
as composer; one *Unnale*: another film). Of the 30 `fuzzy` pairs I read, 2 were wrong: roughly 1 in 15 (a cast or
instrumental version of the same film song). A wrong `strong` match would mean the history import credits plays to the
wrong library song, or Exportify calls a song owned when it is not; a wrong `fuzzy` one only shows a "maybe" you can ignore.
The sample is of *new* matches only and I am not you: the `y/n` column is the real test.
Switching a rule off is one word: remove it from `ALL_RULES` in `song_match.py` (and restart).

## Install (you run it; nothing is installed from this branch)

```
scp -r tool/server/matcher-v2 subi@100.99.105.51:~/matcher-v2
ssh subi@100.99.105.51
cd ~/matcher-v2 && bash install.sh --check       # scratch copy only: patch + the whole tg-fetcher suite
bash install.sh                                   # tests, back up, patch, tests again
sudo systemctl restart tg-fetcher
```

Needs server-fixes-v1; install it after exportify-v1 / history-import-v1 / weekly-exploration / spotify-history-import-v1
(a package that is not there yet is skipped; install matcher-v2 again after adding one). The shuffle server
(`navivibe`) does not import this and needs no restart; data-queue-v1 (not installed yet) carries its own copy of the
offline files and was updated to match (`song_match.py` is in its `TOOLS` list and parity test).

## Rollback

`install.sh` prints it; in short: copy `$TG/backups/matcher-v2-<stamp>/tgfetch/*.py` back over `$TG/tgfetch/` and
`sudo systemctl restart tg-fetcher`. The old `Index` text is in `patch_tgfetch.py`. `song_match.py` can stay (nothing imports it).

## Tests

* `files/tests/test_matcher_v2.py` (46 tests + 5 that need the patched tree): the made-up gold fixture (37 pairs), the
  contract (isrc exact and first, old four-argument call, caller slack, every old version word still blocks, tie-break),
  `norm_title` / `phonetic_key` equal the shuffle server's, the name similarity equals `rapidfuzz`, `load_library` credits.
* `tests_repo/test_parity.py` (repo only): copies byte-identical; the offline tool answers like the server index on the fixture.
* On a copy of the live `/opt/tg-fetcher` (read-only copy, run on this PC): 647 passed / 1 failed before, **698 passed /
  the same 1 failed after** (`test_concurrency` fails on Windows with or without this package); `test_sfv1_autoimport.py`
  needs `fcntl` (Linux) and was not run here. data-queue-v1's own 25 tests pass with the new files; with
  spotify-history-import-v1 added to the copy, 177 pass and 1 fails (`test_account_names_are_checked`, which fails the same
  without matcher-v2).
