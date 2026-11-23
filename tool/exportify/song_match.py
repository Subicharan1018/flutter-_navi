"""
tgfetch/song_match.py  (matcher-v2)
───────────────────────────────────
ONE matcher for "is this outside song one the library already has?", used by
every importer (Exportify, the Spotify / ListenBrainz / Last.fm history
imports, Weekly Exploration, the data queue, the library sweep).

Standard library only, so the very same file runs on the server (imported by
tgfetch/library_sweep.py) and offline (tool/exportify/spotify_match.py imports
a byte-identical copy). Nothing here touches a database, the network or the clock.

What a match is
───────────────
Index.match(...) returns a Match(song, confidence, rule, delta) or None.

  confidence  "isrc"    same ISRC (exact; checked first, never changed).
              "strong"  title + same version words + an artist in common
                        + length within the caller's slack (what the old
                        matcher accepted), or composer/film agreeing as well.
              "fuzzy"   title + same version words and ONE good reason that
                        the old matcher could not see (the credited name is
                        the composer, the film agrees, the length is a few
                        seconds further off). "Probably the same song":
                        callers show it, they do not silently merge it.

Index.find(...) keeps the old call and returns the library song for "isrc" /
"strong" only; pass fuzzy=True to include the fuzzy ones.

Never matches (whatever else agrees)
────────────────────────────────────
  * different version words (remix, reprise, sped up, live, karaoke, cover,
    unplugged, instrumental, female / male, duet, background score …)
  * different language tags ("[TAMIL]" vs "[TELUGU]")
  * lengths further apart than MAX_SLACK_S (15 s) or 8 %, even with every
    other piece of evidence (a 97 s song is not a 313 s song)
  * same title, no artist / composer in common and a different film
  * a title that is only the album ("Love Story" single) never counts as a film
"""

import re
import unicodedata
from dataclasses import dataclass

# ── tunables ─────────────────────────────────────────────────────────────────
STRICT_SLACK_S = 5.0        # weak evidence (title + a credited artist only)
AGREE_SLACK_S = 3.0         # film AND length this close: the same recording
MAX_SLACK_S = 15.0          # the most any evidence buys
MAX_SLACK_REL = 0.08        # ... and never more than 8 % of the song
ARTIST_SAME = 0.88          # normalised edit similarity of two spellings of one name
FILM_SAME = 0.88            # ... of two spellings of one film
FUZZY_IN_FIND = False       # Index.find() default: strong / isrc only

ALL_RULES = frozenset({"len", "role", "film", "names", "spell", "guard", "tie", "versions"})

# ── titles (norm_title / phonetic_key are the shuffle server's, copied exactly;
#    tests/test_matcher_v2.py proves it) ───────────────────────────────────────
_PAREN_RE = re.compile(r"[\(\[].*?[\)\]]")
_FROM_RE = re.compile(r"\s+-\s+(from|feat\.?|ft\.?)\b.*$", re.I)
_FEAT_RE = re.compile(r"\b(feat\.?|ft\.?|featuring)\b.*$", re.I)
_LANG_SUFFIX_RE = re.compile(
    r"\s*[-–(\[]\s*(tamil|telugu|hindi|malayalam|kannada|english)(\s+version)?\s*[)\]]?\s*$", re.I)
_PHONETIC = [("aa", "a"), ("ee", "i"), ("ii", "i"), ("oo", "u"), ("uu", "u"), ("zh", "l"),
             ("th", "t"), ("dh", "d"), ("kh", "k"), ("gh", "g"), ("bh", "b"), ("ph", "f"),
             ("sh", "s"), ("w", "v"), ("y", "i"), ("ai", "i"), ("ei", "i")]
# the conservative-but-wider fold, used only for "fuzzy" spelling matches (voiced/unvoiced, long/short)
_LOOSE = [("ae", "e"), ("d", "t"), ("g", "k"), ("b", "p"), ("j", "c"), ("e", "i"), ("o", "u"), ("h", "")]


def norm_title(s: str) -> str:
    s = unicodedata.normalize("NFKC", s or "").lower()
    s = _PAREN_RE.sub(" ", s)
    s = _FROM_RE.sub(" ", s)
    s = _FEAT_RE.sub(" ", s)
    s = re.sub(r"[^\w\s]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def phonetic_key(title: str) -> str:
    t = norm_title(_LANG_SUFFIX_RE.sub("", title or ""))
    t = t.replace(" ", "")
    for a, b in _PHONETIC:
        t = t.replace(a, b)
    return re.sub(r"(.)\1+", r"\1", t)


def loose_key(title: str) -> str:
    t = phonetic_key(title)
    for a, b in _LOOSE:
        t = t.replace(a, b)
    return re.sub(r"(.)\1+", r"\1", t)


_FROM_BRACKET = re.compile(r"[\(\[]\s*from\b[^\)\]]*[\)\]]", re.I)
_FROM_DASH = re.compile(r"\s+[-–—]\s+from\b.*$", re.I)
_FROM_TAG = re.compile(r"[\(\[]\s*from\s+[\"'“‘”’]*([^\)\]\"“”]+?)[\"'”’]*\s*[\)\]]|"
                       r"\s[-–—]\s+from\s+[\"'“‘”’]*(.+?)[\"'”’]*\s*$", re.I)
_OST = re.compile(r"[\(\[]?\s*(original\s+(motion\s+picture\s+|music\s+picture\s+)?(sound\s*track|score|"
                  r"background\s+score)|\bost\b)\s*[\)\]]?", re.I)
_SUBTITLE = re.compile(r"\s+[-–—:|]\s+.*$")
_VERSION = re.compile(
    r"\b(remix|reprise|unplugged|lo-?fi|slowed|reverb|sped(?:\s+up)?|speed\s+up|acoustic|instrumental|karaoke|"
    r"cover|live|female|male|reloaded|extended|remaster(?:ed)?|mashup|duet|sad|version|revival|"
    r"track by track|commentary|interview|demo|nightcore|8d)\b", re.I)
# matcher-v2 additions: more words that make a different recording
_VERSION_V2 = re.compile(
    r"\b(radio\s+edit|edit|edition|mix|piano|orchestral|medley|rework|flip|bootleg|stripped|"
    r"violin|flute|rap|chill\s+trap|trap|promo|teaser|trailer)\b", re.I)
_BGM = re.compile(r"\b(background\s+score|bgm)\b", re.I)
_LANG_TAG = re.compile(r"[\(\[\-–]\s*(tamil|telugu|hindi|malayalam|kannada)\b", re.I)
_CANON = {"sped": "sped up", "speed up": "sped up", "lofi": "lo fi", "remastered": "remaster",
          "radio edit": "edit", "edition": "edit"}
_LANG_CODE = {"ta": "tamil", "te": "telugu", "hi": "hindi", "ml": "malayalam", "kn": "kannada"}
_ARTIST_SPLIT = re.compile(r"\s*(?:[,;/&•·|]|\bfeat\.?|\bft\.?|\bfeaturing\b|\bwith\b)\s*|\s+(?:x|and)\s+", re.I)
_FEAT_NAMES = re.compile(r"[\(\[]?\b(?:feat\.?|ft\.?|featuring|with)\s+([^\)\]]+)[\)\]]?", re.I)
_GENERIC = {"various artists", "unknown artist", "unknown", "soundtrack", "original soundtrack", "traditional",
            "anonymous", "artist", "va", "various"}
_FILM_NOISE = re.compile(r"\b(original\s+(motion\s+picture\s+|music\s+picture\s+)?(sound\s*track|score)|ost|"
                         r"soundtrack|single|ep|deluxe|edition|tamil|telugu|hindi|malayalam|kannada|"
                         r"extended\s+version|special|hits|songs?)\b", re.I)


def versions(title: str, rules=ALL_RULES) -> frozenset:
    """Version words: a remix / sped-up / live cut is a different song."""
    s = unicodedata.normalize("NFKC", title or "")
    found = _VERSION.findall(s)
    if "versions" in rules:
        found += [m if isinstance(m, str) else m[0] for m in _VERSION_V2.findall(s)]
    out = set()
    for w in found:
        w = re.sub(r"[\s-]+", " ", w.lower()).strip()
        out.add(_CANON.get(w, w))
    return frozenset(out)


def clean_title(title: str) -> str:
    """The song's own name: '(From "DC")', 'Original Motion Picture Soundtrack'
    and ' - The Melting Point of Love' dropped, then norm_title."""
    s = unicodedata.normalize("NFKC", title or "")
    s = _FROM_BRACKET.sub(" ", s)
    s = _FROM_DASH.sub(" ", s)
    s = _OST.sub(" ", s)
    s = _SUBTITLE.sub(" ", s) if _SUBTITLE.search(s) and _SUBTITLE.sub("", s).strip() else s
    return norm_title(s)


def full_title(title: str) -> str:
    """clean_title but a ' - subtitle' stays part of the name."""
    s = unicodedata.normalize("NFKC", title or "")
    return norm_title(_OST.sub(" ", _FROM_DASH.sub(" ", _FROM_BRACKET.sub(" ", s))))


def lang_tag(*texts, code: str = "") -> str:
    """'tamil' / 'telugu' … when a title, album or language column says which."""
    for t in texts:
        m = _LANG_TAG.search(unicodedata.normalize("NFKC", t or ""))
        if m:
            return m.group(1).lower()
    return _LANG_CODE.get((code or "").strip().lower()[:2], "")


# ── names ────────────────────────────────────────────────────────────────────
def _ratio(a: str, b: str) -> float:
    """2*LCS/(len a + len b): the same number as rapidfuzz.fuzz.ratio / 100."""
    if a == b:
        return 1.0
    if not a or not b:
        return 0.0
    prev = [0] * (len(b) + 1)
    for ca in a:
        cur = [0]
        for j, cb in enumerate(b, 1):
            cur.append(prev[j - 1] + 1 if ca == cb else max(prev[j], cur[j - 1]))
        prev = cur
    return 2.0 * prev[-1] / (len(a) + len(b))


def split_names(credit: str) -> list[str]:
    """'Hiphop Tamizha • Kaushik Krish', 'A, B & C feat. D' → normalised names."""
    out = []
    for p in _ARTIST_SPLIT.split(unicodedata.normalize("NFKC", credit or "")):
        n = norm_title(re.sub(r"\.\s*", "", p))
        if n and n not in out:
            out.append(n)
    return out


def _fold(tok: str) -> str:
    for a, b in _PHONETIC:
        tok = tok.replace(a, b)
    return re.sub(r"(.)\1+", r"\1", tok)


_HONOR = {"dr", "mr", "mrs", "ms", "sri", "shri", "smt", "pt", "pandit", "late", "prof", "the"}


def _sig(part: str):
    """(name tokens without initials/honorifics, folded; initials) of one credited name."""
    raw = unicodedata.normalize("NFKC", part or "").replace(".", " ")
    toks, ini = [], set()
    for t in re.findall(r"\w+", raw):
        low = t.lower()
        if low in _HONOR:
            continue
        if len(low) == 1 or (len(low) <= 3 and t.isupper() and len(t) <= 3):
            ini.update(low)
            continue
        toks.append(_fold(low))
    return tuple(toks), frozenset(ini)


def _name_pairs_same(x: str, y: str, rawx: str, rawy: str) -> bool:
    """Two spellings of one name, the wide way: 'G V Prakash' = 'G V Prakash
    Kumar', 'SS Thaman' = 'Thaman S', 'Sirkazhi Govindarajan' = 'Dr Seerkazhi S
    Govindarajan'. A single first name ('Anirudh') is never enough."""
    if x == y or _ratio(x, y) >= ARTIST_SAME:
        return True
    tx, ix = _sig(rawx)
    ty, iy = _sig(rawy)
    if not tx or not ty:
        return False
    if ix and iy and not (ix <= iy or iy <= ix):
        return False
    if set(tx) == set(ty) and sum(len(t) for t in tx) >= 4:
        return True
    short, long_ = (tx, ty) if len(tx) <= len(ty) else (ty, tx)
    sini = ix if short is tx else iy
    if len(short) < len(long_) and long_[:len(short)] == short and (len(short) >= 2 or sini):
        return True
    return _ratio(" ".join(tx), " ".join(ty)) >= ARTIST_SAME


def _credit_parts(credit: str) -> list[tuple[str, str]]:
    """[(normalised, raw part)] of a credit, generic names dropped."""
    out, seen = [], set()
    for p in _ARTIST_SPLIT.split(unicodedata.normalize("NFKC", credit or "")):
        n = norm_title(re.sub(r"\.\s*", "", p))
        if n and n not in seen and n not in _GENERIC:
            seen.add(n)
            out.append((n, p))
    return out


def _share(a_parts, b_parts, wide: bool) -> bool:
    for x, rx in a_parts:
        for y, ry in b_parts:
            if x == y or _ratio(x, y) >= ARTIST_SAME:
                return True
            if wide and _name_pairs_same(x, y, rx, ry):
                return True
    return False


def share_artist(a: str, b: str, wide: bool = False) -> bool:
    """At least one name in common (two spellings of one name count)."""
    return _share(_credit_parts(a), _credit_parts(b), wide)


# ── films ────────────────────────────────────────────────────────────────────
def film_tag(title: str) -> str:
    """The film named inside a title: '(From "Kaaki Sattai")' / ' - From "Petta"'."""
    m = _FROM_TAG.search(unicodedata.normalize("NFKC", title or ""))
    return ((m.group(1) or m.group(2)) if m else "") or ""


def _film_key(text: str) -> str:
    s = _OST.sub(" ", unicodedata.normalize("NFKC", text or ""))
    return phonetic_key(_FILM_NOISE.sub(" ", _PAREN_RE.sub(" ", s)))


def _is_marked(text: str) -> bool:
    """An album / film string that is certainly a film's: carries an OST marker."""
    return bool(_OST.search(text or "")) or bool(_FROM_TAG.search(text or ""))


def films_of(title: str, album: str, film: str, own_title_key: str) -> tuple[frozenset, bool]:
    """(folded film names, certain) a song or incoming row points at. An album
    that is only the song's own name (a single) is not a film."""
    keys, certain = set(), False
    for text, mark in ((film_tag(title), True), (film_tag(album), True), (film, False), (album, False)):
        if not text or not text.strip():
            continue
        k = _film_key(text)
        marked = mark or _is_marked(text)
        if not k or len(k) < 2 or (k == own_title_key and not marked):     # a single named like its song is no film
            continue
        keys.add(k)
        if marked:
            certain = True
    return frozenset(keys), certain


def _films_agree(a: frozenset, b: frozenset) -> bool:
    for x in a:
        for y in b:
            if x == y or (min(len(x), len(y)) >= 5 and (x.startswith(y) or y.startswith(x))):
                return True
            if min(len(x), len(y)) >= 6 and _ratio(x, y) >= FILM_SAME:       # 'vinnathaandi' / 'vinnaithaandi'
                return True
    return False


# ── the index ────────────────────────────────────────────────────────────────
@dataclass
class Match:
    song: dict
    confidence: str          # isrc | strong | fuzzy
    rule: str                # which rule fired (shown in review files)
    delta: float | None = None   # |length difference| in seconds when both are known

    def __iter__(self):      # (song, confidence) unpacking for callers
        yield self.song
        yield self.confidence


_RANK = {"isrc": 0, "strong": 1, "fuzzy": 2}


class _Profile:
    __slots__ = ("song", "versions", "lang", "artist", "roles", "solo", "films", "certain", "title_key", "native", "bgm")

    def __init__(self, song: dict, rules):
        self.song = song
        title = song.get("title") or ""
        self.versions = versions(title, rules)
        self.lang = lang_tag(title, song.get("album") or "")      # written tags only: the language column can be wrong
        self.title_key = phonetic_key(clean_title(title))
        credit = song.get("artist") or ""
        if "names" in rules:
            credit += " ; " + " ; ".join(m.group(1) for m in _FEAT_NAMES.finditer(title))
        self.artist = _credit_parts(credit)
        self.solo = len(_credit_parts(song.get("composer") or "")) <= 1     # one composer: a film score, not a writers' list
        self.roles = []
        for k in ("album_artist", "composer", "lyricist"):
            self.roles += _credit_parts(song.get(k) or "")
        self.films, self.certain = films_of(title, song.get("album") or "", song.get("film") or "", self.title_key)
        self.native = (song.get("title_native") or "").strip()
        self.bgm = bool(_BGM.search(title))


class Index:
    """Library songs by clean title, its phonetic key and its loose key."""

    def __init__(self, library: list[dict], rules=ALL_RULES):
        self.rules = frozenset(rules)
        self.by_key: dict[str, list[dict]] = {}
        self.by_loose: dict[str, list[dict]] = {}
        self.by_isrc: dict[str, list[dict]] = {}
        self._prof: dict[str, _Profile] = {}
        for s in library:
            t = clean_title(s.get("title") or "")
            if not t:
                continue
            for k in {t, "~" + phonetic_key(t)}:
                self.by_key.setdefault(k, []).append(s)
            self.by_loose.setdefault(loose_key(t), []).append(s)
            if "spell" in self.rules:
                self.by_key.setdefault("f:" + phonetic_key(full_title(s["title"])), []).append(s)
            if s.get("isrc"):
                self.by_isrc.setdefault(_isrc(s["isrc"]), []).append(s)
            if s.get("title_native"):
                self.by_key.setdefault("n:" + norm_title(s["title_native"]), []).append(s)
        self.ids = {s["id"] for s in library}

    def _profile(self, s: dict) -> _Profile:
        p = self._prof.get(s["id"])
        if p is None:
            p = self._prof[s["id"]] = _Profile(s, self.rules)
        return p

    # ── candidates ──────────────────────────────────────────────────────────
    def _candidates(self, title: str):
        t = clean_title(title)
        if not t:
            return []
        out, seen = [], set()
        keys = [(t, "title"), ("~" + phonetic_key(t), "title")]
        if "spell" in self.rules:       # 'Dude – Orchestral Suite' = 'Dude Orchestral Suite'
            keys.append(("f:" + phonetic_key(full_title(title)), "title"))
        if "n:" + norm_title(title) in self.by_key:
            keys.append(("n:" + norm_title(title), "native"))
        for k, how in keys:
            for s in self.by_key.get(k, []):
                if s["id"] not in seen:
                    seen.add(s["id"])
                    out.append((s, "exact" if how == "title" else "native"))
        if "spell" in self.rules:
            for s in self.by_loose.get(loose_key(t), []):
                if s["id"] not in seen:
                    seen.add(s["id"])
                    out.append((s, "loose"))
        return out

    # ── the decision ────────────────────────────────────────────────────────
    def _judge(self, q: dict, p: _Profile, how: str, slack: float, rules) -> Match | None:
        s = p.song
        if q["versions"] != p.versions:
            return None
        if "versions" in rules and p.bgm and not q["bgm"]:      # the library's own "(Background Score)" is a score, not the song
            return None
        if "guard" in rules and q["lang"] and p.lang and q["lang"] != p.lang:
            return None
        ld = s.get("duration")
        d = abs(float(ld) - float(q["dur"])) if (q["dur"] and ld) else None
        art = _share(q["artist"], p.artist, "names" in rules)
        role = "role" in rules and bool(p.roles) and _share(q["artist"], p.roles, "names" in rules)
        agree = "film" in rules and _films_agree(q["films"], p.films)
        differ = "guard" in rules and bool(q["films"]) and bool(p.films) and not _films_agree(q["films"], p.films)
        conflict = differ and (q["certain"] or p.certain) and not art       # no artist, another film: another song
        # same credit, another film: doubtful when the names matched only the wide way ('G. V. Prakash' / '… Kumar')
        other_film = (differ and (q["certain"] or p.certain) and art
                      and not _share(q["artist"], p.artist, False))
        loose = how == "loose"
        # a spelling that only the loose fold sees must have a credited artist AND the same film or length
        if loose and not (art or role) and not agree:
            return None

        def cap(base: float, wide: bool) -> float:
            if not wide or "len" not in rules:
                return base
            top = min(MAX_SLACK_S, MAX_SLACK_REL * float(ld or q["dur"] or 0))
            return max(base, top)

        if art:
            if other_film:
                return Match(s, "fuzzy", "artist, other film", d) if d is None or d <= cap(slack, True) else None
            if d is None or d <= slack:
                return Match(s, "fuzzy" if loose else "strong", "artist+spelling" if loose else "artist", d)
            if d <= cap(slack, True):
                return Match(s, "fuzzy", "artist+length", d)
            return None
        if role and not agree and not p.solo:
            role = False    # 'Lana Del Rey; Justin Parker' as composers: a cover of her song credits her too
        if not (role or agree):
            return None
        if role and agree and not p.solo:       # a writers' list plus the album: probably, not surely
            role_strong = False
        else:
            role_strong = True
        if conflict:
            return None
        if loose and not (agree or role):
            return None
        if d is not None and d > cap(slack, True):
            return None
        near = d is None or d <= slack
        if agree and role and near:
            if loose or not role_strong:
                return Match(s, "fuzzy", "composer+film" + ("+spelling" if loose else ", several composers"), d)
            return Match(s, "strong", "composer+film", d)
        if agree and d is not None and d <= AGREE_SLACK_S and not loose:
            return Match(s, "strong", "film+length", d)
        if role and near:
            return Match(s, "fuzzy", "composer" + ("+spelling" if loose else ""), d)
        if agree and near:
            return Match(s, "fuzzy", "film" + ("+spelling" if loose else ""), d)
        return Match(s, "fuzzy", ("composer" if role else "film") + "+length", d)

    def match(self, title: str, artist: str, duration: float | None = None, slack: float = STRICT_SLACK_S,
              album: str | None = None, isrc: str | None = None) -> Match | None:
        rules = self.rules
        if isrc and _isrc(isrc) in self.by_isrc:
            hits = self.by_isrc[_isrc(isrc)]
            best = min(hits, key=lambda s: abs(float(s.get("duration") or 0) - float(duration or 0))) \
                if duration else hits[0]
            return Match(best, "isrc", "isrc")
        cands = self._candidates(title)
        if not cands:
            return None
        ct = clean_title(title)
        tk = phonetic_key(ct)
        credit = artist or ""
        if "names" in rules:
            credit += " ; " + " ; ".join(m.group(1) for m in _FEAT_NAMES.finditer(title or ""))
        films, certain = films_of(title, "", "", tk)
        if album:
            f2, c2 = films_of("", album, "", tk)
            films, certain = films | f2, certain or c2
        q = {"versions": versions(title, rules), "bgm": bool(_BGM.search(title or "")), "lang": lang_tag(title, album or ""), "dur": duration,
             "artist": _credit_parts(credit), "films": films, "certain": certain}
        hits: list[Match] = []
        for s, how in cands:
            prof = self._profile(s)
            m = self._judge(q, prof, how, float(slack), rules)
            if m is not None:
                hits.append((m, "film" in rules and _films_agree(q["films"], prof.films)))
        if not hits:
            return None
        return min(hits, key=lambda h: self._order(h[0], h[1], duration, "tie" in rules))[0]

    @staticmethod
    def _order(m: Match, film_ok: bool, duration, tie: bool):
        s = m.song
        if not tie:     # the old tie-break: closest length, else the longest
            return (0, abs(float(s.get("duration") or 0) - float(duration)) if duration
                    else -float(s.get("duration") or 0), str(s["id"]))
        # several songs share the title: the surer rule, then the film that agrees, then the closest length
        by_rule = {"artist": 0, "composer+film": 0, "film+length": 1, "composer": 2, "film": 2,
                   "artist+length": 3}.get(m.rule, 4)
        dist = abs(float(s.get("duration") or 0) - float(duration)) if duration and s.get("duration") else 99999.0
        return (_RANK[m.confidence], not film_ok, by_rule, dist, -float(s.get("duration") or 0), str(s["id"]))

    def find(self, title: str, artist: str, duration: float | None, slack: float = STRICT_SLACK_S,
             album: str | None = None, fuzzy: bool | None = None, isrc: str | None = None) -> dict | None:
        """The old call: the library song, or None. Strong / isrc matches only
        unless fuzzy=True (or FUZZY_IN_FIND)."""
        m = self.match(title, artist, duration, slack, album=album, isrc=isrc)
        if m is None:
            return None
        if m.confidence == "fuzzy" and not (FUZZY_IN_FIND if fuzzy is None else fuzzy):
            return None
        return m.song


def _isrc(v) -> str:
    return "".join(ch for ch in str(v or "").upper() if ch.isalnum())
