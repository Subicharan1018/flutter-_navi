"""Apply (or check) the tgfetcher-tests-fix-v1 edits: tests/conftest.py (pins) and tgfetch/weekly_exploration_api.py (the build thread's own sqlite connection).

    python patch.py <tg-root>            apply; the edit must match exactly once
    python patch.py <tg-root> --check    only report applied / pending / mismatching

tgfetch/config.py loads <tg-root>/.env at import (`os.environ.setdefault`, so a variable that is already set wins),
and several modules read their tunables at import (exportify.BATCH_SIZE, GB_PER_HOUR) or per call (channels_first).
So a live tree with a real .env ran the suite with production values and two tests failed. conftest.py now pins
every tunable the code reads to its documented default BEFORE tgfetch is imported: .env can no longer change a test.
"""
import os
import sys

EDITS = []


def edit(rel, marker, old, new):
    EDITS.append((rel, marker, old, new))


# Documented defaults (the `os.getenv(NAME, default)` in the code). Secrets and ids are pinned to empty.
PINS = '''# tgfetcher-tests-fix-v1: the suite never depends on the live .env. tgfetch/config.py loads .env with
# os.environ.setdefault, so a variable pinned here wins over it. Every tunable the code reads is pinned to its
# documented default before tgfetch is imported (exportify.BATCH_SIZE / GB_PER_HOUR are read at import).
# A test that needs another value sets it itself (monkeypatch.setenv / setattr).
_PINNED_ENV = {
    "TG_API_ID": "", "TG_API_HASH": "", "TG_SOURCE": "@deezload2bot", "TG_SEARCH_PREFIX": ".trk",
    "TG_DOWNLOAD_CONNECTIONS": "8", "TG_DOWNLOAD_PART_KB": "512",
    "LLM_API_KEY": "", "GROQ_API_KEY": "", "INTERNAL_TOKEN": "", "NTFY_TOPIC": "", "NTFY_SERVER": "https://ntfy.sh",
    "ND_USER": "", "ND_PASS": "", "ALLOWED_USERS": "admin", "ADMIN_USERS": "admin", "ALLOWED_MIMES": "audio/x-flac,audio/flac",
    "MAX_ATTEMPTS": "3", "MAX_QUEUED_LINKS": "2", "SEARCHES_PER_DAY": "0", "JOBS_PER_DAY": "0", "GLOBAL_JOBS_PER_DAY": "0",
    "JOB_CONCURRENCY": "2", "SEARCH_MAX_ATTEMPTS": "5", "SEARCH_RETRY_BASE_S": "20", "SEARCH_VARIANTS": "6",
    "TRENDING_PARALLEL": "2", "REQUEST_RACE": "1",
    "FETCH_PRIMARY": "channels", "FETCH_BOT_FALLBACK": "1", "CHANNEL_MAX_MB": "100", "CHANNEL_MIN_FREE_GB": "25",
    "CHANNEL_SEARCH_GAP_S": "6", "CHANNEL_SKIP_EDITS": "1", "CHANNEL_FALLBACK": "1",
    "EXPORTIFY_BATCH_SIZE": "25", "EXPORTIFY_GB_PER_HOUR": "0.51",
}
os.environ.update(_PINNED_ENV)
# read per call, default "unset": cleared again after config has loaded the .env
_UNSET_AFTER_CONFIG = ("CHANNEL_FALLBACK_CHANNELS", "DATA_QUEUE_OFF", "HUMAN_CHECK_FILE")
'''

edit("tests/conftest.py", "_PINNED_ENV = {",
     '''os.environ["INTERNAL_HMAC_SECRET"] = ""
''',
     '''os.environ["INTERNAL_HMAC_SECRET"] = ""
''' + PINS)

edit("tests/conftest.py", "_UNSET_AFTER_CONFIG:",
     '''from tgfetch import db
''',
     '''from tgfetch import config as _config  # noqa: E402,F401  (loads .env: setdefault, the pins above win)

for _k in _UNSET_AFTER_CONFIG:
    os.environ.pop(_k, None)

from tgfetch import db
''')


# ── tgfetch/weekly_exploration_api.py: the build thread no longer shares the service's sqlite connection ──
# REAL BUG (intermittent in tests, possible in production): the build thread and the polls of /weekly/current used one
# connection at the same time -> sqlite3.InterfaceError -> 'weekly: build failed', the list was not made.
edit("tgfetch/weekly_exploration_api.py", 'contextlib.nullcontext',
     'import logging\nimport threading\n',
     'import contextlib\nimport logging\nimport sqlite3\nimport threading\n')

edit("tgfetch/weekly_exploration_api.py", 'def _open_own(',
     'def register_routes(app, settings, conn, who_dep) -> None:\n',
     'def _file_of(conn) -> str:\n    """The database file behind `conn` (\'\' for an in-memory database)."""\n    try:\n        row = conn.execute("PRAGMA database_list").fetchone()\n        return (row[2] if row else "") or ""\n    except Exception:\n        return ""\n\n\ndef _open_own(path: str):\n    """A connection for the build thread alone, to the same file (same settings as db.connect)."""\n    c = sqlite3.connect(path, timeout=10, isolation_level=None)\n    c.row_factory = sqlite3.Row\n    c.execute("PRAGMA busy_timeout=10000")\n    c.execute("PRAGMA foreign_keys=ON")\n    return c\n\n\ndef register_routes(app, settings, conn, who_dep) -> None:\n')

edit("tgfetch/weekly_exploration_api.py", 'db_guard = contextlib',
     '    wx.ensure_schema(conn)\n\n    def run_build(who: str, seeds: dict) -> None:\n        """Runs in its own thread: a build makes about 40 slow outside calls and must not hold the service."""\n        picks, err = 0, None\n        try:\n            try:\n                library = load_library()\n            except Exception as e:           # without the library every song looks new: do not build\n                log.warning("weekly: library not read (%s)", type(e).__name__)\n                raise RuntimeError("library") from None\n            picks = wx.build(conn, who, seeds, make_sources(), library)\n        except Exception as e:                                  # a failed build must never take the service down\n            err = f"The list couldn\'t be made ({type(e).__name__}). It will try again."\n            log.warning("weekly: build failed (%s)", type(e).__name__)\n        wx.finish_build(conn, who, picks, err)\n\n    @app.get("/weekly/current")\n    async def current(who: str = Depends(who_dep)):\n        return wx.current(conn, who)\n\n    @app.post("/weekly/build", status_code=202)\n    async def build(body: BuildIn, who: str = Depends(who_dep)):\n        if not wx.get_prefs(conn, who)["enabled"]:\n            return {"started": False, "reason": "off"}\n        if not wx.begin_build(conn, who):\n            return {"started": False, "reason": "running"}\n        threading.Thread(target=run_build, args=(who, body.model_dump()), daemon=True, name="weekly-build").start()\n        return {"started": True}\n\n    def act(fn, pick_id: int, who: str):\n        try:\n            return fn(conn, who, pick_id)\n        except wx.PickError as e:\n            raise HTTPException(409 if "expired" in str(e) or "way" in str(e) else 404, str(e)) from None\n\n    @app.post("/weekly/picks/{pick_id}/keep")\n    async def keep(pick_id: int, who: str = Depends(who_dep)):\n        return act(wx.keep, pick_id, who)\n\n    @app.post("/weekly/picks/{pick_id}/skip")\n    async def skip(pick_id: int, who: str = Depends(who_dep)):\n        return act(wx.skip, pick_id, who)\n\n    @app.post("/weekly/picks/{pick_id}/restore")\n    async def restore(pick_id: int, who: str = Depends(who_dep)):\n        return act(wx.restore, pick_id, who)\n\n    @app.put("/weekly/prefs")\n    async def prefs(body: PrefsIn, who: str = Depends(who_dep)):\n        wx.set_prefs(conn, who, body.enabled, body.cap)\n        return wx.current(conn, who)',
     '    wx.ensure_schema(conn)\n    db_path = _file_of(conn)      # read once, here, on the thread that owns `conn`\n    # The build runs in its own thread. One sqlite3 connection must not be used from two threads at once (the\n    # poll of /weekly/current during the build raised InterfaceError and the list was not made), so a file\n    # database gets the build a connection of its own. An in-memory database (tests) cannot be opened twice:\n    # there the build and the weekly routes take turns on this lock.\n    db_guard = contextlib.nullcontext() if db_path else threading.RLock()\n\n    def run_build(who: str, seeds: dict) -> None:\n        """Runs in its own thread: a build makes about 40 slow outside calls and must not hold the service."""\n        own = _open_own(db_path) if db_path else None\n        c = own or conn\n        picks, err = 0, None\n        try:\n            with db_guard:\n                try:\n                    try:\n                        library = load_library()\n                    except Exception as e:           # without the library every song looks new: do not build\n                        log.warning("weekly: library not read (%s)", type(e).__name__)\n                        raise RuntimeError("library") from None\n                    picks = wx.build(c, who, seeds, make_sources(), library)\n                except Exception as e:                              # a failed build must never take the service down\n                    err = f"The list couldn\'t be made ({type(e).__name__}). It will try again."\n                    log.warning("weekly: build failed (%s)", type(e).__name__)\n                wx.finish_build(c, who, picks, err)\n        finally:\n            if own is not None:\n                own.close()\n\n    @app.get("/weekly/current")\n    async def current(who: str = Depends(who_dep)):\n        with db_guard:\n            return wx.current(conn, who)\n\n    @app.post("/weekly/build", status_code=202)\n    async def build(body: BuildIn, who: str = Depends(who_dep)):\n        with db_guard:\n            if not wx.get_prefs(conn, who)["enabled"]:\n                return {"started": False, "reason": "off"}\n            if not wx.begin_build(conn, who):\n                return {"started": False, "reason": "running"}\n        threading.Thread(target=run_build, args=(who, body.model_dump()), daemon=True, name="weekly-build").start()\n        return {"started": True}\n\n    def act(fn, pick_id: int, who: str):\n        try:\n            with db_guard:\n                return fn(conn, who, pick_id)\n        except wx.PickError as e:\n            raise HTTPException(409 if "expired" in str(e) or "way" in str(e) else 404, str(e)) from None\n\n    @app.post("/weekly/picks/{pick_id}/keep")\n    async def keep(pick_id: int, who: str = Depends(who_dep)):\n        return act(wx.keep, pick_id, who)\n\n    @app.post("/weekly/picks/{pick_id}/skip")\n    async def skip(pick_id: int, who: str = Depends(who_dep)):\n        return act(wx.skip, pick_id, who)\n\n    @app.post("/weekly/picks/{pick_id}/restore")\n    async def restore(pick_id: int, who: str = Depends(who_dep)):\n        return act(wx.restore, pick_id, who)\n\n    @app.put("/weekly/prefs")\n    async def prefs(body: PrefsIn, who: str = Depends(who_dep)):\n        with db_guard:\n            wx.set_prefs(conn, who, body.enabled, body.cap)\n            return wx.current(conn, who)')


def run_edits(root, check_only):
    texts, plan = {}, []
    for rel, marker, old, new in EDITS:
        path = os.path.join(root, rel)
        if rel not in texts:
            if not os.path.exists(path):
                print("!! missing file:", path)
                return 2
            with open(path, encoding="utf-8", newline="") as f:
                texts[rel] = f.read()
        text = texts[rel]
        if marker in text:
            plan.append((rel, marker, "applied"))
            continue
        if "\r\n" in text:                       # the live conftest.py has Windows line endings: keep them
            old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
        n = text.count(old)
        if n != 1:
            plan.append((rel, marker, "MISMATCH (old text found %d times)" % n))
            continue
        plan.append((rel, marker, "pending"))
        texts[rel] = text.replace(old, new)
    for rel, marker, st in plan:
        print("  %-9s %-20s %s" % (st.split(" ")[0], rel, marker.strip()[:36]))
    bad = [p for p in plan if p[2].startswith("MISMATCH")]
    for rel, marker, st in bad:
        print("!!", rel, marker.strip()[:36], st)
    if bad:
        print("!! the live tests are not what this package was built on; nothing written")
        return 1
    if check_only:
        return 0
    for rel, text in texts.items():
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8", newline="") as f:
            if f.read() == text:
                continue
        tmp = path + ".tgfetcher-tests-fix-v1.tmp"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(run_edits(sys.argv[1], "--check" in sys.argv))
