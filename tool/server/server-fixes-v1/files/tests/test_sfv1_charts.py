"""server-fixes-v1 #1: a chart song whose library id went `missing` is re-pointed
at its replacement (or goes back to pending), at snapshot time and after a
library change; the chart API never hands out a dead id."""

import asyncio
import sqlite3
from dataclasses import replace

from tgfetch import library_sweep as ls
from tgfetch import trending as tr
from tgfetch.config import settings

from test_trending import LIB, make
from test_trending import alerts, conn  # noqa: F401  (fixtures: charts schema included)

OLD, NEW = "2hfFjUHcMelIcVv8lEIH9H", "0RLJDGIPOLKnl1bLYu4WZI"
# The live library on 16 Nov 2026: the old file is `missing` (so not loaded),
# the re-imported one has the new id, title and artist identical.
RAGA = {"id": NEW, "title": 'Raga of Revenge (From "DC")', "artist": "Anirudh Ravichander",
        "album": "DC (Original Motion Picture Soundtrack)", "suffix": "flac", "duration": 131.25, "isrc": ""}
KAADHAL_OTHER = {"id": "5xQhqGZj0MgjytHm7FRLf6", "title": "Kaadhal En Kaviye", "artist": "Arun Pradeep • JESSE",
                 "album": "Kaadhal En Kaviye", "suffix": "flac", "duration": 97.13, "isrc": ""}
MANCHILD = {"id": "1gDe11soGgHnZELRVnesOR", "title": "Manchild", "artist": "Sabrina Carpenter",
            "album": "Man’s Best Friend", "suffix": "flac", "duration": 213.65, "isrc": ""}
LIVE = [RAGA, KAADHAL_OTHER, MANCHILD]


def _row(conn, key, title, artist, album, dur, nd, deezer_id=None, isrc=None, status="owned"):
    conn.execute("INSERT INTO trending_songs (key, deezer_id, title, artist, album, duration_s, isrc, status, "
                 "nd_song_id, run_date, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                 (key, deezer_id, title, artist, album, dur, isrc, status, nd, "2026-11-15", 1, 1))
    conn.execute("INSERT INTO trending_entries (chart, date, rank, key, title, artist, album, nd_song_id, created_at) "
                 "VALUES ('tamil', '2026-11-16', (SELECT COUNT(*) + 1 FROM trending_entries), ?, ?, ?, ?, ?, 1)",
                 (key, title, artist, album, nd))


def _seed(conn):
    tr.ensure_schema(conn)
    _row(conn, "saavn:WZ5FUQGs", "Raga of Revenge", "Anirudh Ravichander", "DC (Original Motion Picture Soundtrack)",
         131.0, OLD)
    _row(conn, "saavn:515HkIjE", "Kaadhal En Kaviye", "Sid Sriram", 'Kaadhal En Kaviye (From "Salmon 3D")',
         311.0, "3js3hmXEDS2MYbO4BQ4GD7")
    _row(conn, "dz:3400077541", "Manchild", "Sabrina Carpenter", "Manchild", 213.0, "1lus3FzlQwmg7hBarw5mc4",
         deezer_id="3400077541", isrc="USUM72504354")


def song(conn, key):
    return dict(conn.execute("SELECT * FROM trending_songs WHERE key=?", (key,)).fetchone())


def test_raga_of_revenge_is_repointed_to_the_reimported_file(conn):
    _seed(conn)
    out = ls.sweep(conn, [dict(r) for r in LIVE])
    assert out["repointed"] == 2 and out["pending"] == 1
    s = song(conn, "saavn:WZ5FUQGs")
    assert s["nd_song_id"] == NEW and s["status"] == "owned"
    assert conn.execute("SELECT nd_song_id FROM trending_entries WHERE key='saavn:WZ5FUQGs'").fetchone()[0] == NEW
    assert song(conn, "dz:3400077541")["nd_song_id"] == MANCHILD["id"]


def test_song_with_no_replacement_goes_back_to_pending(conn):
    _seed(conn)
    ls.sweep(conn, [dict(r) for r in LIVE])
    s = song(conn, "saavn:515HkIjE")           # only another artist's 97 s song of that name is left
    assert s["nd_song_id"] is None and s["status"] == "match"
    assert conn.execute("SELECT nd_song_id FROM trending_entries WHERE key='saavn:515HkIjE'").fetchone()[0] is None


def test_deezer_song_with_no_replacement_is_queued_again(conn):
    _seed(conn)
    ls.sweep(conn, [dict(r) for r in LIVE if r is not MANCHILD])
    s = song(conn, "dz:3400077541")
    assert s["status"] == "queued" and s["nd_song_id"] is None


def test_charts_own_matcher_is_tried_first(conn):
    _seed(conn)
    asked = []

    def owned(row):
        asked.append(row["key"])
        return NEW if row["key"] == "saavn:WZ5FUQGs" else None
    ls.sweep(conn, [dict(r) for r in LIVE], owned=owned)
    assert "saavn:WZ5FUQGs" in asked and song(conn, "saavn:WZ5FUQGs")["nd_song_id"] == NEW


def test_live_rows_are_left_alone(conn):
    _seed(conn)
    ls.sweep(conn, [dict(r) for r in LIVE])
    before = [dict(r) for r in conn.execute("SELECT * FROM trending_songs ORDER BY key")]
    assert ls.sweep(conn, [dict(r) for r in LIVE]) == {"repointed": 0, "pending": 0, "resolved": 0}
    assert [dict(r) for r in conn.execute("SELECT * FROM trending_songs ORDER BY key")] == before


def test_chart_api_never_hands_out_a_dead_id(conn, alerts):
    t = make(conn, alerts)
    _seed(conn)
    t.load_library = lambda: [dict(r) for r in LIVE]
    rows = {e["title"]: e for e in t.chart("tamil")["entries"]}
    # Before any sweep: the dead ids are not playable, so not "available".
    assert rows["Raga of Revenge"]["song_id"] is None and rows["Raga of Revenge"]["status"] == "pending"
    ls.sweep(conn, t.load_library())
    rows = {e["title"]: e for e in t.chart("tamil")["entries"]}
    assert rows["Raga of Revenge"]["song_id"] == NEW and rows["Raga of Revenge"]["status"] == "available"
    assert rows["Kaadhal En Kaviye"]["song_id"] is None and rows["Kaadhal En Kaviye"]["status"] == "pending"


def test_snapshot_repoints_a_replaced_file(conn, alerts):
    t = make(conn, alerts)
    asyncio.run(t.snapshot([tr.BY_KEY["tamil"]]))
    assert song(conn, "saavn:s1")["nd_song_id"] == "nd1"
    # The file was re-tagged: Navidrome now has it as nd1b, nd1 is missing.
    t.load_library = lambda: [{**dict(LIB[0]), "id": "nd1b"}, dict(LIB[1])]
    asyncio.run(t.snapshot([tr.BY_KEY["tamil"]], date="2026-10-19"))
    s = song(conn, "saavn:s1")
    assert s["nd_song_id"] == "nd1b" and s["status"] == "owned"
    assert t.chart("tamil")["entries"][0]["song_id"] == "nd1b"


def _nd_db(path, rows, scanned="2026-11-16 00:00:00"):
    c = sqlite3.connect(path)
    c.execute("CREATE TABLE IF NOT EXISTS media_file (id TEXT, title TEXT, artist TEXT, album TEXT, suffix TEXT, "
              "duration REAL, tags TEXT, path TEXT, missing INT, updated_at TEXT)")
    c.execute("CREATE TABLE IF NOT EXISTS library (id INT, last_scan_at TEXT, total_missing_files INT, total_songs INT)")
    c.execute("DELETE FROM media_file")
    c.execute("DELETE FROM library")
    for r in rows:
        c.execute("INSERT INTO media_file VALUES (?,?,?,?,?,?,?,?,?,?)",
                  (r["id"], r["title"], r["artist"], r["album"], "flac", r["duration"], "{}", r["id"],
                   r.get("missing", 0), scanned))
    c.execute("INSERT INTO library VALUES (1, ?, ?, ?)", (scanned, sum(r.get("missing", 0) for r in rows), len(rows)))
    c.commit()
    c.close()


def test_sweep_runs_after_a_library_scan_only(conn, alerts, tmp_path):
    nd = str(tmp_path / "navidrome.db")
    _nd_db(nd, [{**RAGA, "id": OLD, "missing": 0}])
    t = make(conn, alerts)
    t.s = replace(settings, navidrome_db=nd)
    t.load_library = lambda: __import__("tgfetch.library", fromlist=["x"]).load_library(nd)
    _seed(conn)
    conn.execute("DELETE FROM trending_songs WHERE key!='saavn:WZ5FUQGs'")
    assert asyncio.run(ls.maybe_sweep(t)) is not None          # first look: sweeps
    assert song(conn, "saavn:WZ5FUQGs")["nd_song_id"] == OLD   # still live then
    assert asyncio.run(ls.maybe_sweep(t)) is None              # checked moments ago
    t._sfv1_checked = 0
    assert asyncio.run(ls.maybe_sweep(t)) is None              # nothing changed in the library
    # Navidrome rescans: the old file is missing, the replacement is new.
    _nd_db(nd, [{**RAGA, "id": OLD, "missing": 1}, RAGA], scanned="2026-11-16 01:00:00")
    t._sfv1_checked = 0
    out = asyncio.run(ls.maybe_sweep(t))
    assert out["repointed"] == 1 and song(conn, "saavn:WZ5FUQGs")["nd_song_id"] == NEW


def test_tick_runs_the_sweep(conn, alerts, monkeypatch):
    t = make(conn, alerts)
    called = []

    async def fake(obj):
        called.append(obj)
    monkeypatch.setattr(ls, "maybe_sweep", fake)
    asyncio.run(t.tick())
    assert called == [t]


def test_clean_title_rules():
    assert ls.clean_title('Raga of Revenge (From "DC")') == ls.clean_title("Raga of Revenge")
    assert ls.clean_title("Kannala Kannala - The Melting Point of Love") == "kannala kannala"
    assert ls.clean_title("DC (Original Motion Picture Soundtrack)") == "dc"
    assert ls.versions("Untouchable (No) - Sped Up") == {"sped up"}
    assert ls.versions("Yad Speed Up") == {"sped up"}
    assert ls.split_names("Hiphop Tamizha • Kaushik Krish • Padmalatha") == ["hiphop tamizha", "kaushik krish",
                                                                              "padmalatha"]
    assert ls.share_artist("A. R. Rahman, Karthik", "AR Rahman")
    assert not ls.share_artist("Anirudh Ravichander", "Arun Pradeep • JESSE")
