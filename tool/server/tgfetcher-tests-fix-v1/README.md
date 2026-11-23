# tgfetcher-tests-fix-v1: the tg-fetcher suite no longer depends on `/opt/tg-fetcher/.env`

`tests/conftest.py` (exact-text patch, line endings kept: that file is CRLF on the server) **and one real bug fix** in
`tgfetch/weekly_exploration_api.py` (see the second section). The code fix needs `sudo systemctl restart tg-fetcher`.

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

## A REAL bug found on the way: Weekly Exploration's build thread shared the service's sqlite connection

`test_weekly_exploration_v1::test_routes_build_keep_skip_and_prefs` failed about 2 runs in 100 (also with NO `.env`
and without the conftest patch: 2/100 and 3/100 measured; it just was not hit before). Cause: `run_build` ran
`wx.build(conn, ...)` in a background thread on the SAME `sqlite3` connection the event loop uses for
`GET /weekly/current` (the page polls it during the build). Two threads on one connection give
`sqlite3.InterfaceError` -> "weekly: build failed" -> the list is not made ("It will try again"). **This can happen in
production** while the owner's page polls during a build; it is not only a test problem.
Fix: for a file database the build thread opens its own connection (same settings as `db.connect`) and closes it;
for an in-memory database (tests only, cannot be opened twice) the build and the weekly routes take turns on a lock.
New test `tests/test_weekly_build_connection_v1.py` (fails 8/8 without the fix). The same edit is in
`tool/server/weekly-exploration-v1/files/tgfetch/weekly_exploration_api.py` so a re-install of that package keeps it.
After: the flaky test 0/100 failed, the new test 0/50, the whole suite 5 runs x 690 passed.

## Counts (scratch copy of the live tree, the 6+ non-secret `.env` tunables present; no key or token copied)

| | no `.env` | live `.env` values |
|---|---|---|
| before | 689 passed | **2 failed**, 687 passed (+ about 2% flaky weekly test) |
| after | 690 passed, 0 skipped | 690 passed, 0 skipped |

## Owner commands (as subi on the server)

```
scp -r tool/server/tgfetcher-tests-fix-v1 subi@100.99.105.51:~/
cd ~/tgfetcher-tests-fix-v1
bash install.sh --check     # prints before/after, with and without the live .env values
bash install.sh             # backs up, patches, runs the suite on the live tree WITH the real .env
```

Rollback (printed by the installer): `cp -a /opt/tg-fetcher/backups/tgfetcher-tests-fix-v1-<stamp>/tests/conftest.py /opt/tg-fetcher/tests/conftest.py`

## Install order for the pending packages: see the report in the session / `tool/server/INSTALL-ORDER.md`.
