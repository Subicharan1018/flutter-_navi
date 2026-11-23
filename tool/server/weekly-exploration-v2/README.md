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

    --users admin         only the admin account(s) (`NAVIVIBE_ADMIN_USERS`): the owner's first start
    --users all-eligible  everyone allowed (the default; what the Monday cron runs)
    --dry-run   per user: `eligible` (with whether ListenBrainz hints are used) or `skipped` and why; builds nothing, sends nothing
    --user N    only this listener (--force to top up a list already made this week)

**ListenBrainz is strictly per listener.** The hints come only from the ListenBrainz key Navidrome holds for that exact
account (`user_props` `ListenBrainzSessionKey`, matched on the exact user name). There is no server-wide token anywhere (v1's page
path does the same lookup per signed-in user, and its cache is per user). The admin's key and data are never used for anyone
else; a listener without their own key gets taste-only picks. Today only the admin has a key. Keys are never printed or sent anywhere but `api.listenbrainz.org`.
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

    30 0 * * 1 cd /opt/shuffle-server && nice -n 19 /opt/shuffle-server/venv/bin/python -m navivibe.weekly_build --users all-eligible >> /DATA/AppData/navivibe/weekly_exploration_build.log 2>&1 # navivibe-weekly-build

Run it now for the **admin only** (the first start):

    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build --users admin --dry-run
    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build --users admin

Turn on the **Monday job for everyone allowed** (taste-only for those without their own ListenBrainz key):

    bash install.sh --cron        # shows the line above and asks; type yes
    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build --users all-eligible --dry-run   # a look first
    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build --users all-eligible             # or now (screen / tmux)

One listener: `... --user NAME` (add `--force` to top up).

Rollback: `rm -f /opt/shuffle-server/navivibe/weekly_build.py /opt/shuffle-server/navivibe/tests/test_weekly_build_v2.py`
(or the `.bak-<time>` copy the installer made), and `crontab -l | grep -v '# navivibe-weekly-build' | crontab -`.
Lists already built stay; the page and v1 are untouched.

## Checked on 23 Nov 2026 (read-only on the live server)

`--dry-run` against the real `fetch.db`, Navidrome users and listening logs (this file piped to the server's Python,
nothing installed, nothing written): 32 users. **6 would be built now**: anish, prem2323, Roopika K, Sanjai S, sanjayn29, shimal
(all taste-only: none of them has a ListenBrainz key; only the admin has one). `--users admin` says
`skipped admin: built_this_week`: the admin opened the page this week, so that list (20 picks, made through the page with the admin's own
hints) already exists; the admin-only run has nothing to do until next Monday, and `--force` would only top up to 20 (nothing to add).
Skipped: 4 `built_this_week` (admin, sandeep, vijay with 20 picks each, and JD with an empty list), 22 `no_listening_history`.
Nobody has turned it off and no one lacks download access (`FETCH_DEFAULT_ACCESS=all`).

## Tests

Scratch copy of the live shuffle server on Windows: 22 new tests + the 14 of v1 pass (36). Covers every skip reason, a failing
listener (or unreadable taste) not stopping the others, a second run in the same week adding nothing, next week building
again, dry run sending nothing, the limit, a never-ending build stopping the run, signed calls with the listener's own seeds, and
read-only access to `fetch.db`. tg-fetcher's Deezer / iTunes calls, throttle and budget are not re-tested here: they are
`tests/test_weekly_exploration_v1.py` in tg-fetcher, and this command only drives the same endpoint the page uses.
Not run on the server: an actual build through this command.
