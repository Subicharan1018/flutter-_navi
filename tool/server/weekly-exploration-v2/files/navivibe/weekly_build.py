"""
navivibe/weekly_build.py   (weekly-exploration-v2)
─────────────────────────────────────────────────
Start this week's Weekly Exploration for everyone, without each listener opening the page first.

    cd /opt/shuffle-server && venv/bin/python -m navivibe.weekly_build [--dry-run] [--user NAME] [--force]
                                                                      [--pause SECONDS] [--limit N]

For every Navidrome user it decides, from what the servers already hold (nothing is written to decide):

  skip  no_download_access   the account may not download (the same rule as the page: navivibe/fetch_access.py)
  skip  turned_off           they switched Weekly Exploration off in Settings
  skip  built_this_week      a list was made for them this week (done, or empty because there was nothing to suggest)
  skip  building             a build for them is running now
  skip  failed_recently      a build failed less than an hour ago (the page retries it by itself)
  skip  no_listening_history nothing to build from yet (the page would only say "play a few songs")
  build                      everyone else

and builds one listener at a time: it sends their taste ("seeds": artist names, languages, never-recommend
names, optional ListenBrainz hints) to tg-fetcher exactly as the page does (POST /weekly/build, signed), then waits
until tg-fetcher says the list is made before it pauses and moves to the next. tg-fetcher does the building with its
own throttle and call budget (iTunes about 20 calls a minute, at most 70 outside calls a build), so one listener
at a time with a pause keeps the whole run inside them. A listener who fails is logged and the rest go on.
A run that finds a build taking longer than 15 minutes stops (never two at once).

  --users admin         only the admin account(s) (NAVIVIBE_ADMIN_USERS): the owner's first start
  --users all-eligible  everyone allowed (the default, and what the Monday cron runs); those without their own
                        ListenBrainz key get taste-only picks
  --dry-run   per user: eligible (and whether ListenBrainz hints are used) or skipped and why; builds nothing, sends nothing
  --user N    only this listener (even when built already: add --force to top the list up)

ListenBrainz is strictly per listener: hints come only from the ListenBrainz key Navidrome holds for that exact account
(Settings > ListenBrainz). There is no server-wide token; the admin's key and data are never used for anyone else.
  --pause S   seconds between listeners (default 30)
  --limit N   build at most N listeners in this run

Never prints a key. Reads the fetch.db tables read-only; the only thing sent anywhere is the same request the
page sends. Run from the shuffle server's folder (it reads /opt/shuffle-server/.env for the bridge secrets by name).
"""

import argparse
import logging
import os
import sqlite3
import sys
import time
from pathlib import Path

log = logging.getLogger("navivibe.weekly_build")

FETCH_DB = os.getenv("FETCH_DB", "/opt/tg-fetcher/data/fetch.db")
NAVIDROME_DB_URI = os.getenv("NAVIDROME_DB_URI", "file:/DATA/AppData/navidrome/data/navidrome.db?mode=ro")
LOCK_PATH = os.getenv("NAVIVIBE_WEEKLY_BUILD_LOCK", "/tmp/navivibe-weekly-build.lock")
PAUSE_S = 30.0
POLL_S = 5.0
BUILD_TIMEOUT_S = 15 * 60
BUILD_STALE_S = 20 * 60          # tg-fetcher's own limit for a "running" build
RETRY_FAILED_S = 3600
IST_OFFSET_S = 5.5 * 3600
ENV_NAMES = ("TG_FETCHER_TOKEN", "TG_FETCHER_HMAC_SECRET", "TG_FETCHER_URL", "FETCH_DEFAULT_ACCESS", "NAVIVIBE_ADMIN_USERS",
             "FETCH_DB", "NAVIVIBE_SOCIAL_DB")


def load_env(path: str | None = None) -> None:
    """The names this tool needs from the server's .env (like bin/fetch-access): nothing else is read into the process."""
    p = Path(path or os.getenv("NAVIVIBE_ENV_FILE", "/opt/shuffle-server/.env"))
    if not p.is_file():
        return
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            if k.strip() in ENV_NAMES:
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def week_of(now: float) -> str:
    """The Monday of this week in India (tg-fetcher's `week_of`, kept in step by a test)."""
    import datetime as dt
    d = dt.datetime.fromtimestamp(now, dt.timezone(dt.timedelta(seconds=IST_OFFSET_S))).date()
    return (d - dt.timedelta(days=d.weekday())).isoformat()


# ── what the servers already know ────────────────────────────────────────────

def navidrome_users() -> list[str]:
    c = sqlite3.connect(NAVIDROME_DB_URI, uri=True, timeout=5)
    try:
        return [r[0] for r in c.execute("SELECT user_name FROM user ORDER BY lower(user_name)") if r[0]]
    finally:
        c.close()


def read_state(path: str | None = None) -> tuple[dict, dict]:
    """({user: enabled bool}, {user: {week, status, started_at, finished_at}}) from fetch.db, read-only.
    A missing table means nobody has opened the page yet: empty answers."""
    prefs, builds = {}, {}
    try:
        c = sqlite3.connect(f"file:{path or FETCH_DB}?mode=ro", uri=True, timeout=5)
    except sqlite3.Error:
        return prefs, builds
    try:
        c.row_factory = sqlite3.Row
        try:
            prefs = {r["user"]: bool(r["enabled"]) for r in c.execute("SELECT user, enabled FROM weekly_prefs")}
            builds = {r["user"]: dict(r) for r in c.execute(
                "SELECT user, week, status, started_at, finished_at FROM weekly_builds")}
        except sqlite3.Error:
            pass
    finally:
        c.close()
    return prefs, builds


def decide(user: str, now: float, *, has_access, prefs: dict, builds: dict, seeds_for, force: bool = False) -> tuple[str, str]:
    """("build" | "skip", reason). `has_access(user)`, `seeds_for(user)` (None while unknown) are only called when needed."""
    if not has_access(user):
        return "skip", "no_download_access"
    if prefs.get(user, True) is False:            # no row = on (tg-fetcher's default), as for a listener who never opened the page
        return "skip", "turned_off"
    b = builds.get(user)
    if b and b["status"] == "running" and now - b["started_at"] < BUILD_STALE_S:
        return "skip", "building"
    if b and b["week"] == week_of(now) and not force:
        if b["status"] in ("done", "empty"):
            return "skip", "built_this_week"
        if b["status"] == "failed" and now - (b["finished_at"] or 0) < RETRY_FAILED_S:
            return "skip", "failed_recently"
    seeds = seeds_for(user)
    if seeds is not None and not seeds.get("artists") and not seeds.get("extra"):
        return "skip", "no_listening_history"
    return "build", "this week's list is not made yet" if not b or b["week"] != week_of(now) else "topping up"


# ── the bridge to tg-fetcher (what fetch_proxy does for the page) ────────────

class Bridge:
    """Signed calls to tg-fetcher as one listener. `http(method, url, json, headers)` is requests.request."""

    def __init__(self, url: str, token: str, secret: str, http=None):
        import requests
        from navivibe.fetch_signing import sign
        self.url, self.token, self.secret, self._sign = url.rstrip("/"), token, secret, sign
        self.http = http or (lambda m, u, json=None, headers=None: requests.request(m, u, json=json, headers=headers, timeout=60))

    def call(self, user: str, method: str, path: str, body=None) -> tuple[int, dict]:
        r = self.http(method, f"{self.url}{path}", json=body,
                      headers={"X-Internal-Token": self.token, **self._sign(self.secret, user, True, method, path)})
        try:
            return r.status_code, r.json()
        except ValueError:
            return r.status_code, {}

    @classmethod
    def from_env(cls) -> "Bridge":
        tok, sec = os.getenv("TG_FETCHER_TOKEN", ""), os.getenv("TG_FETCHER_HMAC_SECRET", "")
        if not (tok and sec):
            raise SystemExit("!! TG_FETCHER_TOKEN / TG_FETCHER_HMAC_SECRET are not set (Online search is off on this server).")
        return cls(os.getenv("TG_FETCHER_URL", "http://127.0.0.1:5510"), tok, sec)


class TooSlow(Exception):
    pass


def build_one(bridge: Bridge, user: str, seeds: dict, *, sleep=time.sleep, clock=time.time) -> tuple[str, int]:
    """Start the build and wait for it. Returns (outcome, picks) with outcome started | running | off | done | empty | failed.
    Raises TooSlow when it is still going after BUILD_TIMEOUT_S."""
    code, body = bridge.call(user, "POST", "/weekly/build", seeds)
    if code != 202:
        raise RuntimeError(f"tg-fetcher answered {code}")
    if not body.get("started"):
        return ("off" if body.get("reason") == "off" else "running"), 0
    t0 = clock()
    while True:
        sleep(POLL_S)
        code, cur = bridge.call(user, "GET", "/weekly/current")
        if code == 200 and not cur.get("building"):
            n = len([p for p in cur.get("picks", []) if p.get("state") == "pending"])
            return ("done" if n else "empty"), n
        if code != 200:
            log.info("weekly build: current answered %s", code)
        if clock() - t0 > BUILD_TIMEOUT_S:
            raise TooSlow(user)


# ── the run ──────────────────────────────────────────────────────────────────

def run(users: list[str], now: float, *, has_access, prefs: dict, builds_for, seeds_for, bridge, dry: bool = False,
        force: bool = False, pause: float = PAUSE_S, limit: int | None = None, sleep=time.sleep, out=print,
        clock=time.time, has_key=lambda u: False) -> dict:
    """Decide for each user and (unless dry) build, one at a time. `builds_for()` re-reads the build table (so a second
    pass in the same run, or a page open meanwhile, is seen). Returns counts and the per-user decisions."""
    decisions, built, failed, stopped = [], 0, 0, False
    for u in users:
        try:
            action, why = decide(u, now, has_access=has_access, prefs=prefs, builds=builds_for(), seeds_for=seeds_for, force=force)
        except Exception as e:                      # reading their taste failed: this listener only
            failed += 1
            decisions.append((u, "error", type(e).__name__))
            out(f"FAILED      {u}: {type(e).__name__}: {str(e)[:120]}")
            continue
        if action == "build" and limit is not None and built + failed >= limit:
            action, why = "skip", "limit_reached"
        decisions.append((u, action, why))
        if dry:
            if action == "build":
                lb = "own ListenBrainz key" if has_key(u) else "none (taste only)"
                out(f"{'eligible':<11} {u}: {why}; ListenBrainz hints: {lb}")
            else:
                out(f"{'skipped':<11} {u}: {why}")
            continue
        if action != "build":
            out(f"{action:<11} {u}: {why}")
            continue
        try:
            outcome, n = build_one(bridge, u, seeds_for(u), sleep=sleep, clock=clock)
            out(f"build       {u}: {outcome} ({n} picks)")
            if outcome in ("done", "empty"):
                built += 1
            elif outcome == "failed":
                failed += 1
        except TooSlow:
            out(f"STOP        {u}: still building after {BUILD_TIMEOUT_S // 60} minutes; stopping so two builds never run at once")
            failed += 1
            stopped = True
            break
        except Exception as e:                      # one listener failing never stops the others
            failed += 1
            out(f"FAILED      {u}: {type(e).__name__}: {str(e)[:120]}")
        if pause and u != users[-1]:
            sleep(pause)
    return {"built": built, "failed": failed, "stopped": stopped, "decisions": decisions,
            "would_build": sum(1 for _, a, _ in decisions if a == "build") if dry else None}


def _seeds_loader(now: float):
    """seeds_for(user): the listener's taste, from the catalog and the listening logs. Loaded once, on first use."""
    state = {}

    def seeds_for(user: str):
        if "events" not in state:
            from navivibe import weekly_exploration as we
            from navivibe.catalog import store
            from navivibe.recsys.data import Catalog, load_all
            cat = Catalog.from_rows(store.load_catalog())          # what the recommender loads, without the models
            state["cat"], state["we"] = cat, we
            state["events"], _ = load_all(cat)
        we = state["we"]
        s = we.seeds_from(state["events"], state["cat"].meta, user, now, we.blocked_artist_names(user))
        s["extra"] = we.lb_hints(user, now, key=own_lb_key)      # strictly this listener's own key, else nothing
        return s

    return seeds_for


def own_lb_key(user: str) -> str | None:
    """The ListenBrainz key Navidrome holds for exactly this account (case-sensitive; never another account's, never a
    server-wide token: there is none). None means no hints for this listener: their list is taste only."""
    try:
        c = sqlite3.connect(NAVIDROME_DB_URI, uri=True, timeout=5)
        try:
            r = c.execute("SELECT p.value FROM user_props p JOIN user u ON u.id=p.user_id "
                          "WHERE p.key='ListenBrainzSessionKey' AND u.user_name=?", (user,)).fetchone()
        finally:
            c.close()
    except sqlite3.Error:
        return None
    return (r[0] or None) if r else None


def users_in_scope(scope: str, everyone: list[str], admins: set) -> list[str]:
    """`admin`: only the admin account(s) (NAVIVIBE_ADMIN_USERS); `all-eligible`: every user (the decision then drops
    those who may not use it)."""
    if scope == "admin":
        return [u for u in everyone if u.strip().lower() in admins]
    return list(everyone)


def _lock():
    """One run at a time (cron and a hand run could overlap). Best effort: no fcntl (Windows) means no lock."""
    try:
        import fcntl
        f = open(LOCK_PATH, "w")
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return f
    except ImportError:
        return True
    except OSError:
        return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dry-run", action="store_true")
    who = ap.add_mutually_exclusive_group()
    who.add_argument("--users", choices=("admin", "all-eligible"), default="all-eligible",
                     help="admin: only the admin account (the first start); all-eligible: everyone allowed (the Monday cron, the default)")
    who.add_argument("--user", help="one named listener")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--pause", type=float, default=PAUSE_S)
    ap.add_argument("--limit", type=int)
    a = ap.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    load_env()
    from navivibe import fetch_access
    now = time.time()
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(now)) + " UTC"
    everyone = navidrome_users()
    if a.user and a.user not in everyone:
        print(f"!! {a.user} is not a Navidrome user")
        return 2
    users = [a.user] if a.user else users_in_scope(a.users, everyone, fetch_access.admins())
    if not users:
        print(f"!! nobody in scope ({a.users}): is NAVIVIBE_ADMIN_USERS set to a Navidrome user?")
        return 2
    lock = _lock()
    if lock is None and not a.dry_run:
        print("!! another weekly build is running")
        return 3
    prefs, _ = read_state()
    bridge = None if a.dry_run else Bridge.from_env()
    scope = f"user {a.user}" if a.user else a.users
    print(f"weekly build {stamp}: week of {week_of(now)}, scope {scope}, {len(users)} user(s){' (dry run)' if a.dry_run else ''}")
    res = run(users, now, has_access=fetch_access.has_access, prefs=prefs, builds_for=lambda: read_state()[1],
              seeds_for=_seeds_loader(now), bridge=bridge, dry=a.dry_run, force=a.force,
              pause=a.pause, limit=a.limit, has_key=lambda u: own_lb_key(u) is not None)
    skipped = skip_summary(res["decisions"])
    print(f"done: built {res['built']}, failed {res['failed']}" + (f", eligible {res['would_build']}" if a.dry_run else "")
          + (f"; skipped {skipped}" if skipped else ""))
    return 1 if res["failed"] or res["stopped"] else 0


def skip_summary(decisions) -> str:
    from collections import Counter
    c = Counter(w for _, a, w in decisions if a == "skip")
    return ", ".join(f"{k} {v}" for k, v in sorted(c.items()))


if __name__ == "__main__":
    sys.exit(main())
