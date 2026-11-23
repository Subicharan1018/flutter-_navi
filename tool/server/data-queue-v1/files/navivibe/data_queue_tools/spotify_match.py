"""Read an Exportify CSV and match its rows to library songs, with no server import.

The matching rules are NOT written here any more: they are matcher-v2's `song_match.py`, the same file the server's
`library_sweep.Index` uses (tool/server/matcher-v2/files/tgfetch/song_match.py; this folder holds a byte-identical
copy, matcher-v2's tests_repo/test_parity.py keeps the two equal). ISRC first (exact), then clean title + the same
version words + an artist (or the composer, or the film) in common + a length that fits the evidence. Every match
carries a confidence: "isrc", "strong", "fuzzy" (probably the same song: shown, never merged silently).
`Index.find(row)` keeps its old answer, (song, "isrc" | "title") for isrc / strong matches only;
`Index.find_match(row, fuzzy=True)` returns the full Match.
The `Added By` / `Added At` columns are never read.
"""
import csv

import song_match as sm

SLACK_S = sm.STRICT_SLACK_S
FEATURES = ("danceability", "energy", "key", "loudness", "mode", "speechiness", "acousticness", "instrumentalness",
            "liveness", "valence", "tempo", "time_signature")

versions = sm.versions
clean_title = sm.clean_title
names = sm.split_names
share_artist = sm.share_artist
norm_isrc = sm._isrc


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def parse_exportify(path) -> list:
    """[{isrc, title, artist, album, duration_s, features{...}}]; rows without a title are skipped."""
    rows = []
    with open(path, encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            low = {(k or "").strip().lower(): v for k, v in r.items() if (k or "").strip().lower() not in ("added by", "added at")}
            title = (low.get("track name") or low.get("title") or "").strip()
            if not title:
                continue
            ms = _num(low.get("duration (ms)"))
            rows.append({"isrc": norm_isrc(low.get("isrc")), "title": title,
                         "artist": (low.get("artist name(s)") or low.get("artist") or "").replace(";", ", "),
                         "album": (low.get("album name") or low.get("album") or "").strip(),
                         "duration_s": ms / 1000.0 if ms else _num(low.get("duration")),
                         "features": {f: _num(low.get(f)) for f in FEATURES if _num(low.get(f)) is not None}})
    return rows


class Index:
    def __init__(self, songs, rules=sm.ALL_RULES):
        self._idx = sm.Index(songs, rules)

    def find_match(self, row, fuzzy=True):
        """sm.Match (confidence isrc | strong | fuzzy) or None; fuzzy=False leaves the fuzzy ones out."""
        m = self._idx.match(row["title"], row.get("artist") or "", row.get("duration_s"), SLACK_S,
                            album=row.get("album"), isrc=row.get("isrc"))
        return m if m is not None and (fuzzy or m.confidence != "fuzzy") else None

    def find(self, row):
        """(song, 'isrc' | 'title') for isrc / strong matches, else (None, None)."""
        m = self.find_match(row, fuzzy=False)
        return (m.song, "isrc" if m.confidence == "isrc" else "title") if m else (None, None)


def match_rows(rows, songs):
    """[(row, song, how)] for the rows that matched (isrc / strong); one row per library song (the first)."""
    idx, seen, out = Index(songs), set(), []
    for r in rows:
        s, how = idx.find(r)
        if s and s["id"] not in seen:
            seen.add(s["id"])
            out.append((r, s, how))
    return out
