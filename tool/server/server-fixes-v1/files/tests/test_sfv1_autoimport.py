"""server-fixes-v1 #5: files copied into the music folder get the bot pipeline
(tags, ReplayGain, lyrics, Navidrome, sweep, doctor, catalog + moods), after
they stop changing, with a backup first; the first run only records what is there."""

import os
import struct
from dataclasses import replace
from pathlib import Path

import pytest
from mutagen.flac import FLAC

from tgfetch import autoimport as ai_mod, db, doctor
from tgfetch.autoimport import AutoImport
from tgfetch.config import settings
from tgfetch.importer import Importer
from tgfetch.rank import Candidate


def make_flac(path: Path, title="Song", artist="Artist", seconds=200, **tags) -> Path:
    """A metadata-only FLAC mutagen can read and write (STREAMINFO block)."""
    rate, ch, bps, total = 44100, 2, 16, 44100 * seconds
    packed = (rate << 44) | ((ch - 1) << 41) | ((bps - 1) << 36) | total
    info = struct.pack(">HH", 4096, 4096) + b"\x00\x00\x00\x00\x00\x00" + packed.to_bytes(8, "big") + b"\x00" * 16
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"fLaC" + bytes([0x80]) + len(info).to_bytes(3, "big") + info)
    f = FLAC(path)
    f.add_tags()
    f["title"], f["artist"] = [title], [artist]
    for k, v in tags.items():
        f[k] = [v]
    f.save()
    return path


class Clock:
    def __init__(self, t=1_800_000_000.0):
        self.t = t

    def __call__(self):
        return self.t


class FakeImporter(Importer):
    """The real tagging; ReplayGain, Navidrome find and scan are fakes."""
    def __init__(self, s):
        super().__init__(s)
        self.indexed, self.gains, self.scans, self.fail = {}, [], 0, False

    def tag(self, path, source="deezload"):
        if self.fail:
            Path(path).write_bytes(b"broken")
            raise OSError("disk full")
        return super().tag(path, source)

    def replaygain(self, path):
        self.gains.append(Path(path).name)
        return True

    def find(self, rel):
        return self.indexed.get(rel)

    async def start_scan(self):
        self.scans += 1
        return False


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(ai_mod, "SETTLE_S", 30)
    s = replace(settings, library_dir=tmp_path / "Music", db_path=tmp_path / "data" / "fetch.db",
                navidrome_db=str(tmp_path / "nope.db"), ntfy_topic="")
    (tmp_path / "Music").mkdir()
    clock = Clock()
    calls = {"doctor": [], "mood": [], "lyrics": [], "notify": []}

    async def lyrics(title, artist, album, duration):
        calls["lyrics"].append(title)
        return "[00:01.00] la"

    async def notify(s, title, message, tags=""):
        calls["notify"].append(message)

    def doctor_fn(s, ids, now):
        calls["doctor"].append(list(ids))
        return "doctor: nothing to fix"

    def mood_fn(ids):
        calls["mood"].append(list(ids))
        return '{"labelled": 1}'

    fetch = db.connect(s.db_path)
    imp = FakeImporter(s)
    library = []
    a = AutoImport(s, importer=imp, lyrics=lyrics, notify=notify, doctor_fn=doctor_fn, mood_fn=mood_fn,
                   catalog_ready=lambda ids: set(ids) & calls.setdefault("cataloged", set()),
                   fetch_conn=fetch, library_loader=lambda: library, clock=clock,
                   sleep=lambda s_: setattr(clock, "t", clock.t + s_))
    return a, s, clock, calls, imp, library, fetch


def stage(a, rel):
    r = a.conn.execute("SELECT * FROM files WHERE path=?", (rel,)).fetchone()
    return dict(r) if r else None


def test_first_run_only_records_existing_files(env):
    a, s, clock, calls, imp, *_ = env
    make_flac(s.library_dir / "old.flac")
    out = a.run_once()
    assert out["seeded"] == 1 and stage(a, "old.flac")["stage"] == "existing"
    assert FLAC(s.library_dir / "old.flac").get("tgfetch_source") is None
    clock.t += 3600
    assert a.run_once()["new"] == 0


def test_dropped_flac_goes_through_the_pipeline(env):
    a, s, clock, calls, imp, library, fetch = env
    a.run_once()                                                   # seed (empty)
    p = make_flac(s.library_dir / "Kannala Kannala.flac", title="Kannala Kannala",
                  artist="Hiphop Tamizha, Padmalatha")
    # A failed download of the same song is waiting in the queue's failed list.
    sid = db.create_search(fetch, "admin", "x", kind="tracks", status="done")
    db.save_candidates(fetch, sid, [Candidate(0, "r", "Kannala Kannala - The Melting Point of Love",
                                              "Hiphop Tamizha", "")])
    jid = db.create_job(fetch, "admin", db.get_search(fetch, sid)["candidates"][0]["id"])
    db.update_job(fetch, jid, status="failed", error="the music bot didn't send this song")
    clock.t += 5
    out = a.run_once()                                             # seen; settles within the pass
    assert out["tagged"] == 1
    row = stage(a, "Kannala Kannala.flac")
    assert row["stage"] == "tagged"
    f = FLAC(p)
    assert f["tgfetch_source"] == ["dropped"] and f["albumartist"] == ["Hiphop Tamizha"]
    assert f["artist"] == ["Hiphop Tamizha", "Padmalatha"]
    assert p.with_suffix(".lrc").exists() and imp.gains == ["Kannala Kannala.flac"] and imp.scans == 1
    bk = Path(row["backup"])
    assert bk.exists() and FLAC(bk).get("tgfetch_source") is None            # the original, untouched
    os.utime(p, (clock.t, clock.t))                                # just written (on the test clock)
    # Navidrome indexes it: the sweep resolves the failed download.
    imp.indexed["Kannala Kannala.flac"] = "nd-kk"
    library.append({"id": "nd-kk", "title": "Kannala Kannala", "artist": "Hiphop Tamizha • Padmalatha",
                    "album": "x", "suffix": "flac", "duration": 200.0})
    assert [f_["title"] for f_ in db.failed_songs(fetch)] == ["Kannala Kannala - The Melting Point of Love"]
    clock.t += 60
    out = a.run_once()
    assert out["indexed"] == 1 and stage(a, "Kannala Kannala.flac")["nd_song_id"] == "nd-kk"
    assert db.failed_songs(fetch) == []
    assert calls["notify"] and calls["doctor"] == []                       # doctor waits for a quiet file
    clock.t += doctor.RECENT_S + 60
    os.utime(p, (clock.t - doctor.RECENT_S - 60, clock.t - doctor.RECENT_S - 60))
    a.run_once()
    assert calls["doctor"] == [["nd-kk"]] and stage(a, "Kannala Kannala.flac")["stage"] == "doctored"
    calls["cataloged"].add("nd-kk")                                        # the shuffle server ingested it
    clock.t += 600
    a.run_once()
    assert calls["mood"] == [["nd-kk"]] and stage(a, "Kannala Kannala.flac")["stage"] == "done"


def test_a_growing_file_waits_until_it_stops_changing(env, monkeypatch):
    a, s, clock, calls, imp, *_ = env
    monkeypatch.setattr(ai_mod, "RUN_BUDGET_S", 0)                 # one look per pass
    a.run_once()
    p = s.library_dir / "big.flac"
    make_flac(p)
    a.run_once()
    assert stage(a, "big.flac")["stage"] == "seen"
    with open(p, "ab") as fh:                                      # still copying
        fh.write(b"\x00" * 100)
    clock.t += 40
    a.run_once()
    assert stage(a, "big.flac")["stage"] == "seen"                 # changed since the last look
    os.utime(p, (clock.t - 60, clock.t - 60))
    a.run_once()                                                   # mtime changed once more → observed
    clock.t += 40
    a.run_once()
    assert stage(a, "big.flac")["stage"] in ("tagged", "failed")


def test_bot_folder_hidden_and_partial_files_are_ignored(env):
    a, s, *_ = env
    a.run_once()
    make_flac(s.library_dir / "tg-fetcher" / "bot.flac")
    make_flac(s.library_dir / ".hidden.flac")
    make_flac(s.library_dir / "venv" / "x.flac")
    (s.library_dir / "notes.txt").write_text("x")
    (s.library_dir / "song.flac.part").write_bytes(b"x")
    make_flac(s.library_dir / "Album" / "CD1" / "track.flac")
    assert sorted(a.rel(p) for p in a.walk()) == ["Album/CD1/track.flac"]


def test_failed_tagging_puts_the_original_back(env):
    a, s, clock, calls, imp, *_ = env
    a.run_once()
    p = make_flac(s.library_dir / "x.flac", title="X")
    original = p.read_bytes()
    imp.fail = True
    clock.t += 5
    out = a.run_once()
    assert out["failed"] == 1 and stage(a, "x.flac")["stage"] == "failed"
    assert p.read_bytes() == original


def test_mp3_gets_replaygain_but_keeps_its_tags(env):
    a, s, clock, calls, imp, *_ = env
    a.run_once()
    (s.library_dir / "a.mp3").write_bytes(b"ID3" + b"\x00" * 200)
    clock.t += 5
    a.run_once()
    row = stage(a, "a.mp3")
    assert row["stage"] == "tagged" and "tags left as they are" in row["note"]


def test_removed_before_import_is_logged(env, monkeypatch):
    a, s, clock, *_ = env
    monkeypatch.setattr(ai_mod, "RUN_BUDGET_S", 0)
    a.run_once()
    p = make_flac(s.library_dir / "y.flac")
    a.run_once()
    p.unlink()
    a.run_once()
    assert stage(a, "y.flac")["stage"] == "gone"


def test_old_backups_are_pruned(env):
    a, s, clock, *_ = env
    old = a.backup_root / "20200101"
    old.mkdir(parents=True)
    (old / "f.flac").write_bytes(b"x")
    keep = a.backup_root / "20270110"
    keep.mkdir()
    other = a.backup_root / "not-ours"
    other.mkdir()
    assert a.prune_backups() == 1 and not old.exists()
