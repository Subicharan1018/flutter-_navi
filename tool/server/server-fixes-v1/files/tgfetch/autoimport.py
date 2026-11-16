"""
tgfetch/autoimport.py  (server-fixes-v1)
────────────────────────────────────────
Songs copied straight into the music folder (LIBRARY_DIR, /DATA/Media/Music =
Navidrome's /music) get what a bot download gets, as far as it applies to a
file that is already in place:

  1. settle     wait until the file stops changing (same size and mtime for
                SETTLE_S); a batch copy is handled together
  2. backup     the original is copied to <library>/../.autoimport-backup/<day>/
                before anything is written to it (kept BACKUP_KEEP_DAYS days)
  3. tag        FLAC: the importer's tagging (artist split, album artist,
                grouping with the library, name spellings; TGFETCH_SOURCE=dropped);
                ReplayGain (rsgain) when the file has none; synced lyrics (.lrc)
                when it has none. Other formats: ReplayGain only. A failure puts
                the backup back. Nothing is ever moved or deleted.
  4. index      ask Navidrome to scan (when ND_USER/ND_PASS are set; its own
                watcher and hourly scan also find it) and wait for the song id
  5. resolve    the library sweep: chart songs re-matched, failed downloads of
                this song marked resolved (failed list), see library_sweep.py.
                (There is no Wishlist on the server yet; nothing to resolve there.)
  6. doctor     the library doctor's per-song fixes (cover, ISRC, artist
                spelling) for just these songs, once the file has been quiet for
                the doctor's RECENT_S; only when the doctor is enabled
  7. catalog    the shuffle server's own catalog loop ingests new songs within
                CATALOG_POLL_SEC (10 min: enrich, language, audio, calibrate) and
                reloads its engine; once a song is in catalog.db its mood label
                is asked for right away (the nightly run would do it otherwise)

Each run is short and resumes from the state in data/autoimport.db, so a
systemd path unit (a file appears) plus a 10-minute timer drive it. The first
run only records the files already there (nothing is processed).

    venv/bin/python -m tgfetch.autoimport run       # one pass (the units call this)
    venv/bin/python -m tgfetch.autoimport status    # the latest files and what happened
"""

import argparse
import asyncio
import fcntl
import json
import logging
import os
import shutil
import sqlite3
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from tgfetch.config import Settings, settings as default_settings

log = logging.getLogger("tgfetch.autoimport")

AUDIO = {".flac", ".mp3", ".m4a", ".wav", ".ogg", ".opus", ".aiff", ".aif", ".wv", ".ape"}
SKIP_DIRS = {"__pycache__", "venv", ".venv", "site-packages", "node_modules", "dist-info"}
MAX_DEPTH = 3
SETTLE_S = float(os.getenv("AUTOIMPORT_SETTLE_S", "30"))
RUN_BUDGET_S = float(os.getenv("AUTOIMPORT_RUN_BUDGET_S", "900"))
INDEX_GIVE_UP_S = 6 * 3600
CATALOG_GIVE_UP_S = 3 * 3600
BACKUP_KEEP_DAYS = int(os.getenv("AUTOIMPORT_BACKUP_DAYS", "30"))
SHUFFLE_ROOT = os.getenv("NAVIVIBE_ROOT", "/opt/shuffle-server")
CATALOG_DB = os.getenv("NAVIVIBE_CATALOG_DB", f"{SHUFFLE_ROOT}/catalog.db")

SCHEMA = """
CREATE TABLE IF NOT EXISTS files (
    path        TEXT PRIMARY KEY,          -- relative to the library
    size        INTEGER,
    mtime       REAL,
    obs_at      REAL,                      -- when size/mtime were last seen to change
    seen_at     REAL NOT NULL,
    stage       TEXT NOT NULL,             -- existing | seen | tagged | indexed | doctored | done | gone | failed
    nd_song_id  TEXT,
    backup      TEXT,
    note        TEXT,
    updated_at  REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS files_stage ON files(stage);
CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
"""


def connect(path) -> sqlite3.Connection:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(str(path), timeout=30, isolation_level=None)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA journal_mode=WAL")
    c.executescript(SCHEMA)
    return c


def load_env_file(path: str) -> dict:
    out = {}
    try:
        for line in Path(path).read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                out[k.strip()] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return out


# ── the default steps that talk to other services (tests replace them) ──────

def default_mood(ids: list[str]) -> str:
    """Mood labels for these songs, by the shuffle server's own labeller
    (its venv, its .env for the Groq key)."""
    code = ("import json, sys\n"
            "from navivibe.catalog import mood_tags, store\n"
            "ids = set(json.loads(sys.argv[1]))\n"
            "rows = [r for r in store.load_catalog().values() if r.get('id') in ids]\n"
            "print(json.dumps(mood_tags.label_missing(rows=rows)))\n")
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "PYTHONPATH": SHUFFLE_ROOT,
           **load_env_file(f"{SHUFFLE_ROOT}/.env")}
    r = subprocess.run([f"{SHUFFLE_ROOT}/venv/bin/python", "-c", code, json.dumps(ids)], cwd=SHUFFLE_ROOT,
                       env=env, capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or "")[-300:])
    return (r.stdout or "").strip().splitlines()[-1] if r.stdout.strip() else "{}"


def default_catalog_ready(ids: list[str]) -> set:
    """Which of these songs the shuffle server's catalog has ingested."""
    if not ids:
        return set()
    try:
        c = sqlite3.connect(f"file:{CATALOG_DB}?mode=ro", uri=True, timeout=10)
    except sqlite3.Error:
        return set()
    try:
        marks = ",".join("?" * len(ids))
        return {r[0] for r in c.execute(
            f"SELECT id FROM songs WHERE id IN ({marks}) AND missing=0 AND enrich_status='done'", ids)}
    except sqlite3.Error:
        return set()
    finally:
        c.close()


def default_doctor(s: Settings, ids: list[str], now: float) -> str:
    """The doctor's fixes for just these songs (its nightly rules, its undo log)."""
    from tgfetch import doctor
    dconn = doctor.connect(s.db_path.with_name("doctor.db"))
    try:
        if doctor.get_meta(dconn, "enabled") != "1":
            return "doctor is off"
        songs = doctor.load_songs(s)
        new = [x for x in songs if x.id in set(ids)]
        if not new:
            return "not in Navidrome yet"
        # Artist spellings need the whole library to know which spelling dominates;
        # the live lookups (cover, ISRC) only for the new songs.
        full = doctor.plan_run(s, dconn, songs, lookups=False, sources=None, now=now, record=False)
        sub = doctor.plan_run(s, dconn, new, lookups=True, sources=doctor.Sources(), now=now)
        plan = {}
        for sid in ids:
            a, b = full["plan"].get(sid) or {}, sub["plan"].get(sid) or {}
            if not a and not b:
                continue
            plan[sid] = {"song": (a or b)["song"],
                         "edits": {**(b.get("edits") or {}), **(a.get("edits") or {})},
                         "cover": b.get("cover"),
                         "sources": {**{k: v for k, v in (b.get("sources") or {}).items() if k != "artist"},
                                     **(a.get("sources") or {})}}
        batch = "autoimport-" + datetime.fromtimestamp(now, doctor.IST).strftime("%Y%m%d-%H%M%S")
        stats = doctor.apply_plan(s, dconn, {**full, "plan": plan}, batch, now, limit=50)
        return f"doctor: {stats or 'nothing to fix'} (undo: bin/doctor undo {batch})"
    finally:
        dconn.close()


# ── the pass ─────────────────────────────────────────────────────────────────

class AutoImport:
    def __init__(self, s: Settings = default_settings, conn=None, importer=None, lyrics=None, notify=None,
                 doctor_fn=None, mood_fn=None, catalog_ready=None, fetch_conn=None, library_loader=None,
                 clock=time.time, sleep=time.sleep):
        from tgfetch import extras
        from tgfetch.importer import Importer
        self.s = s
        self.conn = conn or connect(s.db_path.with_name("autoimport.db"))
        self.importer = importer or Importer(s)
        self.lyrics = lyrics or extras.synced_lyrics
        self.notify = notify or extras.notify
        self.doctor_fn = doctor_fn or default_doctor
        self.mood_fn = mood_fn or default_mood
        self.catalog_ready = catalog_ready or default_catalog_ready
        self._fetch_conn = fetch_conn
        self.library_loader = library_loader
        self.clock, self.sleep = clock, sleep
        self.root = Path(s.library_dir)
        self.backup_root = self.root.parent / ".autoimport-backup"

    # files ------------------------------------------------------------------

    def walk(self):
        """Audio files under the library (not the bot's own folder, hidden or code folders)."""
        bot_dir = self.s.library_subdir

        def rec(d: Path, depth: int):
            try:
                entries = list(os.scandir(d))
            except OSError:
                return
            for e in entries:
                if e.name.startswith(".") or e.name.startswith("~"):
                    continue
                if e.is_dir(follow_symlinks=False):
                    if depth < MAX_DEPTH and e.name not in SKIP_DIRS and not e.name.endswith(".dist-info") \
                            and not (depth == 0 and e.name == bot_dir):
                        yield from rec(Path(e.path), depth + 1)
                elif e.is_file(follow_symlinks=False) and Path(e.name).suffix.lower() in AUDIO:
                    yield Path(e.path)
        yield from rec(self.root, 0)

    def rel(self, p: Path) -> str:
        return p.relative_to(self.root).as_posix()

    def _set(self, path: str, **f) -> None:
        f["updated_at"] = self.clock()
        cols = ", ".join(f"{k}=?" for k in f)
        self.conn.execute(f"UPDATE files SET {cols} WHERE path=?", (*f.values(), path))

    def seed(self) -> int:
        now = self.clock()
        n = 0
        for p in self.walk():
            st = p.stat()
            self.conn.execute("INSERT OR IGNORE INTO files (path, size, mtime, obs_at, seen_at, stage, updated_at) "
                              "VALUES (?,?,?,?,?, 'existing', ?)", (self.rel(p), st.st_size, st.st_mtime, now, now, now))
            n += 1
        self.conn.execute("INSERT OR REPLACE INTO meta (k, v) VALUES ('seeded', ?)", (str(now),))
        return n

    def observe(self) -> list[str]:
        """Record new files and size changes; return the settled ones ready to process."""
        now = self.clock()
        known = {r["path"]: dict(r) for r in self.conn.execute("SELECT * FROM files")}
        present = set()
        for p in self.walk():
            rel = self.rel(p)
            present.add(rel)
            try:
                st = p.stat()
            except OSError:
                continue
            row = known.get(rel)
            if row is None:
                self.conn.execute("INSERT INTO files (path, size, mtime, obs_at, seen_at, stage, updated_at) "
                                  "VALUES (?,?,?,?,?, 'seen', ?)", (rel, st.st_size, st.st_mtime, now, now, now))
                log.info("new file: %s (%d bytes)", rel, st.st_size)
            elif row["stage"] == "seen" and (row["size"] != st.st_size or row["mtime"] != st.st_mtime):
                self._set(rel, size=st.st_size, mtime=st.st_mtime, obs_at=now)
        ready = []
        for r in self.conn.execute("SELECT * FROM files WHERE stage='seen'"):
            if r["path"] not in present:
                self._set(r["path"], stage="gone", note="removed before it was imported")
                log.info("gone before import: %s", r["path"])
            elif now - r["obs_at"] >= SETTLE_S and now - (r["mtime"] or 0) >= SETTLE_S and r["size"]:
                ready.append(r["path"])
        return ready

    def unsettled(self) -> int:
        return self.conn.execute("SELECT COUNT(*) FROM files WHERE stage='seen'").fetchone()[0]

    # steps --------------------------------------------------------------------

    def backup(self, rel: str) -> Path:
        day = datetime.fromtimestamp(self.clock()).strftime("%Y%m%d")
        dest = self.backup_root / day / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(self.root / rel, dest)
        return dest

    def tag(self, rel: str) -> str:
        """Backup, then tags / ReplayGain / lyrics. Returns a note; raises after
        putting the original back when a step that writes the file fails."""
        path = self.root / rel
        is_flac = path.suffix.lower() == ".flac"
        bk = self.backup(rel)
        self._set(rel, backup=str(bk))
        notes = []
        try:
            tags = {}
            if is_flac:
                from mutagen.flac import FLAC
                audio = FLAC(path)
                if (audio.tags or {}).get("tgfetch_source"):
                    notes.append("tags already done")
                else:
                    tags = self.importer.tag(path, source="dropped")
                    notes.append("tagged")
                has_gain = bool((audio.tags or {}).get("replaygain_track_gain"))
            else:
                has_gain = self._has_gain(path)
                notes.append(f"{path.suffix.lower()[1:]}: tags left as they are")
            if not has_gain:
                notes.append("replaygain" if self.importer.replaygain(path) else "no replaygain (rsgain failed)")
        except Exception:
            shutil.copy2(bk, path)                          # put the original back
            raise
        if is_flac and not path.with_suffix(".lrc").exists():
            try:
                notes.append("lyrics" if self._lyrics(path, tags) else "no synced lyrics found")
            except Exception as e:                           # bookkeeping: never fails the import
                notes.append(f"lyrics skipped ({type(e).__name__})")
        return ", ".join(notes)

    @staticmethod
    def _has_gain(path: Path) -> bool:
        try:
            import mutagen
            f = mutagen.File(path)
            keys = {str(k).lower() for k in (f.tags.keys() if f is not None and f.tags else [])}
            return any("replaygain_track_gain" in k for k in keys)
        except Exception:
            return True                                      # unreadable: leave it alone

    def _lyrics(self, path: Path, tags: dict) -> bool:
        from mutagen.flac import FLAC
        from tgfetch import extras
        audio = FLAC(path)
        t = audio.tags or {}

        def first(k):
            return (t.get(k) or [""])[0]
        if first("lyrics") or first("unsyncedlyrics"):
            return False
        title = tags.get("title") or first("title")
        artist = tags.get("albumartist") or first("albumartist") or first("artist")
        lrc = asyncio.run(self.lyrics(title, artist, tags.get("album") or first("album"), audio.info.length))
        if lrc:
            extras.write_lrc(path, lrc)
            return True
        return False

    def _fetch(self):
        if self._fetch_conn is None:
            from tgfetch import db
            self._fetch_conn = db.connect(self.s.db_path)
        return self._fetch_conn

    def resolve(self) -> dict:
        from tgfetch import library_sweep, trending
        from tgfetch.library import load_library
        library = (self.library_loader or load_library)()
        conn = self._fetch()
        trending.ensure_schema(conn)
        t = trending.Trending(conn, self.s, library_loader=lambda: library)
        return library_sweep.sweep(conn, library, owned=library_sweep.chart_owned(t, library))

    # the pass ---------------------------------------------------------------

    def run_once(self) -> dict:
        out = {"new": 0, "tagged": 0, "failed": 0, "indexed": 0, "doctored": 0, "done": 0}
        if not self.conn.execute("SELECT 1 FROM meta WHERE k='seeded'").fetchone():
            n = self.seed()
            log.info("first run: %d files already in the library recorded; only new ones are imported", n)
            return {**out, "seeded": n}
        start = self.clock()
        while True:
            ready = self.observe()
            for rel in ready:
                out["new"] += 1
                try:
                    note = self.tag(rel)
                    self._set(rel, stage="tagged", note=note)
                    out["tagged"] += 1
                    log.info("%s: %s", rel, note)
                except Exception as e:
                    self._set(rel, stage="failed", note=f"{type(e).__name__}: {e}"[:300])
                    out["failed"] += 1
                    log.warning("%s: failed (%s: %s); the original is back in place", rel, type(e).__name__, e)
            if not self.unsettled() or self.clock() - start > RUN_BUDGET_S:
                break
            self.sleep(min(SETTLE_S / 3, 10))
        if out["tagged"]:
            try:
                asyncio.run(self.importer.start_scan())
            except Exception as e:
                log.warning("Navidrome scan request failed: %s", type(e).__name__)
        self.advance(out)
        self.prune_backups()
        return out

    def advance(self, out: dict) -> None:
        now = self.clock()
        newly = []
        for r in self.conn.execute("SELECT * FROM files WHERE stage='tagged'").fetchall():
            sid = self.importer.find(r["path"])
            if sid:
                self._set(r["path"], stage="indexed", nd_song_id=sid)
                newly.append((r["path"], sid))
                out["indexed"] += 1
            elif now - r["seen_at"] > INDEX_GIVE_UP_S:
                self._set(r["path"], stage="done", note=(r["note"] or "") + "; Navidrome never indexed it")
        if newly:
            try:
                res = self.resolve()
                log.info("after import: %s", res)
                for rel, sid in newly:
                    self._set(rel, note=f"{self._note(rel)}; song {sid}; sweep {res}")
            except Exception as e:
                log.warning("library sweep failed: %s", e)
            self._alert(newly)
        from tgfetch import doctor
        quiet = [dict(r) for r in self.conn.execute("SELECT * FROM files WHERE stage='indexed'")
                 if now - self._mtime(r["path"]) >= doctor.RECENT_S + 30]
        if quiet:
            try:
                res = self.doctor_fn(self.s, [r["nd_song_id"] for r in quiet], now)
            except Exception as e:
                res = f"doctor failed ({type(e).__name__})"
            for r in quiet:
                self._set(r["path"], stage="doctored", note=f"{self._note(r['path'])}; {res}")
                out["doctored"] += 1
            log.info("doctor for %d new song(s): %s", len(quiet), res)
        rows = [dict(r) for r in self.conn.execute("SELECT * FROM files WHERE stage='doctored'")]
        if rows:
            ready = self.catalog_ready([r["nd_song_id"] for r in rows])
            mine = [r for r in rows if r["nd_song_id"] in ready]
            if mine:
                try:
                    res = f"moods {self.mood_fn([r['nd_song_id'] for r in mine])}"
                except Exception as e:
                    res = f"mood labels failed ({type(e).__name__}); the nightly run will label them"
                for r in mine:
                    self._set(r["path"], stage="done", note=f"{self._note(r['path'])}; in the catalog; {res}")
                    out["done"] += 1
                log.info("catalog + moods for %d song(s): %s", len(mine), res)
            for r in rows:
                if r["nd_song_id"] not in ready and now - r["seen_at"] > CATALOG_GIVE_UP_S:
                    self._set(r["path"], stage="done",
                              note=f"{self._note(r['path'])}; not in the catalog yet: left to the nightly run")

    def _note(self, rel: str) -> str:
        r = self.conn.execute("SELECT note FROM files WHERE path=?", (rel,)).fetchone()
        return (r["note"] if r else "") or ""

    def _mtime(self, rel: str) -> float:
        try:
            return (self.root / rel).stat().st_mtime
        except OSError:
            return 0.0

    def _alert(self, newly: list) -> None:
        names = ", ".join(Path(p).stem for p, _ in newly[:5]) + (f" (+{len(newly) - 5} more)" if len(newly) > 5 else "")
        try:
            asyncio.run(self.notify(self.s, "Added from the music folder", names, "white_check_mark,musical_note"))
        except Exception:
            pass

    def prune_backups(self) -> int:
        """Drop our own backups older than BACKUP_KEEP_DAYS (never the library's files)."""
        if not self.backup_root.exists():
            return 0
        cut = self.clock() - BACKUP_KEEP_DAYS * 86400
        n = 0
        for d in self.backup_root.iterdir():
            try:
                day = datetime.strptime(d.name, "%Y%m%d").timestamp() if d.is_dir() else None
            except ValueError:
                continue                                    # not one of ours: never touched
            if day is not None and day + 86400 < cut:
                shutil.rmtree(d, ignore_errors=True)
                n += 1
        return n


def _status(ai: AutoImport, limit: int = 30) -> None:
    for r in ai.conn.execute("SELECT * FROM files WHERE stage!='existing' ORDER BY seen_at DESC LIMIT ?", (limit,)):
        when = datetime.fromtimestamp(r["seen_at"]).strftime("%d %b %H:%M")
        print(f"{when}  {r['stage']:<9} {r['path']}\n           {r['note'] or ''}")


def main(argv=None) -> None:
    p = argparse.ArgumentParser(prog="tgfetch.autoimport")
    p.add_argument("cmd", choices=["run", "status", "seed"])
    a = p.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)
    ai = AutoImport()
    if a.cmd == "status":
        _status(ai)
        return
    if a.cmd == "seed":             # install.sh: record what is there now, once; never processes anything
        if ai.conn.execute("SELECT 1 FROM meta WHERE k='seeded'").fetchone():
            print("already seeded")
        else:
            print(f"recorded {ai.seed()} files already in the library (they are never re-imported)")
        return
    lock = open(default_settings.db_path.with_name("autoimport.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log.info("another auto-import pass is running")
        return
    out = ai.run_once()
    log.info("auto-import pass: %s", out)


if __name__ == "__main__":
    sys.exit(main())
