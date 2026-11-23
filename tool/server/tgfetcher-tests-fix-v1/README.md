# tgfetcher-tests-fix-v1: the tg-fetcher suite no longer depends on `/opt/tg-fetcher/.env`

Test file only (`tests/conftest.py`, one exact-text patch, line endings kept: that file is CRLF on the server). No
tg-fetcher code changes, nothing to restart.

## What went wrong

`tgfetch/config.py` loads `/opt/tg-fetcher/.env` at import (`os.environ.setdefault`), and `exportify.py` reads
`EXPORTIFY_BATCH_SIZE` / `EXPORTIFY_GB_PER_HOUR` at import. The installers' scratch copy has no `.env` (they exclude
it), so it passed; the "tests on the live tree" step reads the real one. Since channels-primary-v1 set
`EXPORTIFY_BATCH_SIZE=100`, `EXPORTIFY_GB_PER_HOUR=0.77` there, `test_exportify_v1::test_estimate_says_what_it_costs`
and `::test_batches_are_at_most_25_songs` failed, and every package that runs the live tg-fetcher suite
(spotify-history-import-v1, matcher-v2, channels-primary-v1, data-queue-v1's hook step, ...) would roll back.
Not a bug in the product: the code honours the `.env` as designed. The tests assumed the defaults.

## The fix

`tests/conftest.py` pins every tunable the code reads (`EXPORTIFY_*`, `CHANNEL_*`, `FETCH_PRIMARY`,
`FETCH_BOT_FALLBACK`, `JOB_CONCURRENCY`, `SEARCH_*`, `TG_DOWNLOAD_*`, limits per day, `ALLOWED_USERS`, keys and
tokens as empty ...) to its documented default **before** `tgfetch` is imported, so the `.env` (set-default) cannot
change a test; it also clears the per-call ones (`CHANNEL_FALLBACK_CHANNELS`, `DATA_QUEUE_OFF`, `HUMAN_CHECK_FILE`)
after the config has loaded. A test that wants another value sets it itself (`monkeypatch`). Secrets in `.env` are
now never visible to a test either.

## Counts (scratch copy of the live tree, the 6+ non-secret `.env` tunables present; no key or token copied)

| | no `.env` | live `.env` values |
|---|---|---|
| before | 689 passed | **2 failed**, 687 passed |
| after | 689 passed, 0 skipped | 689 passed, 0 skipped |

## Owner commands (as subi on the server)

```
scp -r tool/server/tgfetcher-tests-fix-v1 subi@100.99.105.51:~/
cd ~/tgfetcher-tests-fix-v1
bash install.sh --check     # prints before/after, with and without the live .env values
bash install.sh             # backs up, patches, runs the suite on the live tree WITH the real .env
```

Rollback (printed by the installer): `cp -a /opt/tg-fetcher/backups/tgfetcher-tests-fix-v1-<stamp>/tests/conftest.py /opt/tg-fetcher/tests/conftest.py`

## Install order for the pending packages: see the report in the session / `tool/server/INSTALL-ORDER.md`.
