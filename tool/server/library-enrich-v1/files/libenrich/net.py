"""HTTP: rate limiting, MusicBrainz and Last.fm clients. The opener is injectable so tests never touch the network.
Errors carry only a status code or a type name: never a URL (a Last.fm URL contains the API key).

Rate-limit signals seen live (23 Nov 2026): MusicBrainz answers `503` with `Retry-After: 1`,
`X-RateLimit-Zone: search`, `X-RateLimit-Who: search-shed` and body "currently busy": that is the gateway shedding
load for the whole search zone, not our own rate. The right answer is to wait and retry the SAME request."""
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
RETRIES = 4                # tries per request when the service says "busy"
BACKOFF_S = 2.0            # 2, 4, 8, 16 s unless Retry-After says more
MAX_WAIT_S = 60.0
LF_RETRY_ERRORS = {8, 16, 29}   # operation failed, temporary error, rate limit exceeded


class RateLimited(Exception):
    """The service kept saying 'busy' after every retry. `service` is 'musicbrainz' or 'lastfm'; the text names the
    signal (status or error code, plus MusicBrainz's zone) so the log shows who limited us."""
    def __init__(self, service: str, detail: str):
        super().__init__("%s: %s" % (service, detail))
        self.service, self.detail = service, detail


class NetError(Exception):
    """A transient failure (network, 5xx, bad JSON). Only a short description, never a URL."""


def real_opener(url: str, headers: dict, timeout: float = 30):
    """(status, body, response headers as a dict with lower-case keys)."""
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(), {k.lower(): v for k, v in r.headers.items()}
    except urllib.error.HTTPError as e:
        return e.code, (e.read() or b""), {k.lower(): v for k, v in (e.headers or {}).items()}
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise NetError(type(e).__name__)


def retry_after(headers: dict) -> float:
    try:
        return max(0.0, float(headers.get("retry-after", 0)))
    except (TypeError, ValueError):
        return 0.0


def describe(service: str, status, headers: dict) -> str:
    bits = ["HTTP %s" % status]
    for k in ("x-ratelimit-zone", "x-ratelimit-who", "retry-after"):
        if headers.get(k):
            bits.append("%s=%s" % (k.replace("x-ratelimit-", ""), headers[k]))
    return " ".join(bits)


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
        self.ua, self.opener, self.sleep = user_agent, opener, sleep
        self.mb = Throttle(MB_INTERVAL, clock, sleep)
        self.lf = Throttle(LF_INTERVAL, clock, sleep)
        self.waited = 0.0          # seconds spent backing off (for the run summary)

    def _call(self, throttle, url):
        throttle.wait()
        out = self.opener(url, {"User-Agent": self.ua, "Accept": "application/json"})
        return (out + ({},))[:3] if len(out) == 2 else out

    def _json(self, service, throttle, url, body_busy=None):
        """GET with retry: on 429/503 (or a busy answer inside the body) wait max(Retry-After, backoff) and
        try the same request again, up to RETRIES times, then raise RateLimited."""
        detail = ""
        for attempt in range(RETRIES):
            status, body, headers = self._call(throttle, url)
            data = None
            busy = status in (429, 503)
            if status == 200 or (status not in (404,) and not busy and body_busy):
                try:
                    data = json.loads(body.decode("utf-8")) if body else None
                except ValueError:
                    if status == 200:
                        raise NetError("bad json")
                if body_busy and body_busy(data):
                    busy, status = True, "error %s" % (data or {}).get("error")
            if not busy:
                if status == 404:
                    return None
                if status != 200:
                    raise NetError("http %s" % status)
                return data
            detail = describe(service, status, headers)
            if attempt + 1 < RETRIES:
                wait = min(MAX_WAIT_S, max(retry_after(headers), BACKOFF_S * 2 ** attempt))
                self.waited += wait
                self.sleep(wait)
        raise RateLimited(service, detail)

    # MusicBrainz -------------------------------------------------------------
    def mb_get(self, path: str, **params):
        params["fmt"] = "json"
        return self._json("musicbrainz", self.mb, "%s/%s?%s" % (MB_BASE, path, urllib.parse.urlencode(params)))

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
        busy = lambda d: isinstance(d, dict) and d.get("error") in LF_RETRY_ERRORS   # noqa: E731
        data = self._json("lastfm", self.lf, LF_BASE + "?" + urllib.parse.urlencode(p), body_busy=busy)
        if isinstance(data, dict) and "error" in data:
            return None                                   # 6 = not found, others: a miss
        return data
