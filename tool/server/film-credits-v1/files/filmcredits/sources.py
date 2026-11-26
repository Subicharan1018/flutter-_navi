"""Wikidata (CC0) and MusicBrainz (CC0) clients and the strict matching rules. The opener is injectable: tests never
touch the network. Errors carry a status or a type name, never a URL. Politeness: one request per second at most, a
User-Agent that names a contact, a busy answer (429/503) is waited out and retried a few times, then the song or film is
left for the next run (nothing cached), exactly as library-enrich-v1 does.

Nothing here guesses: a film is accepted only when exactly one Wikidata item is a film with the same title and a year (and
language / country / composer) that agrees with the library. Otherwise the answer is a miss and the fields stay empty.
"""
import json
import time
import urllib.error
import urllib.parse
import urllib.request

from .derive import norm_key

WD_API = "https://www.wikidata.org/w/api.php"
MB_BASE = "https://musicbrainz.org/ws/2"
INTERVAL = 1.1
RETRIES = 4
BACKOFF_S = 2.0
MAX_WAIT_S = 60.0

Q_FILM = {"Q11424"}                                          # film
Q_INDIAN_LANGS = {"Q5885", "Q8097", "Q1568", "Q36236", "Q33673", "Q1860"}   # Tamil Telugu Hindi Malayalam Kannada (+ English: needs a country)
Q_INDIA = "Q668"
P_CLASS, P_DATE, P_DIRECTOR, P_COMPOSER, P_LYRICIST, P_LANG, P_COUNTRY = "P31", "P577", "P57", "P86", "P676", "P364", "P495"


class RateLimited(Exception):
    pass


class NetError(Exception):
    pass


def real_opener(url, headers, timeout=30):
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(), {k.lower(): v for k, v in r.headers.items()}
    except urllib.error.HTTPError as e:
        return e.code, (e.read() or b""), {k.lower(): v for k, v in (e.headers or {}).items()}
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise NetError(type(e).__name__)


class Client:
    def __init__(self, user_agent, opener=real_opener, clock=time.monotonic, sleep=time.sleep):
        self.ua, self.opener, self.clock, self.sleep = user_agent, opener, clock, sleep
        self.last = None
        self.requests = 0

    def _get(self, url):
        for attempt in range(RETRIES):
            if self.last is not None:
                gap = INTERVAL - (self.clock() - self.last)
                if gap > 0:
                    self.sleep(gap)
            self.last = self.clock()
            self.requests += 1
            status, body, headers = self.opener(url, {"User-Agent": self.ua, "Accept": "application/json"})
            if status in (429, 503):
                try:
                    ra = float(headers.get("retry-after", 0))
                except (TypeError, ValueError):
                    ra = 0.0
                if attempt + 1 < RETRIES:
                    self.sleep(min(MAX_WAIT_S, max(ra, BACKOFF_S * 2 ** attempt)))
                continue
            if status == 404:
                return None
            if status != 200:
                raise NetError("http %s" % status)
            try:
                return json.loads(body.decode("utf-8"))
            except ValueError:
                raise NetError("bad json")
        raise RateLimited("HTTP busy")

    def wd(self, **p):
        p["format"] = "json"
        return self._get(WD_API + "?" + urllib.parse.urlencode(p))

    def mb(self, path, **p):
        p["fmt"] = "json"
        return self._get("%s/%s?%s" % (MB_BASE, path, urllib.parse.urlencode(p)))


# ── Wikidata ──────────────────────────────────────────────────────────────────

def _ids(entity, prop):
    out = []
    for c in (entity.get("claims") or {}).get(prop, []):
        v = ((c.get("mainsnak") or {}).get("datavalue") or {}).get("value")
        if isinstance(v, dict) and v.get("id"):
            out.append(v["id"])
    return out


def _year(entity):
    for c in (entity.get("claims") or {}).get(P_DATE, []):
        t = (((c.get("mainsnak") or {}).get("datavalue") or {}).get("value") or {}).get("time", "")
        if t[1:5].isdigit():
            return int(t[1:5])
    return None


def _label(entity):
    return ((entity.get("labels") or {}).get("en") or {}).get("value", "")


def film_candidates(client, title):
    r = client.wd(action="wbsearchentities", search=title, language="en", type="item", limit=8) or {}
    ids = [h["id"] for h in r.get("search", []) if norm_key(h.get("label")) == norm_key(title)]
    if not ids:
        return {}
    e = client.wd(action="wbgetentities", ids="|".join(ids[:6]), props="claims|labels", languages="en") or {}
    return e.get("entities") or {}


def pick_film(entities, title, year=None):
    """The one Wikidata film that is this film, or None. A film item must: be a film; have the same title; sit in the
    Indian film world (language or country); and not contradict the library's year (+/-2). Returns (qid, entity), None,
    or ('ambiguous', [(qid, entity), ...])."""
    ok = []
    for qid, ent in entities.items():
        if norm_key(_label(ent)) != norm_key(title) or not (set(_ids(ent, P_CLASS)) & Q_FILM):
            continue
        langs, countries = set(_ids(ent, P_LANG)), set(_ids(ent, P_COUNTRY))
        if not (langs & Q_INDIAN_LANGS) and Q_INDIA not in countries:
            continue
        y = _year(ent)
        if year and y and abs(year - y) > 2:
            continue
        ok.append((qid, ent))
    # more than one survivor: resolve_film settles it by composer (needs the people's labels), else it is a miss
    return ok[0] if len(ok) == 1 else (None if not ok else ("ambiguous", ok))


def resolve_film(client, title, year=None, composers=()):
    """-> dict {wikidata, year, directors, music_directors, lyricists} or None (a miss)."""
    cands = film_candidates(client, title)
    got = pick_film(cands, title, year)
    if got is None:
        return None
    if got[0] == "ambiguous":
        ids = {n for _, e in got[1] for n in _ids(e, P_COMPOSER)}
        names = _labels(client, ids)
        want = {norm_key(c) for c in composers}
        keep = [(q, e) for q, e in got[1] if want & {norm_key(names.get(n, "")) for n in _ids(e, P_COMPOSER)}]
        if len(keep) != 1:
            return None
        got = keep[0]
    qid, ent = got
    people = set(_ids(ent, P_DIRECTOR) + _ids(ent, P_COMPOSER) + _ids(ent, P_LYRICIST))
    names = _labels(client, people)
    nm = lambda prop: [names[i] for i in _ids(ent, prop) if names.get(i)]   # noqa: E731
    return {"wikidata": qid, "year": _year(ent), "directors": nm(P_DIRECTOR), "music_directors": nm(P_COMPOSER),
            "lyricists": nm(P_LYRICIST)}


def _labels(client, ids):
    ids = sorted(ids)
    out = {}
    for i in range(0, len(ids), 50):
        e = client.wd(action="wbgetentities", ids="|".join(ids[i:i + 50]), props="labels", languages="en") or {}
        for q, ent in (e.get("entities") or {}).items():
            if _label(ent):
                out[q] = _label(ent)
    return out


# ── MusicBrainz soundtrack track list ─────────────────────────────────────────

def tracklist(client, title, composers=(), year=None):
    """-> {'mbid', 'tracks': [{'title','artist','ms'}]} or None. The release must carry the film's title, score >= 90, a
    soundtrack-like type or an Indian-music artist match (composer in the artist credit), and a date near the film's year."""
    q = 'release:"%s"' % title.replace('"', " ")
    if composers:
        q += ' AND artist:"%s"' % composers[0].replace('"', " ")
    r = client.mb("release", query=q, limit=6) or {}
    best = None
    for rel in r.get("releases", []):
        if int(rel.get("score", 0)) < 90 or norm_key(_strip(rel.get("title"))) != norm_key(title):
            continue
        d = (rel.get("date") or "")[:4]
        if year and d.isdigit() and abs(int(d) - year) > 2:
            continue
        credit = " ".join(a.get("name", "") for a in rel.get("artist-credit", []) if isinstance(a, dict))
        if composers and norm_key(composers[0]) not in norm_key(credit):
            continue
        if best is None or int(rel.get("track-count", 0)) > int(best.get("track-count", 0)):
            best = rel
    if not best:
        return None
    full = client.mb("release/" + urllib.parse.quote(best["id"]), inc="recordings+artist-credits") or {}
    tracks = []
    for m in full.get("media", []):
        for t in m.get("tracks", []):
            tracks.append({"title": t.get("title", ""), "ms": t.get("length"),
                           "artist": " ".join((a.get("name", "") + (a.get("joinphrase") or ""))
                                              for a in t.get("artist-credit", []) if isinstance(a, dict)).strip()})
    return {"mbid": best["id"], "tracks": [t for t in tracks if t["title"]]} if len(tracks) >= 2 else None


def _strip(s):
    from .derive import clean_film
    return clean_film(s)
