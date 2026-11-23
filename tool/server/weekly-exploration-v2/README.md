# weekly-exploration-v2: start Weekly Exploration for listeners with a ListenBrainz key

For `/opt/shuffle-server`. **Needs weekly-exploration-v1** (installed). Patches nothing: one new command,
`navivibe/weekly_build.py`, and its tests. No restart.

Before this, a listener's list was built the first time they opened the page each week. This builds this week's list
for every listener who has **their own ListenBrainz key**, so the Home shelf is already there on Monday. Today that is
only the admin; everyone else is skipped by default (`--include-taste-only` can include them later).

## Where the songs come from

For a listener with a key, **the songs the ListenBrainz API returns for that listener** (their recommendations, up to 20),
each looked up on iTunes for the 30 s preview, exactly as the page does. If ListenBrainz returns at least 8 songs, the list is
those songs alone (source `ListenBrainz`); if fewer, the listener's own listening history fills in (`ListenBrainz + taste`).
The usual rules still apply (nothing owned, no remix/karaoke cuts, never-recommend, at most 2 an artist, 14-day expiry).
A listener without a key has no ListenBrainz data, so by default they get nothing (`no_listenbrainz_key`).
With `--include-taste-only` they are built from their listening history alone (and skipped as `no_listening_history` without any).

**A key is used only for its own account.** It is the key Navidrome holds for that exact user name (case-sensitive,
`user_props` `ListenBrainzSessionKey`). There is no server-wide token; the admin's key and ListenBrainz data are never used for
anyone else (tested). Keys are never printed, and go only to `api.listenbrainz.org`.

## What it does

For every Navidrome user in scope, in name order, it decides from `fetch.db` (read-only), `fetch_access`, Navidrome's user
table and the listening logs:

| Decision | Reason |
|---|---|
| skip | `no_download_access` (admins, a grant, or `FETCH_DEFAULT_ACCESS=all`, as the page) |
| skip | `turned_off` (they switched it off in Settings; a run never overrides this) |
| skip | `built_this_week` (a list was made this week, or it was empty because there was nothing to suggest) |
| skip | `building` (their build is running now) / `failed_recently` (failed under an hour ago; the page retries it) |
| skip | `no_listenbrainz_key` (default) / `no_listening_history` (only with `--include-taste-only`) |
| build | everyone else |

It builds **one listener at a time**: it sends their seeds to tg-fetcher exactly as the page does (signed `POST /weekly/build`),
waits until tg-fetcher says the list is made, pauses (default 30 s), then the next. tg-fetcher builds with its own throttle and
call budget (iTunes about 20 calls a minute; at most 70 outside calls a build), so a sequential run stays inside them. A listener
who fails is logged and the rest go on; exit code 1 if any failed. A build still going after 15 minutes stops the run (never two
at once). A lock stops cron and a hand run overlapping.

    --users admin         only the admin account(s) (`NAVIVIBE_ADMIN_USERS`): the owner's first start
    --users with-key      everyone with their own ListenBrainz key (the default; what the Monday cron runs)
    --users all-eligible  with-key plus --include-taste-only
    --include-taste-only  also listeners without a key, from their listening history alone
    --dry-run             per user: `key=yes|no  will build=yes|no  source=...  [reason]`; builds nothing, sends nothing
    --user N              only this listener (--force to top up a list already made this week)
    --pause S / --limit N seconds between listeners (default 30) / at most N builds

The dry run is offline: it does not call ListenBrainz, so how many songs ListenBrainz returns (and so whether taste fills in)
is only known in a real run, which prints `build  NAME: done (20 picks, source ListenBrainz)`.

## Install (on the server, as `subi`, no sudo)

    scp -r tool/server/weekly-exploration-v2 subi@100.99.105.51:~/
    ssh subi@100.99.105.51
    cd ~/weekly-exploration-v2
    bash install.sh --check      # scratch tests only; nothing live is touched
    bash install.sh              # tests, adds the command; the cron stays OFF
    bash install.sh --cron       # as above, then shows the Monday line and asks: type yes

The cron line it offers (the server clock is UTC, so 06:00 IST on Monday):

    30 0 * * 1 cd /opt/shuffle-server && nice -n 19 /opt/shuffle-server/venv/bin/python -m navivibe.weekly_build --users with-key >> /DATA/AppData/navivibe/weekly_exploration_build.log 2>&1 # navivibe-weekly-build

Run it now for the **admin only** (the first start):

    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build --users admin --dry-run
    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build --users admin

Turn on the **Monday job for everyone with a key**:

    bash install.sh --cron        # shows the line above and asks; type yes
    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build --users with-key --dry-run   # a look first

Later, to include listeners without a key: add `--include-taste-only` to the command (and to the cron line).
One listener: `... --user NAME` (add `--force` to top up).

Rollback: `rm -f /opt/shuffle-server/navivibe/weekly_build.py /opt/shuffle-server/navivibe/tests/test_weekly_build_v2.py`
(or the `.bak-<time>` copy the installer made), and `crontab -l | grep -v '# navivibe-weekly-build' | crontab -`.
Lists already built stay; the page and v1 are untouched.

## Checked on 23 Nov 2026 (read-only on the live server)

`--dry-run` against the real `fetch.db`, Navidrome users and listening logs (this file piped to the server's Python,
nothing installed, nothing written): 32 users. **Only the admin has a ListenBrainz key**, so `--users with-key` skips 28 as
`no_listenbrainz_key`, and the 4 others are `built_this_week`. `--users admin` says `admin: key=yes  will build=no  [built_this_week]`:
the admin opened the page this week, so that list (20 pending picks) already exists, and `--force` would add nothing (it tops up to
20). The admin-only run therefore does nothing until the next Monday. Nobody has turned it off; no one lacks download access
(`FETCH_DEFAULT_ACCESS=all`).

## Tests

Scratch copy of the live shuffle server on Windows: 29 tests in `test_weekly_build_v2.py` + the 14 of v1 pass (43). They cover every skip
reason; only listeners with their own key built, and taste-only users only with the flag; ListenBrainz as the main source with 8+
songs (taste not even loaded) and taste filling in with fewer; the exact-account key lookup (another account, another spelling of
the name, no key: nothing); the admin's key never sent for anyone else; a failing listener (or unreadable taste) not stopping the
others; a second run in the same week adding nothing; next week building again; dry run sending nothing; the limit; a never-ending
build stopping the run; signed calls; read-only access to `fetch.db`; the scope switch. tg-fetcher's Deezer / iTunes calls,
throttle and budget are covered by `tests/test_weekly_exploration_v1.py` there. Not run on the server: a real build through this
command, or a real ListenBrainz response for the admin.
