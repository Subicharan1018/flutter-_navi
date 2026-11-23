"""Choose the N library songs that make the best CALIBRATION set for Spotify's audio features.

Why: only a few hundred songs can go through the free playlist-transfer route. Their true Spotify energy /
valence / danceability train a model that predicts the same numbers for the rest of the library from the audio
embedding, so the sample has to cover the whole space the model must predict, not a random corner of it.

Rules (all deterministic: the same catalog, seed and exclusions give the same list):
  1. Eligible: a title that is not a remix / sped-up / live / karaoke / instrumental ... version, an artist, a length
     of 60 s to 10 min, a genre that is not spoken word. Songs that already carry Spotify values in the catalog
     (feature_source = 'spotify') and songs in --exclude files are skipped.
  2. ISRC first: songs with an ISRC (the best chance to match on Spotify) are used before any without one.
  3. Coverage: the energy x valence plane is cut into 4 x 4 cells at the pool's own quartiles; each cell gets the same
     quota. Inside a cell the next song is the one farthest (tempo, release year, language) from what is already chosen,
     minus a penalty for composers and genre buckets already well represented. Cells are served round-robin, so
     stopping early is still balanced.
"""
import csv
import hashlib
import re

BAD_TITLE = re.compile(
    r"\b(remix|re-?mix|sped[ -]?up|slowed|reverb|nightcore|8d|live|karaoke|instrumental|unplugged|acoustic version|"
    r"mashup|cover|bgm|theme music|reprise|lofi|lo-fi|edit|version|demo|dj|jukebox|medley|podcast|interview|"
    r"audiobook|ringtone|trailer|teaser|speech)\b", re.I)
SPOKEN = re.compile(r"spoken|podcast|audiobook|comedy|speech", re.I)
MIN_S, MAX_S = 60, 600
GRID = 4
COMPOSER_PENALTY, GENRE_PENALTY, LANG_PENALTY = 0.35, 0.15, 3.0


def tie(seed: int, sid: str) -> int:
    return int(hashlib.sha256(("%d:%s" % (seed, sid)).encode()).hexdigest()[:12], 16)


def title_key(title, artist) -> tuple:
    t = re.sub(r"\(\s*(from|feat|ft)\b[^)]*\)|\s-\s*(from|feat|ft)\b.*$", " ", str(title or ""), flags=re.I)
    t = "".join(ch for ch in t.casefold() if ch.isalnum())
    a = re.split(r"[;,&/]", str(artist or ""))[0]
    return (t, "".join(ch for ch in a.casefold() if ch.isalnum()))


def read_exclusions(paths) -> tuple:
    """(isrc set, title/artist key set) from earlier export files: this tool's CSV (title, artist, isrc) or
    Exportify's (Track Name, Artist Name(s), ISRC)."""
    isrcs, keys = set(), set()
    for p in paths or ():
        with open(p, encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                low = {(k or "").strip().lower(): v for k, v in r.items()}
                i = "".join(ch for ch in (low.get("isrc") or "").upper() if ch.isalnum())
                if i:
                    isrcs.add(i)
                t = low.get("title") or low.get("track name")
                a = low.get("artist") or low.get("artist name(s)") or low.get("artist name")
                if t:
                    keys.add(title_key(t, a))
    return isrcs, keys


def eligible(s: dict, exclude=((), ()), skip_have_spotify=True) -> bool:
    if not s.get("title") or not s.get("artist") or BAD_TITLE.search(s["title"]):
        return False
    if not (MIN_S <= (s.get("duration") or 0) <= MAX_S):
        return False
    if SPOKEN.search(s.get("genre") or ""):
        return False
    if skip_have_spotify and s.get("feature_source") == "spotify":
        return False
    ex_isrc, ex_keys, *more = exclude                  # more[0]: library song ids matched from the files (optional)
    if more and s.get("id") in more[0]:
        return False
    return not ((s.get("isrc") and s["isrc"] in ex_isrc) or title_key(s["title"], s["artist"]) in ex_keys)


def excluded_ids(paths, songs) -> set:
    """Library songs that appear in earlier export files (ours or Exportify's), by the exportify-v1 matching rules:
    ISRC, else clean title + same version words + an artist in common + length within 5 s."""
    try:                          # package (the server: navivibe.data_queue_tools) or plain script (this folder)
        from . import spotify_match
    except ImportError:
        import spotify_match
    ids = set()
    for p in paths or ():
        ids |= {s["id"] for _, s, _ in spotify_match.match_rows(spotify_match.parse_exportify(p), songs)}
    return ids


def pick_gaps(songs: list, n: int, labelled_ids, embeddings: dict, exclude=((), ()), seed: int = 1) -> list:
    """The n eligible songs (ISRC first) that sit farthest, in the audio-embedding space, from every labelled song and
    from each other: the biggest coverage gaps of the songs Spotify has already labelled. A composer already chosen costs
    a penalty so one composer cannot take a gap alone."""
    import numpy as np
    try:
        from . import embedding_gap
    except ImportError:
        import embedding_gap
    have = [s for s in songs if s["id"] in embeddings]
    P = embedding_gap.reduce(np.stack([embeddings[s["id"]] for s in have]))
    pos = {s["id"]: i for i, s in enumerate(have)}
    labelled = [pos[i] for i in labelled_ids if i in pos]
    keys = [(s.get("composer") or s["artist"]).split(";")[0].split(",")[0].strip().casefold() for s in have]
    ok = [i for i, s in enumerate(have) if eligible(s, exclude, True) and s["id"] not in labelled_ids]
    with_isrc = [i for i in ok if have[i].get("isrc")]
    chosen = embedding_gap.kcenter(P, labelled, with_isrc, n, keys, COMPOSER_PENALTY)
    if len(chosen) < n:
        rest = [i for i in ok if not have[i].get("isrc")]
        chosen += embedding_gap.kcenter(P, labelled + chosen, rest, n - len(chosen), keys, COMPOSER_PENALTY)
    return [have[i] for i in chosen]


def quantile_edges(values, parts=GRID):
    v = sorted(values)
    if not v:
        return []
    return [v[min(len(v) - 1, (len(v) * k) // parts)] for k in range(1, parts)]


def bucket(x, edges) -> int:
    return sum(1 for e in edges if x >= e)


def rank01(values: dict) -> dict:
    """id -> rank in 0..1 (ties share the lower rank)."""
    order = sorted(values.values())
    n = max(1, len(order) - 1)
    first = {}
    for i, v in enumerate(order):
        first.setdefault(v, i)
    return {k: first[v] / n for k, v in values.items()}


def pick(songs: list, n: int, seed: int = 1, exclude=((), ()), skip_have_spotify=True) -> list:
    pool = [s for s in songs if eligible(s, exclude, skip_have_spotify)]
    with_isrc = [s for s in pool if s.get("isrc")]
    # ISRC songs first; the others only when the ISRC pool alone cannot fill N
    if with_isrc and len(with_isrc) < n:      # every ISRC song goes in; the rest is the best-spread part of the others
        rest = [s for s in pool if not s.get("isrc")]
        return with_isrc + pick(rest, n - len(with_isrc), seed, ((), ()), False)
    use = with_isrc or pool
    if n >= len(use):
        return sorted(use, key=lambda s: tie(seed, s["id"]))
    ev = [(s["energy"], s["valence"]) for s in use if s.get("energy") is not None and s.get("valence") is not None]
    e_edges = quantile_edges([e for e, _ in ev])
    v_edges = quantile_edges([v for _, v in ev])
    tempo = rank01({s["id"]: s["bpm"] for s in use if s.get("bpm")})
    year = rank01({s["id"]: s["year"] for s in use if s.get("year")})
    cells = {}
    for s in use:
        if s.get("energy") is None or s.get("valence") is None:
            c = (-1, -1)                                  # no estimate: only used when the grid cannot fill N
        else:
            c = (bucket(s["energy"], e_edges), bucket(s["valence"], v_edges))
        cells.setdefault(c, []).append(s)
    for c in cells:
        cells[c].sort(key=lambda s: tie(seed, s["id"]))
    order = sorted(k for k in cells if k != (-1, -1)) + ([(-1, -1)] if (-1, -1) in cells else [])
    chosen, taken = [], {c: 0 for c in cells}
    comp, gen, lang_n = {}, {}, {}
    lang_share = {}
    for s in use:
        lang_share[s.get("language") or ""] = lang_share.get(s.get("language") or "", 0) + 1.0 / len(use)

    def person(s):
        return (s.get("composer") or s["artist"]).split(";")[0].split(",")[0].strip().casefold()

    def dist(a, b):
        d = abs(tempo.get(a["id"], 0.5) - tempo.get(b["id"], 0.5)) + abs(year.get(a["id"], 0.5) - year.get(b["id"], 0.5))
        return d + (0.15 if (a.get("language") or "") != (b.get("language") or "") else 0.0)

    def score(s):
        far = min((dist(s, c) for c in chosen[-60:]), default=1.0)        # recent picks are the ones that matter
        lang = s.get("language") or ""
        over = max(0.0, lang_n.get(lang, 0) / max(1, len(chosen)) - lang_share.get(lang, 0.0))   # a language above its pool share
        return (far - COMPOSER_PENALTY * comp.get(person(s), 0) - GENRE_PENALTY * gen.get(s.get("genre") or "", 0) ** 0.5
                - LANG_PENALTY * over)

    quota = {c: n / max(1, len([k for k in order if k != (-1, -1)])) for c in order if c != (-1, -1)}
    while len(chosen) < n:
        progress = False
        for c in order:
            if len(chosen) >= n:
                break
            if not cells[c]:
                continue
            if c == (-1, -1) and any(cells[k] for k in order if k != (-1, -1)):
                continue                              # songs without an estimate only when the grid is used up
            if c != (-1, -1) and taken[c] >= quota[c] + 1:
                continue
            best = max(cells[c], key=lambda s: (score(s), -tie(seed, s["id"])))
            cells[c].remove(best)
            taken[c] += 1
            chosen.append(best)
            comp[person(best)] = comp.get(person(best), 0) + 1
            gen[best.get("genre") or ""] = gen.get(best.get("genre") or "", 0) + 1
            lang_n[best.get("language") or ""] = lang_n.get(best.get("language") or "", 0) + 1
            progress = True
        if not progress:
            for c in order:                          # quotas used up everywhere: let any cell give more
                taken[c] = 0
                quota[c] = quota.get(c, 0) + 1
            if not any(cells.values()):
                break
    return chosen


def coverage(chosen: list, universe: list = None) -> str:
    """Counts the owner can read: energy / valence quartiles (of the whole catalog), genre buckets, composers."""
    base = universe or chosen
    ev = [(s["energy"], s["valence"]) for s in base if s.get("energy") is not None and s.get("valence") is not None]
    e_edges, v_edges = quantile_edges([e for e, _ in ev]), quantile_edges([v for _, v in ev])
    ge, gv = [0] * GRID, [0] * GRID
    grid = [[0] * GRID for _ in range(GRID)]
    for s in chosen:
        if s.get("energy") is not None and s.get("valence") is not None:
            a, b = bucket(s["energy"], e_edges), bucket(s["valence"], v_edges)
            ge[a] += 1
            gv[b] += 1
            grid[a][b] += 1
    genres, langs, decades = {}, {}, {}
    for s in chosen:
        genres[s.get("genre") or "(none)"] = genres.get(s.get("genre") or "(none)", 0) + 1
        langs[s.get("language") or "(none)"] = langs.get(s.get("language") or "(none)", 0) + 1
        if s.get("year"):
            d = "%ds" % (s["year"] // 10 * 10)
            decades[d] = decades.get(d, 0) + 1
    composers = {(s.get("composer") or s["artist"]).split(";")[0].strip().casefold() for s in chosen}
    top = lambda d, k=8: ", ".join("%s %d" % kv for kv in sorted(d.items(), key=lambda kv: -kv[1])[:k])  # noqa: E731
    lines = [
        "sample: %d songs; %d with ISRC" % (len(chosen), sum(1 for s in chosen if s.get("isrc"))),
        "energy quartile (low..high): %s" % " / ".join(map(str, ge)),
        "valence quartile (low..high): %s" % " / ".join(map(str, gv)),
        "energy x valence cells (min / max): %d / %d" % (min(min(r) for r in grid), max(max(r) for r in grid)),
        "different composers: %d (largest share %d songs)" % (
            len(composers), max([sum(1 for s in chosen if (s.get("composer") or s["artist"]).split(";")[0].strip().casefold() == c)
                                 for c in composers] or [0])),
        "genre buckets: %s" % top(genres),
        "languages: %s" % top(langs),
        "decades: %s" % ", ".join("%s %d" % kv for kv in sorted(decades.items())),
    ]
    return "\n".join(lines)
