"""tgfetcher-tests-fix-v1: the Weekly Exploration build thread never shares the service's sqlite connection.

A file database gives the build its own connection; polling /weekly/current all through a build must never make
it fail (it used to: sqlite3.InterfaceError, intermittently).

    cd /opt/tg-fetcher && venv/bin/python -m pytest tests/test_weekly_build_connection_v1.py -q
"""

import threading
import time
from dataclasses import replace

from fastapi.testclient import TestClient

from tgfetch import db
from tgfetch import exportify as ex
from tgfetch import weekly_exploration as wx
from tgfetch import weekly_exploration_api as wxapi
from tgfetch.api import create_app

from test_exportify_v1 import LIB, details_db  # noqa: F401  (details_db: autouse)
from test_weekly_exploration_v1 import SEEDS, hh, sources
from test_worker import _no_llm, cfg, fakes  # noqa: F401  (fixtures)


def test_a_file_database_gets_the_build_a_connection_of_its_own(cfg, monkeypatch, tmp_path):
    conn = db.connect(tmp_path / "fetch.db")
    monkeypatch.setattr(wxapi, "make_sources", sources)
    monkeypatch.setattr(wxapi, "load_library", lambda: [dict(s) for s in LIB])
    monkeypatch.setattr(ex, "free_bytes", lambda p: 200 * 10**9)
    used = {}
    real_build = wx.build

    def spy(c, *a, **kw):
        used["conn"], used["thread"] = c, threading.current_thread()
        return real_build(c, *a, **kw)

    monkeypatch.setattr(wx, "build", spy)
    c = replace(cfg, internal_token="t0ken", allowed_users=("alice",))
    client = TestClient(create_app(c, conn, {"telegram": lambda: True, "worker": lambda: True}))
    assert client.post("/weekly/build", json=SEEDS, headers=hh()).json() == {"started": True}
    polls = 0
    for _ in range(400):                                   # hammer the route the page polls during the build
        cur = client.get("/weekly/current", headers=hh()).json()
        polls += 1
        if not cur["building"] and not cur["needs_build"]:
            break
        time.sleep(0.005)
    assert len(cur["picks"]) == 20 and not cur.get("error"), cur
    assert used["conn"] is not conn and used["thread"] is not threading.main_thread()
    assert wx.get_prefs(conn, "alice")["enabled"] and polls >= 1
