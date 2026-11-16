"""
tgfetch/titles.py  (server-fixes-v1)
────────────────────────────────────
YouTube / YouTube Music titles → the song's own name, for searching the music
bot. YouTube is only a list of names: nothing else is ever asked of it.

Rules (docs/TODO.md, "YouTube playlists via the bot", section 3), in order:
  1. NFKC; '｜' → '|', '–'/'—' → '-'; emoji and symbols dropped; spaces collapsed.
  2. The channel is the artist only for YouTube Music tracks (ATV / OMV) or an
     auto-generated "- Topic" channel; labels (Sony Music South, Think Music,
     T-Series, Lahari, Saregama, …) never are.
  3. '(From "X")', '[From X]', '- From "X"', 'X Tamil Movie Songs', a year
     → X is the film hint, not part of the title.
  4. Noise (Official Video, Lyric Video, Video Song, Full Song, Audio, HD, 4K,
     With Lyrics, Visualizer, Teaser, …) is dropped; version words that change
     the song (Remix, Reprise, Unplugged, Live, Instrumental, Female Version,
     Slowed, Lofi, Karaoke, Cover, Sped Up) are kept.
  5. Split on '|' and ' - ': a part that had a title word ("Video Song") is the
     title; a known artist (from the library) is an artist; a film part is the
     film; the rest are other possible titles (alts), tried after the first.
  6. 'feat. X', 'song by X' → artists.
  7. Empty, only noise, or longer than 120 characters → unreadable (no search).
The raw title is always kept for display.
"""

import re
import unicodedata

from rapidfuzz import fuzz

from navivibe.catalog.enrich import norm_title

MAX_LEN = 120
_DASHES = str.maketrans({"｜": "|", "│": "|", "–": "-", "—": "-", "‐": "-", "‒": "-", "：": ":"})
LABELS = re.compile(
    r"\b(sony music|think music|t-series|tseries|lahari|saregama|orange music|ap international|junglee music|"
    r"star music|music master|bayshore|movie world|divo|u1 records|sun ?tv|zee music|tips (official|music)|"
    r"aditya music|mango music|muzik ?247|trend music|sun music|vijay television|wonderwall|"
    r"records|entertainment|productions|films|studios|movies)\b", re.I)
_TOPIC = re.compile(r"\s*-\s*topic$|\s*vevo$", re.I)
_FROM = re.compile(r"[\(\[]\s*from\s+[\"'“‘]?([^\)\]\"'”’]+)[\"'”’]?\s*[\)\]]|\s-\s*from\s+[\"'“‘]([^\"'”’]+)[\"'”’]",
                   re.I)
_OST = re.compile(r"[\(\[]?\s*original\s+(motion\s+picture\s+)?(sound\s*track|score|background\s+score)\s*[\)\]]?",
                  re.I)
_YEAR = re.compile(r"[\(\[]?\b(19[4-9]\d|20[0-4]\d)\b[\)\]]?")
_FILM_WORDS = re.compile(r"\b(tamil|telugu|hindi|malayalam|kannada)?\s*(movie|film)\s*(songs?|video songs?)?\b|"
                         r"\bsongs\b\s*$", re.I)
_TITLE_WORDS = re.compile(r"\b(video\s+songs?|full\s+songs?|lyric(al)?(\s+video)?|official\s+(music\s+)?video|"
                          r"audio\s+songs?|full\s+video(\s+songs?)?|\bsong\b|\bvideo\b)", re.I)
_NOISE = re.compile(
    r"\b(official\s+(music\s+|lyric(al)?\s+|full\s+)?video|lyric(al)?\s+video|lyric(al)?|lyrics|video\s+songs?|"
    r"full\s+video\s+songs?|full\s+song\s+video|full\s+video|full\s+songs?|audio\s+songs?|audio|video|"
    r"songs?|official|hd|4k|hq|1080p|720p|with\s+(tamil\s+|english\s+)?lyrics|visuali[sz]er|music\s+video|"
    r"promo|teaser|trailer|version\s+\d+|"
    r"(tamil|telugu|hindi|malayalam|kannada|english)(?=\s+(lyric|movie|film|video|song|full|audio))|"
    r"full(?=\s+(song|video|audio)))\b|"
    r"[\(\[]\s*(tamil|telugu|hindi|malayalam|kannada|english|hd|4k|hq|new|official|audio|video|lyrics?)\s*[\)\]]|"
    r"\b(new|hd)\s*$",
    re.I)
_FEAT = re.compile(r"\s*[\(\[]?\b(?:feat\.?|ft\.?|featuring)\s+([^\)\]|]+)[\)\]]?", re.I)
_SONG_BY = re.compile(r"\bsong\s+by\s+(.+)$", re.I)
_VERSION_ONLY = re.compile(r"\b(remix|reprise|unplugged|lo-?fi|slowed|reverb|sped\s+up|speed\s+up|acoustic|"
                           r"instrumental|karaoke|cover|live|female|male|version|extended|mashup|duet|sad)\b|[+&()\[\]]",
                           re.I)
_LOOSE_FROM = re.compile(r"\s+from\s+([^\W\d][\w\s]{1,40})$", re.I)
_PREFIX = re.compile(r"^\s*(official|exclusive|new)\s*[:\-]\s*", re.I)
_EMPTY_BRACKETS = re.compile(r"[\(\[]\s*[\)\]]")
_TRAIL = re.compile(r"^[\s\-:|,.]+|[\s\-:|,.]+$")


def _symbols_out(s: str) -> str:
    return "".join(ch for ch in s if not unicodedata.category(ch).startswith("S") or ch in "&+'|")


def _tidy(s: str) -> str:
    s = _EMPTY_BRACKETS.sub(" ", s)
    s = re.sub(r"\s+", " ", s)
    return _TRAIL.sub("", s).strip()


def _latin(s: str) -> bool:
    letters = [c for c in s if c.isalpha()]
    return bool(letters) and sum(c.isascii() for c in letters) / len(letters) > 0.8


def is_label(name: str) -> bool:
    return bool(LABELS.search(name or ""))


def channel_artist(name: str) -> str:
    return _TOPIC.sub("", name or "").strip()


class Known:
    """Artist and film names the library already has (normalised)."""

    def __init__(self, artists=(), films=()):
        self.artists = {a for a in artists if a}
        self.films = {f for f in films if f}

    @classmethod
    def from_library(cls, library: list[dict]) -> "Known":
        from tgfetch.library_sweep import split_names
        artists, films = set(), set()
        for s in library:
            artists.update(n for n in split_names(s.get("artist") or "") if len(n) > 2)
            album = s.get("album") or ""
            for m in _FROM.finditer(album + " " + (s.get("title") or "")):
                films.add(norm_title(m.group(1) or m.group(2) or ""))
            films.add(norm_title(_OST.sub(" ", album)))
        return cls(artists, films)

    def is_artist(self, text: str) -> bool:
        n = norm_title(re.sub(r"\.\s*", "", text or ""))
        if not n or len(n) < 3:
            return False
        if n in self.artists:
            return True
        if not hasattr(self, "_squashed"):
            self._squashed = {a.replace(" ", "") for a in self.artists}
        if len(n) > 5 and n.replace(" ", "") in self._squashed:     # 'A R Rahman' / 'AR Rahman'
            return True
        return len(n) > 5 and any(abs(len(a) - len(n)) <= 3 and fuzz.ratio(a, n) >= 90 for a in self.artists)

    def is_film(self, text: str) -> bool:
        n = norm_title(text)
        return bool(n) and n in self.films


def _split_people(s: str) -> list[str]:
    return [p.strip() for p in re.split(r"\s*(?:,|&|\band\b|\bx\b)\s*", s or "") if p.strip()]


def clean(raw: str, artists: list[str] | None = None, video_type: str = "", album: str = "",
          known: Known | None = None) -> dict:
    """{'raw', 'title', 'alts', 'artists', 'film', 'unreadable'} for one YouTube item.
    `artists` are ytmusicapi's artist names (the channel for plain videos)."""
    known = known or Known()
    out = {"raw": raw or "", "title": "", "alts": [], "artists": [], "film": "", "unreadable": False}
    s = _symbols_out(unicodedata.normalize("NFKC", raw or "").translate(_DASHES))
    s = _PREFIX.sub("", re.sub(r"\s+", " ", s)).strip()
    film = ""
    m = _FROM.search(s)
    if m:
        film = (m.group(1) or m.group(2) or "").strip()
        s = _FROM.sub(" ", s)
    s = _OST.sub(" ", s)
    people: list[str] = []
    for fm in _FEAT.finditer(s):
        people += _split_people(fm.group(1))
    s = _FEAT.sub(" ", s)
    sb = _SONG_BY.search(s)
    if sb:
        people += _split_people(sb.group(1))
        s = s[:sb.start()] + " song"

    if "(" not in s and "[" not in s and "|" not in s:
        fr = _LOOSE_FROM.search(s)          # 'nimirnthu nil from saroja'
        if fr and not film and len(s[:fr.start()].split()) >= 2:
            film = fr.group(1).strip()
            s = s[:fr.start()]

    # Parts: '|' first, then ' - ' inside each. A part that is only noise but
    # says "Video Song" marks the part beside it as the title ('Rasaali - Video Song').
    titles, title_signal = [], False
    for seg_no, seg in enumerate(s.split("|")):
        pieces = [p for p in re.split(r"\s+-\s+|\s+-$|^-\s+", seg) if p.strip()]
        seg_titles, seg_signal = [], False
        for p in pieces:
            has_title = bool(_TITLE_WORDS.search(p))
            has_film = bool(_FILM_WORDS.search(p)) or bool(_YEAR.search(p))
            name = _tidy(_NOISE.sub(" ", _YEAR.sub(" ", p)))
            if not name:
                seg_signal = seg_signal or has_title
                continue
            if has_film and not (has_title and not re.search(r"movie|film", p, re.I)):
                film = film or _tidy(_FILM_WORDS.sub(" ", name)) or name
                continue
            if is_label(name):
                continue
            if "," in name or known.is_artist(name):
                if known.is_artist(name) or all(known.is_artist(x) for x in _split_people(name)):
                    people += _split_people(name)
                continue          # a list of actors / crew: neither title nor artist we can trust
            if known.is_film(name) and (titles or seg_titles):
                film = film or name
                continue
            if seg_titles and not _VERSION_ONLY.sub("", name).strip():
                prev, flag = seg_titles[-1]          # 'Kaavaalaa - Remix': the version stays on the title
                seg_titles[-1] = (f"{prev} {name}", flag or has_title)
                continue
            seg_titles.append((name, has_title))
        if not seg_titles:
            continue
        flagged = [n for n, t in seg_titles if t]
        if flagged or (seg_signal and len(seg_titles) == 1):
            pick = flagged[0] if flagged else seg_titles[0][0]
            if not title_signal:
                titles.insert(0, pick)
                title_signal = True
            else:
                titles.append(pick)
            titles += [n for n, _ in seg_titles if n != pick]
        elif seg_no == 0 and len(seg_titles) > 1:
            # 'Petta - Ilamai Thirumbudhe', 'Uyirum Neeye - Pavithra': the longer
            # part is more often the song; a known film name never is.
            ranked = sorted((n for n, _ in seg_titles), key=lambda t: (_latin(t), len(t)), reverse=True)
            if known.is_film(ranked[0]) and len(ranked) > 1:
                film = film or ranked[0]
                ranked = ranked[1:]
            titles += ranked
        else:
            titles += [n for n, _ in seg_titles]
    if titles:
        first, rest = titles[0], titles[1:]
        if not title_signal and not _latin(first):
            latin = [t for t in rest if _latin(t)]
            if latin:                                  # the bot is searched in Latin script
                first, rest = latin[0], [first] + [t for t in rest if t != latin[0]]
        out["title"] = first
        out["alts"] = [] if title_signal else [t for t in rest if len(t.split()) <= 6][:2]
        if title_signal and not film and rest:
            film = rest[0]          # 'Song Video Song | Film | actors…': the part after the song is the film
    # Artists: the YouTube Music credit for music tracks / Topic channels; the
    # uploader of a plain video only when the library knows the name.
    vt = (video_type or "").upper()
    music_track = vt.endswith("ATV") or vt.endswith("OMV") or any(_TOPIC.search(a or "") for a in artists or [])
    names = []
    for a in artists or []:
        a = channel_artist(a)
        if not a or is_label(a):
            continue
        if music_track or known.is_artist(a):
            names.append(a)
    for p in people:
        p = _tidy(_NOISE.sub(" ", channel_artist(p)))
        if p and not is_label(p) and p.lower() not in (n.lower() for n in names):
            names.append(p)
    out["artists"] = names
    if not film and album:
        a = _tidy(_OST.sub(" ", album))
        if norm_title(a) and norm_title(a) != norm_title(out["title"]):
            film = a
    out["film"] = film
    t = out["title"]
    if not t or not norm_title(t) or len(t) > MAX_LEN:
        out["unreadable"] = True
        out["title"] = ""
        out["alts"] = []
    return out
