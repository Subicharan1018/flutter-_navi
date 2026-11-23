"""HTTP: rate limiting, MusicBrainz and Last.fm clients. The opener is injectable so tests never touch the network.
Errors carry only a status code or a type name: never a URL (a Last.fm URL contains the API key)."""
import json
import time
import urllib.error
import urllib.parse
import urllib.request

MB_BASE = "https://musicbrainz.org/ws/2"
LF_BASE = "https://ws.audioscrobbler.com/2.0/"
MB_INTERVAL = 1.1          # MusicBrainz allows 1 request per second per IP
LF_INTERVAL = 0.3
NO_LABEL_IDS = {"157afde4-4bf5-4039-8ad2-5a15acc85466"}          # MusicBrainz's special "[no label]"


class RateLimited(Exception):
    """HTTP 429/503 or a Last.fm rate-limit error: stop the run, resume on the next one."""


class NetError(Exception):
    """A transient failure (network, 5xx, bad JSON). Only a short description, never a URL."""


def real_opener(url: str, headers: dict, timeout: float = 30):
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise NetError(type(e).__name__)


class Throttle:
    def __init__(self, interval: float, clock=time.monotonic, sleep=time.sleep):
        self.interval, self.clock, self.sleep, self.last = interval, clock, sleep, None

    def wait(self):
        if self.last is not None:
            gap = self.interval - (self.clock() - self.last)
            if gap > 0:
                self.sleep(gap)
        self.last = self.clock()


class Client:
    def __init__(self, user_agent: str, opener=real_opener, clock=time.monotonic, sleep=time.sleep):
        self.ua, self.opener = user_agent, opener
        self.mb = Throttle(MB_INTERVAL, clock, sleep)
        self.lf = Throttle(LF_INTERVAL, clock, sleep)

    def _json(self, throttle, url):
        throttle.wait()
        status, body = self.opener(url, {"User-Agent": self.ua, "Accept": "application/json"})
        if status in (429, 503):
            raise RateLimited(str(status))
        if status == 404:
            return None
        if status != 200:
            raise NetError("http %d" % status)
        try:
            return json.loads(body.decode("utf-8"))
        except ValueError:
            raise NetError("bad json")

    # MusicBrainz -------------------------------------------------------------
    def mb_get(self, path: str, **params):
        params["fmt"] = "json"
        return self._json(self.mb, "%s/%s?%s" % (MB_BASE, path, urllib.parse.urlencode(params)))

    def mb_recording(self, mbid):
        return self.mb_get("recording/" + urllib.parse.quote(mbid), inc="isrcs+genres+releases")

    def mb_releases(self, mbid):
        return self.mb_get("release", recording=mbid, inc="labels", limit=50)

    def mb_search(self, title: str, artist: str):
        q = 'recording:"%s"' % title.replace('"', " ")
        if artist:
            q += ' AND artist:"%s"' % artist.replace('"', " ")
        return self.mb_get("recording", query=q, limit=5)

    # Last.fm -----------------------------------------------------------------
    def lf_tags(self, api_key: str, method: str, artist: str, track: str = None):
        p = {"method": method, "artist": artist, "api_key": api_key, "format": "json", "autocorrect": 1}
        if track:
            p["track"] = track
        data = self._json(self.lf, LF_BASE + "?" + urllib.parse.urlencode(p))
        if isinstance(data, dict) and "error" in data:
            if data["error"] in (29, 8, 16):              # rate limit / operation failed / temporary
                raise RateLimited("lastfm %s" % data["error"])
            return None                                   # 6 = not found, others: a miss
        return data
