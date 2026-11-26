"""Credits from what the library already says (file tags, album names, iTunes payloads). No network, no guessing.

Unknown stays unknown: a field is filled only when a source states it. Everything here is pure, so tests need no files.
"""
import json
import re
import unicodedata

# separators between several names in one tag ("A ; B", "A, B & C", "A feat. B")
_SPLIT = re.compile(r"\s*(?:;|/|\||&|,|\bfeat\.?|\bft\.?|\bfeaturing\b|\band\b|•|·|�)\s*", re.I)
# a bracketed group that is about the release, not the film's name
_JUNK_GROUP = re.compile(
    r"\s*[\(\[][^\)\]]*(?:soundtrack|original|\bost\b|motion picture|music from|music picture|"
    r"tamil|telugu|hindi|malayalam|kannada|deluxe|version|from the)[^\)\]]*[\)\]]", re.I)
_FROM = re.compile(r"[\(\[]\s*(?:from|music from)(?: the (?:movie|film))?\s*[:\-]?\s*[“\"'‘]?([^”\"'’\)\]]+?)[”\"'’]?\s*[\)\]]", re.I)
_RELEASE_TAIL = re.compile(r"\s*[-–]\s*(?:(?:tamil|telugu|hindi|malayalam|kannada)\s*[-–]\s*)?(?:ep|single)\s*$", re.I)
_SOUNDTRACK = re.compile(r"soundtrack|motion picture|music picture|\bost\b", re.I)


def norm_key(s) -> str:
    """The grouping key for a film or a person: case-folded letters, digits and combining marks only, so 'A. R. Rahman', 'A.R Rahman'
    and 'a r rahman' are one. MUST match `normKey` in lib/features/film_credits (a shared test vector pins both)."""
    s = unicodedata.normalize("NFKC", s or "").casefold()
    # letters, digits AND combining marks: Tamil vowel signs are marks (category M), dropping them would merge names
    return "".join(ch for ch in s if ch.isalnum() or unicodedata.category(ch)[0] == "M")


def split_names(s) -> list:
    """'A ; B, C' -> ['A', 'B', 'C'], de-duplicated by key, order kept. Empty / None -> []."""
    out, seen = [], set()
    for part in _SPLIT.split(s or ""):
        part = part.strip(" .\t")
        k = norm_key(part)
        if part and k and k not in seen:
            seen.add(k)
            out.append(part)
    return out


def clean_film(s) -> str:
    """'Kaaki Sattai (Original Motion Picture Soundtrack)' -> 'Kaaki Sattai'. Never invents: only strips."""
    s = (s or "").strip()
    prev = None
    while prev != s:
        prev = s
        s = _JUNK_GROUP.sub("", s).strip()
    s = _RELEASE_TAIL.sub("", s)
    return re.sub(r"\s+", " ", s).strip(" -–:")


def film_from_title(title) -> str:
    m = _FROM.search(title or "")
    return clean_film(m.group(1)) if m else ""


def film_of(song: dict, itunes: dict = None):
    """(film title, source) or ('', ''). Order of trust: the catalog's own film tag, then an album named as a
    soundtrack, then 'From "X"' in the title, then the same two hints in the iTunes payload."""
    f = clean_film(song.get("film"))
    if f:
        return f, "tag"
    album = song.get("album") or ""
    if _SOUNDTRACK.search(album):
        f = clean_film(album)
        if f:
            return f, "album"
    f = film_from_title(song.get("title"))
    if f:
        return f, "title"
    it = itunes or {}
    f = film_from_title(it.get("trackName"))
    if f:
        return f, "itunes"
    coll = it.get("collectionName") or ""
    if _SOUNDTRACK.search(coll):
        f = clean_film(coll)
        if f:
            return f, "itunes"
    return "", ""


def derive_song(song: dict, itunes: dict = None, known_lyricists: set = None) -> dict:
    """One song's credits from tags. `known_lyricists`: person keys already known to be lyricists (library tags,
    Wikidata); an artist-tag name in that set is credited as lyricist, not as singer."""
    known = known_lyricists or set()
    film, src = film_of(song, itunes)
    md = split_names(song.get("composer"))
    ly = split_names(song.get("lyricist"))
    ly_keys = {norm_key(n) for n in ly}
    sg = []
    for n in split_names(song.get("artist")):
        k = norm_key(n)
        if k in ly_keys:
            continue
        if k in known:
            ly.append(n)
            ly_keys.add(k)
            continue
        sg.append(n)
    return {"film": film, "fk": norm_key(film), "md": md, "ly": ly, "sg": sg, "film_src": src}


def itunes_payload(raw) -> dict:
    try:
        d = json.loads(raw) if isinstance(raw, str) else raw
        return d if isinstance(d, dict) else {}
    except (TypeError, ValueError):
        return {}
