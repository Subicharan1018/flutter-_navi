# weekly-exploration-v2: start Weekly Exploration for everyone

For `/opt/shuffle-server`. **Needs weekly-exploration-v1** (installed). Patches nothing: one new command,
`navivibe/weekly_build.py`, and its tests. No restart.

Before this, a listener's list was built the first time they opened the page each week. This builds this week's list
for every listener who may use it, so the Home shelf is already there on Monday.

## What a listener who never opened the page gets

They are **on by default** (no `weekly_prefs` row means enabled, as in v1), so with download access and some listening
history they get the same 20 picks and the Home shelf as anyone else. Without history, or with downloads off for them,
they get nothing and nothing is stored.

## What it does

For every Navidrome user, in name order, it decides from `fetch.db` (read-only), `fetch_access` and the listening logs:

| Decision | Reason |
|---|---|
| skip | `no_download_access` (admins, a grant, or `FETCH_DEFAULT_ACCESS=all`, as the page) |
| skip | `turned_off` (they switched it off in Settings; a manual run never overrides this) |
| skip | `built_this_week` (a list was made this week, or it was empty because there was nothing to suggest) |
| skip | `building` (their build is running now) / `failed_recently` (failed under an hour ago; the page retries it) |
| skip | `no_listening_history` (under 3 artists with 2 completed plays in 4 weeks, nor 120 days, and no ListenBrainz hints) |
| build | everyone else |

It builds **one listener at a time**: it sends their taste to tg-fetcher exactly as the page does (signed
`POST /weekly/build`), waits until tg-fetcher says the list is made, pauses (default 30 s), then the next. tg-fetcher builds
with its own throttle and call budget (iTunes about 20 calls a minute; at most 70 outside calls a build), so a sequential run
stays inside them. A listener who fails is logged and the rest go on; exit code 1 if any failed. A build still going after
15 minutes stops the run (never two at once). A lock stops cron and a hand run overlapping.

    --dry-run   the decision for every user and why; builds nothing, sends nothing
    --user N    only this listener (--force to top up a list already made this week)
    --pause S   seconds between listeners (default 30)
    --limit N   at most N builds in this run

Keys are read by name from `/opt/shuffle-server/.env` and never printed.

## Install (on the server, as `subi`, no sudo)

    scp -r tool/server/weekly-exploration-v2 subi@100.99.105.51:~/
    ssh subi@100.99.105.51
    cd ~/weekly-exploration-v2
    bash install.sh --check      # scratch tests only; nothing live is touched
    bash install.sh              # tests, adds the command; the cron stays OFF
    bash install.sh --cron       # as above, then shows the Monday line and asks: type yes

The cron line it offers (the server clock is UTC, so 06:00 IST on Monday):

    30 0 * * 1 cd /opt/shuffle-server && nice -n 19 /opt/shuffle-server/venv/bin/python -m navivibe.weekly_build >> /DATA/AppData/navivibe/weekly_exploration_build.log 2>&1 # navivibe-weekly-build

Then:

    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build --dry-run     # who would get a list
    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build --user NAME   # one listener now
    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build               # everyone now (use screen / tmux)

Rollback: `rm -f /opt/shuffle-server/navivibe/weekly_build.py /opt/shuffle-server/navivibe/tests/test_weekly_build_v2.py`
(or the `.bak-<time>` copy the installer made), and `crontab -l | grep -v '# navivibe-weekly-build' | crontab -`.
Lists already built stay; the page and v1 are untouched.

## Checked on 23 Nov 2026 (read-only on the live server)

`--dry-run` against the real `fetch.db`, Navidrome users and listening logs (this file piped to the server's Python,
nothing installed, nothing written): 32 users. **6 would be built now**: anish, prem2323, Roopika K, Sanjai S, sanjayn29, shimal.
Skipped: 4 `built_this_week` (admin, sandeep, vijay with 20 picks each, and JD with an empty list), 22 `no_listening_history`.
Nobody has turned it off and no one lacks download access (`FETCH_DEFAULT_ACCESS=all`).

## Tests

Scratch copy of the live shuffle server on Windows: 22 new tests + the 14 of v1 pass (36). Covers every skip reason, a failing
listener (or unreadable taste) not stopping the others, a second run in the same week adding nothing, next week building
again, dry run sending nothing, the limit, a never-ending build stopping the run, signed calls with the listener's own seeds, and
read-only access to `fetch.db`. tg-fetcher's Deezer / iTunes calls, throttle and budget are not re-tested here: they are
`tests/test_weekly_exploration_v1.py` in tg-fetcher, and this command only drives the same endpoint the page uses.
Not run on the server: an actual build through this command.
