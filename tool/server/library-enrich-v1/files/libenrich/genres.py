"""Last.fm / MusicBrainz tags -> a small clean genre vocabulary.

Only tags that map to a genre survive (a whitelist), so junk ("seen live", "favorites", "2010s", artist and
composer names, places, languages) is dropped by default. Mood words (sad, chill, romantic ...) are dropped on
purpose: moods belong to the mood labeller, not to genre. Language tags (tamil, hindi ...) are dropped too:
the catalog already has a `language` column.
"""
import re
import unicodedata

# synonym -> vocabulary genre
_MAP = {
    "pop": "pop", "dance-pop": "pop", "dance pop": "pop", "teen pop": "pop", "pop rap": "hip hop",
    "country pop": "pop", "alt-pop": "pop", "indie pop": "indie", "dream pop": "indie", "chamber pop": "indie",
    "electropop": "synth-pop", "synthpop": "synth-pop", "synth-pop": "synth-pop", "synth pop": "synth-pop",
    "rock": "rock", "pop rock": "rock", "soft rock": "rock", "country rock": "rock", "classic rock": "rock",
    "hard rock": "rock", "space rock": "rock", "psychedelic rock": "psychedelic", "psychedelic": "psychedelic",
    "psychedelic pop": "psychedelic", "neo-psychedelia": "psychedelic",
    "alternative": "alternative", "alternative rock": "alternative", "alt rock": "alternative",
    "alternative rnb": "r&b", "indie": "indie", "indie rock": "indie", "indie folk": "folk",
    "hip-hop": "hip hop", "hip hop": "hip hop", "hiphop": "hip hop", "rap": "hip hop", "trap": "trap",
    "rnb": "r&b", "r&b": "r&b", "r and b": "r&b", "rhythm and blues": "r&b", "prog-rnb": "r&b",
    "soul": "soul", "neo-soul": "soul", "neo soul": "soul", "funk": "funk", "disco": "disco", "nu-disco": "disco",
    "electronic": "electronic", "electronica": "electronic", "electro": "electronic", "dubstep": "electronic",
    "downtempo": "electronic", "trip-hop": "trip-hop", "trip hop": "trip-hop", "dance": "dance",
    "edm": "edm", "house": "house", "electro house": "house", "deep house": "house", "techno": "techno",
    "ambient": "ambient", "ambient pop": "ambient", "chillout": "ambient", "lo-fi": "lo-fi", "lofi": "lo-fi",
    "jazz": "jazz", "blues": "blues", "classical": "classical", "orchestral": "classical",
    "carnatic": "carnatic", "carnatic music": "carnatic", "indian classical": "classical",
    "hindustani": "hindustani", "hindustani classical": "hindustani",
    "folk": "folk", "singer-songwriter": "singer-songwriter", "singer songwriter": "singer-songwriter",
    "americana": "country", "country": "country", "contemporary country": "country",
    "metal": "metal", "heavy metal": "metal", "punk": "punk", "pop punk": "punk", "post-punk": "punk",
    "new wave": "new wave", "reggae": "reggae", "latin": "latin", "latin pop": "latin", "reggaeton": "latin",
    "k-pop": "k-pop", "kpop": "k-pop", "korean pop": "k-pop",
    "soundtrack": "soundtrack", "soundtracks": "soundtrack", "ost": "soundtrack", "film": "soundtrack",
    "filmi": "soundtrack", "indian film": "soundtrack", "film music": "soundtrack", "score": "soundtrack",
    "kollywood": "soundtrack", "bollywood": "soundtrack", "tollywood": "soundtrack", "mollywood": "soundtrack",
    "devotional": "devotional", "bhajan": "devotional", "gospel": "devotional", "ghazal": "ghazal",
    "qawwali": "qawwali", "sufi": "qawwali", "kuthu": "kuthu", "gaana": "kuthu", "melody": "melody",
    "ballad": "ballad", "acoustic": "acoustic", "instrumental": "instrumental",
}
VOCAB = sorted(set(_MAP.values()))
MIN_SCORE = 20.0        # on a 0..100 scale (Last.fm tag count x source weight)
MAX_GENRES = 3


def _key(tag: str) -> str:
    t = unicodedata.normalize("NFKC", str(tag)).casefold().strip()
    return re.sub(r"\s+", " ", t)


def _plain(text: str) -> str:
    return "".join(ch for ch in unicodedata.normalize("NFKC", str(text or "")).casefold()
                   if ch.isalnum() or unicodedata.category(ch).startswith("M"))


def _name_words(names) -> set:
    """Normalised artist / composer names and their words, so an artist-name tag is never a genre."""
    out = set()
    for n in names:
        for part in re.split(r"[;,&/]| feat\.? | ft\.? | and ", str(n or "")):
            p = _plain(part)
            if len(p) > 2:
                out.add(p)
    return out


def normalise(sources, names=()) -> list:
    """sources: [(tags {name: count}, weight)]; counts are scaled per source so the biggest is 100.
    Returns up to 3 vocabulary genres, strongest first. `names`: artist / composer names of the song."""
    people = _name_words(names)
    score: dict = {}
    for tags, weight in sources:
        if not tags:
            continue
        top = max(float(v) for v in tags.values()) or 1.0
        for name, count in tags.items():
            if _plain(name) in people:
                continue
            g = _MAP.get(_key(name))
            if not g:
                continue
            score[g] = score.get(g, 0.0) + (float(count) / top) * 100.0 * weight
    ranked = sorted(score.items(), key=lambda kv: (-kv[1], kv[0]))
    if not ranked:
        return []
    best = ranked[0][1]
    return [g for g, s in ranked if s >= MIN_SCORE and s >= 0.25 * best][:MAX_GENRES]
