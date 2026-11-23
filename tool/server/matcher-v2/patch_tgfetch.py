"""Apply (or check) the matcher-v2 edits to /opt/tg-fetcher.

    python patch_tgfetch.py <tg-fetcher-root>            apply; every edit must match exactly once
    python patch_tgfetch.py <tg-fetcher-root> --check    only report what is applied / pending / mismatching

New file: tgfetch/song_match.py (copied by install.sh, not here). Each edit is (file, marker, old, new, optional);
`marker` appears only after the edit, so a second run changes nothing. An `old` that is missing or ambiguous aborts
the run before any file is written. `optional` edits are skipped when the file is not installed (the package that
owns it is not on this server yet): install matcher-v2 AFTER such a package to get its edit.

What changes (README.md has the measured table):
  library_sweep.py         Index is song_match.Index (find() keeps its call and its answer for strong / isrc
                           matches; adds album= and fuzzy=; match() returns the confidence and the rule).
                           versions / clean_title / split_names / share_artist are NOT touched: exportify's stored
                           song keys are built from them.
  library.py               load_library also returns album_artist, composer, lyricist (from Navidrome's participants).
  exportify.py             the title match gets the row's album; the "maybe" (similar_id) also lists fuzzy matches.
  history_import.py        the listen's album goes to the matcher (ListenBrainz / Last.fm).
  weekly_exploration.py    a fuzzy match counts as owned (not worth suggesting).
  spotify_history.py       the play's album goes to the matcher (only when spotify-history-import-v1 is installed).
"""
import os
import sys

EDITS = []


def edit(rel, marker, old, new, optional=False):
    EDITS.append((rel, marker, old, new, optional))


# ── library_sweep.py: the matcher is song_match.Index ───────────────────────────────────────────────
edit("tgfetch/library_sweep.py", "from tgfetch.song_match import Index", '''class Index:
    """Library songs by clean title (and its phonetic key) for quick lookups."""

    def __init__(self, library: list[dict]):
        self.by_key: dict[str, list[dict]] = {}
        for s in library:
            t = clean_title(s.get("title") or "")
            if not t:
                continue
            for k in {t, "~" + phonetic_key(t)}:
                self.by_key.setdefault(k, []).append(s)
        self.ids = {s["id"] for s in library}

    def find(self, title: str, artist: str, duration: float | None, slack: float) -> dict | None:
        t = clean_title(title)
        if not t:
            return None
        seen, hits = set(), []
        for s in self.by_key.get(t, []) + self.by_key.get("~" + phonetic_key(t), []):
            if s["id"] not in seen and same_song(title, artist, duration, s, slack):
                seen.add(s["id"])
                hits.append(s)
        if not hits:
            return None
        if duration:
            return min(hits, key=lambda s: abs(float(s.get("duration") or 0) - float(duration)))
        return max(hits, key=lambda s: float(s.get("duration") or 0))
''', '''# matcher-v2: the matching rules are in tgfetch/song_match.py, ONE file shared with the offline tools
# (tool/exportify/spotify_match.py). Index.find(title, artist, duration, slack, album=None, fuzzy=None) returns the
# library song for "isrc" / "strong" matches (fuzzy=True adds the "probably the same song" ones);
# Index.match(...) returns song + confidence + rule. The old Index is kept in matcher-v2's backup folder.
from tgfetch.song_match import Index  # noqa: E402,F401
''')

# ── library.py: the credits the matcher compares ────────────────────────────────────────────────────
edit("tgfetch/library.py", "def _credits(", '''def load_library(db_path: str | None = None) -> list[dict]:
    conn = sqlite3.connect(f"file:{db_path or settings.navidrome_db}?mode=ro", uri=True, timeout=30)
    conn.row_factory = sqlite3.Row
    try:
        songs = []
        for r in conn.execute("SELECT id, title, artist, album, suffix, duration, tags "
                              "FROM media_file WHERE missing = 0"):
            song = dict(r)
            song["isrc"] = _isrc(song.pop("tags"))
            songs.append(song)
        return songs
    finally:
        conn.close()
''', '''def load_library(db_path: str | None = None) -> list[dict]:
    conn = sqlite3.connect(f"file:{db_path or settings.navidrome_db}?mode=ro", uri=True, timeout=30)
    conn.row_factory = sqlite3.Row
    try:
        songs = []
        try:    # matcher-v2: + the album artist and the composer / lyricist credits (Navidrome's participants)
            rows = conn.execute("SELECT id, title, artist, album, suffix, duration, tags, album_artist, participants "
                                "FROM media_file WHERE missing = 0").fetchall()
        except sqlite3.OperationalError:        # an older Navidrome schema: the old columns only
            rows = conn.execute("SELECT id, title, artist, album, suffix, duration, tags "
                                "FROM media_file WHERE missing = 0").fetchall()
        for r in rows:
            song = dict(r)
            song["isrc"] = _isrc(song.pop("tags"))
            _credits(song)
            songs.append(song)
        return songs
    finally:
        conn.close()


def _credits(song: dict) -> None:
    """participants JSON → song["composer"] / song["lyricist"] ('A; B'); never raises."""
    raw = song.pop("participants", None)
    try:
        parts = json.loads(raw or "{}")
    except (ValueError, TypeError):
        parts = {}
    for role in ("composer", "lyricist"):
        try:
            names = [p.get("name") for p in (parts.get(role) or []) if isinstance(p, dict) and p.get("name")]
        except AttributeError:
            names = []
        song[role] = "; ".join(names)
''')

# ── exportify.py ────────────────────────────────────────────────────────────────────────────────────
edit("tgfetch/exportify.py", 'idx.find(r["title"], r["artist"], dur, DURATION_SLACK_S, album=r.get("album"))',
     '''    hit = idx.find(r["title"], r["artist"], dur, DURATION_SLACK_S)''',
     '''    hit = idx.find(r["title"], r["artist"], dur, DURATION_SLACK_S, album=r.get("album"))''')
edit("tgfetch/exportify.py", 'NEAR_SLACK_S, album=r.get("album"), fuzzy=True)',
     '''    near = idx.find(r["title"], r["artist"], dur, NEAR_SLACK_S) if dur else None''',
     '''    # matcher-v2: "probably the same song" (fuzzy) matches show up here as the "maybe", never as owned
    near = idx.find(r["title"], r["artist"], dur, NEAR_SLACK_S, album=r.get("album"), fuzzy=True) if dur else None''')

# ── history_import.py ───────────────────────────────────────────────────────────────────────────────
edit("tgfetch/history_import.py", 'DURATION_SLACK_S, album=l.get("album"))',
     '''            hit = hit or idx.find(title, artist, l["duration_s"], DURATION_SLACK_S)''',
     '''            hit = hit or idx.find(title, artist, l["duration_s"], DURATION_SLACK_S, album=l.get("album"))''')

# ── weekly_exploration.py ───────────────────────────────────────────────────────────────────────────
edit("tgfetch/weekly_exploration.py", 'album=c.get("album"), fuzzy=True):      # matcher-v2',
     '''        if idx is not None and idx.find(c["title"], c["artist"], c["duration_s"], OWNED_SLACK_S):''',
     '''        if idx is not None and idx.find(c["title"], c["artist"], c["duration_s"], OWNED_SLACK_S,
                                        album=c.get("album"), fuzzy=True):      # matcher-v2: "probably owned" is not new''')

# ── spotify_history.py (spotify-history-import-v1; optional) ────────────────────────────────────────
edit("tgfetch/spotify_history.py", 'hi.DURATION_SLACK_S, album=row.get("album"))',
     '''            cache[key] = idx.find(row["title"], row["artist"], None, hi.DURATION_SLACK_S)''',
     '''            cache[key] = idx.find(row["title"], row["artist"], None, hi.DURATION_SLACK_S, album=row.get("album"))''',
     optional=True)


def run(root, check_only):
    state, writes, bad = [], {}, False
    for rel, marker, old, new, optional in EDITS:
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            state.append(("skipped (not installed)" if optional else "MISSING FILE", rel, marker))
            bad = bad or not optional
            continue
        text = writes.get(path)
        if text is None:
            with open(path, encoding="utf-8", newline="") as f:
                text = f.read()
        if marker in text and old not in text:
            state.append(("applied", rel, marker))
            continue
        n = text.count(old)
        if n != 1:
            state.append((f"MISMATCH ({n} matches)", rel, marker))
            bad = True
            continue
        state.append(("pending", rel, marker))
        writes[path] = text.replace(old, new)
    for s, rel, marker in state:
        print(f"  {s:26s} {rel}  [{marker[:48]}]")
    if bad:
        print("!! not applying anything: fix the mismatching / missing edits first")
        return 1
    if check_only:
        return 0
    for path, text in writes.items():
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)
    print(f"  {len(writes)} file(s) written")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sys.exit(run(sys.argv[1], "--check" in sys.argv))
