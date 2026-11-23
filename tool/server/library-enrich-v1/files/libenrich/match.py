"""Parsing MusicBrainz / Last.fm answers and deciding whether a result is the same song."""
import difflib
import re
import unicodedata

from .net import NO_LABEL_IDS

DATE_OK = re.compile(r"^\d{4}(-\d{2}(-\d{2})?)?$")
ISRC_OK = re.compile(r"^[A-Z]{2}[A-Z0-9]{3}\d{7}$")
_NOISE = re.compile(r"\(\s*(from|feat|ft|with)\b[^)]*\)|\[[^\]]*\]|\s-\s*(from|feat|ft)\b.*$|"
                    r"original motion picture soundtrack", re.I)
TITLE_MIN = 0.88
LENGTH_SLACK_S = 6


def plain(text) -> str:
    """Case-folded letters and digits (and combining marks, so Tamil vowel signs survive)."""
    return "".join(ch for ch in unicodedata.normalize("NFKC", str(text or "")).casefold()
                   if ch.isalnum() or unicodedata.category(ch).startswith("M"))


def clean_title(title) -> str:
    return plain(_NOISE.sub(" ", str(title or "")))


def artist_parts(text) -> set:
    return {p for p in (plain(x) for x in re.split(r"[;,&/]| feat\.? | ft\.? | and ", str(text or ""), flags=re.I)) if p}


def artists_overlap(a, b) -> bool:
    pa, pb = artist_parts(a), artist_parts(b)
    if not pa or not pb:
        return False
    return any(x == y or difflib.SequenceMatcher(None, x, y).ratio() >= 0.85 for x in pa for y in pb)


def same_song(song: dict, title, artist, length_s) -> bool:
    """Title (version words like remix kept: they are part of the title), an artist in common, and a length
    within a few seconds when both are known. Strict on purpose: a wrong ISRC or label is worse than none."""
    if difflib.SequenceMatcher(None, clean_title(song["title"]), clean_title(title)).ratio() < TITLE_MIN:
        return False
    names = " ; ".join(x for x in (song.get("artist"), song.get("album_artist")) if x)
    if not artists_overlap(names, artist):
        return False
    d = song.get("duration") or 0
    if d and length_s:
        return abs(float(d) - float(length_s)) <= LENGTH_SLACK_S
    return True


def credit_names(rec: dict) -> str:
    return " ; ".join(c.get("name") or (c.get("artist") or {}).get("name", "") for c in rec.get("artist-credit", []) if isinstance(c, dict))


def good_date(d):
    return d if isinstance(d, str) and DATE_OK.match(d) else None


def good_isrc(i):
    i = "".join(ch for ch in str(i or "").upper() if ch.isalnum())
    return i if ISRC_OK.match(i) else None


def pick_search_hit(song: dict, search: dict):
    """The best accepted recording of a /recording search answer, or None."""
    best = None
    for rec in (search or {}).get("recordings", []):
        if int(rec.get("score", 0)) < 90:
            continue
        length = (rec.get("length") or 0) / 1000.0
        if same_song(song, rec.get("title"), credit_names(rec), length):
            best = best or rec
    return best


def parse_recording(rec: dict) -> dict:
    """What a recording says: isrc (the sorted first valid one), earliest date, genres {name: count}."""
    isrcs = sorted({i for i in (good_isrc(x) for x in rec.get("isrcs", [])) if i})
    dates = sorted(d for d in (good_date(r.get("date")) for r in rec.get("releases", [])) if d)
    first = good_date(rec.get("first-release-date")) or (dates[0] if dates else None)
    genres = {g["name"]: g.get("count", 1) for g in rec.get("genres", []) if g.get("name")}
    if not genres:
        genres = {t["name"]: t.get("count", 1) for t in rec.get("tags", []) if t.get("name")}
    return {"isrc": isrcs[0] if isrcs else None, "release_date": first, "genres": genres,
            "length_s": (rec.get("length") or 0) / 1000.0}


def parse_releases(rel: dict) -> dict:
    """label (of the earliest dated release that has a real label) and that release's date."""
    rows = []
    for r in (rel or {}).get("releases", []):
        for li in r.get("label-info", []) or []:
            lab = li.get("label") or {}
            name = (lab.get("name") or "").strip()
            if name and lab.get("id") not in NO_LABEL_IDS and name.lower() not in ("[no label]", "[unknown]", "[nolabel]"):
                rows.append((good_date(r.get("date")) or "9999", name))
    rows.sort()
    return {"label": rows[0][1] if rows else None}


def parse_lastfm(toptags: dict) -> dict:
    """{name: count} from a track.getTopTags / artist.getTopTags answer."""
    tags = ((toptags or {}).get("toptags") or {}).get("tag") or []
    if isinstance(tags, dict):
        tags = [tags]
    out = {}
    for t in tags:
        try:
            out[t["name"]] = int(t.get("count", 0))
        except (KeyError, TypeError, ValueError):
            continue
    return out
