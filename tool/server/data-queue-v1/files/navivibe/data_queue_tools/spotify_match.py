"""Read an Exportify CSV and match its rows to library songs, with no server import.

The same rules as exportify-v1's matcher (tool/server/server-fixes-v1 `library_sweep.Index.find`), re-implemented here
because that one imports server packages: ISRC first (exact), then the clean title (with "(From ...)", " - From ...",
"Original Motion Picture Soundtrack" and a trailing " - subtitle" dropped) + the SAME version words (a remix, sped-up,
live, karaoke ... never matches the plain song) + at least one artist in common + length within 5 seconds.
The `Added By` / `Added At` columns are never read.
"""
import csv
import difflib
import re
import unicodedata

SLACK_S = 5.0
FEATURES = ("danceability", "energy", "key", "loudness", "mode", "speechiness", "acousticness", "instrumentalness",
            "liveness", "valence", "tempo", "time_signature")
_FROM = re.compile(r"[\(\[]\s*(from|feat\.?|ft\.?)\b[^\)\]]*[\)\]]|\s[-–—]\s*(from|feat\.?|ft\.?)\b.*$", re.I)
_OST = re.compile(r"[\(\[]?\s*original\s+(motion\s+picture\s+)?(sound\s*track|score|background\s+score)\s*[\)\]]?", re.I)
_SUB = re.compile(r"\s+[-–—:|]\s+.*$")
_VERSION = re.compile(
    r"\b(remix|reprise|unplugged|lo-?fi|slowed|reverb|sped(?:\s+up)?|speed\s+up|acoustic|instrumental|karaoke|cover|live|"
    r"female|male|reloaded|extended|remaster(?:ed)?|mashup|duet|sad|version|revival|demo|nightcore|8d)\b", re.I)
_SPLIT = re.compile(r"\s*(?:[,;/&•·|]|\bfeat\.?|\bft\.?|\bfeaturing\b|\bwith\b)\s*|\s+(?:x|and)\s+", re.I)
_CANON = {"sped": "sped up", "speed up": "sped up", "lofi": "lo fi", "remastered": "remaster"}


def plain(text) -> str:
    return "".join(ch for ch in unicodedata.normalize("NFKC", str(text or "")).casefold()
                   if ch.isalnum() or unicodedata.category(ch).startswith("M"))


def versions(title) -> frozenset:
    out = set()
    for w in _VERSION.findall(unicodedata.normalize("NFKC", str(title or ""))):
        w = re.sub(r"[\s-]+", " ", w.lower()).strip()
        out.add(_CANON.get(w, w))
    return frozenset(out)


def clean_title(title) -> str:
    s = unicodedata.normalize("NFKC", str(title or ""))
    s = _OST.sub(" ", _FROM.sub(" ", s))
    if _SUB.search(s) and _SUB.sub("", s).strip():
        s = _SUB.sub(" ", s)
    return plain(s)


def names(credit) -> list:
    out = []
    for p in _SPLIT.split(unicodedata.normalize("NFKC", str(credit or ""))):
        n = plain(re.sub(r"\.\s*", "", p))
        if n and n not in out:
            out.append(n)
    return out


def share_artist(a, b) -> bool:
    return any(x == y or difflib.SequenceMatcher(None, x, y).ratio() >= 0.85 for x in names(a) for y in names(b))


def norm_isrc(v) -> str:
    return "".join(ch for ch in str(v or "").upper() if ch.isalnum())


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def parse_exportify(path) -> list:
    """[{isrc, title, artist, duration_s, features{...}}]; rows without a title are skipped."""
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
                         "duration_s": ms / 1000.0 if ms else _num(low.get("duration")),
                         "features": {f: _num(low.get(f)) for f in FEATURES if _num(low.get(f)) is not None}})
    return rows


class Index:
    def __init__(self, songs):
        self.by_isrc, self.by_title = {}, {}
        for s in songs:
            if norm_isrc(s.get("isrc")):
                self.by_isrc.setdefault(norm_isrc(s["isrc"]), []).append(s)
            t = clean_title(s.get("title"))
            if t:
                self.by_title.setdefault(t, []).append(s)

    def find(self, row):
        """(song, 'isrc' | 'title') or (None, None)."""
        if row["isrc"] and row["isrc"] in self.by_isrc:
            hits = self.by_isrc[row["isrc"]]
            d = row.get("duration_s")
            return (min(hits, key=lambda s: abs((s.get("duration") or 0) - d)) if d else hits[0]), "isrc"
        hits = [s for s in self.by_title.get(clean_title(row["title"]), [])
                if versions(row["title"]) == versions(s["title"])
                and share_artist(row["artist"], s.get("artist") or "")
                and (not row.get("duration_s") or not s.get("duration") or abs(s["duration"] - row["duration_s"]) <= SLACK_S)]
        if not hits:
            return None, None
        d = row.get("duration_s")
        return (min(hits, key=lambda s: abs((s.get("duration") or 0) - d)) if d else hits[0]), "title"


def match_rows(rows, songs):
    """[(row, song, how)] for the rows that matched; one row per library song (the first)."""
    idx, seen, out = Index(songs), set(), []
    for r in rows:
        s, how = idx.find(r)
        if s and s["id"] not in seen:
            seen.add(s["id"])
            out.append((r, s, how))
    return out
