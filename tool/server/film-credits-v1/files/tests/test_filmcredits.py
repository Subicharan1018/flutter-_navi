import json
import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from filmcredits import cli, derive, sources  # noqa: E402


def ent(label, cls=("Q11424",), year=None, lang=("Q5885",), director=(), composer=(), lyricist=(), country=()):
    def claim(ids):
        return [{"mainsnak": {"datavalue": {"value": {"id": i}}}} for i in ids]
    claims = {"P31": claim(cls), "P364": claim(lang), "P57": claim(director), "P86": claim(composer),
              "P676": claim(lyricist), "P495": claim(country)}
    if year:
        claims["P577"] = [{"mainsnak": {"datavalue": {"value": {"time": "+%d-01-01T00:00:00Z" % year}}}}]
    return {"labels": {"en": {"value": label}}, "claims": {k: v for k, v in claims.items() if v}}


class FakeNet:
    """Answers like api.php / ws/2, from a dict; counts requests."""
    def __init__(self, search=None, entities=None, releases=None, release_full=None):
        self.search, self.entities, self.releases, self.release_full = search or {}, entities or {}, releases or {}, release_full or {}
        self.urls = []

    def __call__(self, url, headers):
        self.urls.append(url)
        assert "NaviVibe-FilmCredits" in headers["User-Agent"]
        from urllib.parse import urlparse, parse_qs
        u, q = urlparse(url), {k: v[0] for k, v in parse_qs(urlparse(url).query).items()}
        if "wikidata" in u.netloc:
            if q["action"] == "wbsearchentities":
                body = {"search": [{"id": i, "label": l} for i, l in self.search.get(q["search"], [])]}
            else:
                body = {"entities": {i: self.entities[i] for i in q["ids"].split("|") if i in self.entities}}
        elif u.path.endswith("/release"):
            body = {"releases": self.releases.get(q["query"].split('"')[1], [])}
        else:
            body = self.release_full
        return 200, json.dumps(body).encode(), {}


class Derive(unittest.TestCase):
    def test_keys_ignore_dots_case_and_spaces(self):
        self.assertEqual(derive.norm_key("A. R. Rahman"), derive.norm_key("a.r rahman"))
        self.assertEqual(derive.norm_key("Pa. Vijay"), derive.norm_key("PA Vijay"))
        self.assertEqual(derive.norm_key("காதல்"), "காதல்")

    def test_shared_key_vectors(self):          # the same vectors are asserted in test/film_credits/film_key_test.dart
        for raw, key in [("A. R. Rahman", "arrahman"), ("Kaaki Sattai", "kaakisattai"), ("  24 (Tamil) ", "24tamil"), ("", "")]:
            self.assertEqual(derive.norm_key(raw), key)

    def test_split(self):
        self.assertEqual(derive.split_names("Vijay; Shreya Ghoshal"), ["Vijay", "Shreya Ghoshal"])
        self.assertEqual(derive.split_names("Mani Sharma, Hemachandra, Saindhavi & Na. Muthukumar"),
                         ["Mani Sharma", "Hemachandra", "Saindhavi", "Na. Muthukumar"])
        self.assertEqual(derive.split_names("A ; a"), ["A"])
        self.assertEqual(derive.split_names(None), [])

    def test_clean_film(self):
        self.assertEqual(derive.clean_film("Kaaki Sattai (Original Motion Picture Soundtrack)"), "Kaaki Sattai")
        self.assertEqual(derive.clean_film("24 (Tamil) [Original Motion Picture Soundtrack]"), "24")
        self.assertEqual(derive.clean_film("Kaththi (Original Music Picture Soundtrack)"), "Kaththi")
        self.assertEqual(derive.clean_film("Devara Part 1 - TELUGU - EP"), "Devara Part 1")
        self.assertEqual(derive.clean_film("Remo - Single"), "Remo")
        self.assertEqual(derive.clean_film("Thalapathy Vijay Kondattam"), "Thalapathy Vijay Kondattam")

    def test_film_sources_in_order_of_trust(self):
        self.assertEqual(derive.film_of({"film": "Remo"}), ("Remo", "tag"))
        self.assertEqual(derive.film_of({"album": "Kodi (Original Motion Picture Soundtrack)"}), ("Kodi", "album"))
        self.assertEqual(derive.film_of({"title": 'Thanjavoor Jilla Kaari (From "Sura")'}), ("Sura", "title"))
        self.assertEqual(derive.film_of({"title": "X"}, {"trackName": "X (From “Ayan”)"}), ("Ayan", "itunes"))
        self.assertEqual(derive.film_of({"title": "Alone", "album": "Alone"}), ("", ""))     # unknown stays unknown

    def test_album_that_is_not_a_soundtrack_is_not_a_film(self):
        self.assertEqual(derive.film_of({"album": "Thalapathy Vijay Kondattam"}), ("", ""))

    def test_credits(self):
        d = derive.derive_song({"title": "Ei Suzhali", "artist": "Santhosh Narayanan ; Vivek", "composer": "Santhosh Narayanan",
                                "lyricist": "", "album": "Kodi (Original Motion Picture Soundtrack)"}, None, {derive.norm_key("Vivek")})
        self.assertEqual((d["film"], d["md"], d["ly"], d["sg"]), ("Kodi", ["Santhosh Narayanan"], ["Vivek"], ["Santhosh Narayanan"]))
        d2 = derive.derive_song({"title": "t", "artist": "Karthik"})
        self.assertEqual((d2["film"], d2["md"], d2["ly"], d2["sg"]), ("", [], [], ["Karthik"]))


FILM = "Remo"
ENT = {"Q1": ent("Remo", year=2016, director=["Q10"], composer=["Q11"], lyricist=["Q12"]),
       "Q2": ent("Remo", year=1980, lang=("Q1860",), country=("Q30",)),          # an old American film of the same title
       "Q10": {"labels": {"en": {"value": "Bakkiyaraj Kannan"}}}, "Q11": {"labels": {"en": {"value": "Anirudh Ravichander"}}},
       "Q12": {"labels": {"en": {"value": "Thamarai"}}}}


class Wikidata(unittest.TestCase):
    def client(self, net):
        return sources.Client("NaviVibe-FilmCredits/1.0 ( test )", opener=net, sleep=lambda s: None)

    def test_one_clean_match(self):
        net = FakeNet(search={FILM: [("Q1", "Remo"), ("Q2", "Remo")]}, entities=ENT)
        r = sources.resolve_film(self.client(net), FILM, 2016, ["Anirudh Ravichander"])
        self.assertEqual(r, {"wikidata": "Q1", "year": 2016, "directors": ["Bakkiyaraj Kannan"],
                             "music_directors": ["Anirudh Ravichander"], "lyricists": ["Thamarai"]})

    def test_year_that_disagrees_is_a_miss_not_a_guess(self):
        net = FakeNet(search={FILM: [("Q1", "Remo")]}, entities=ENT)
        self.assertIsNone(sources.resolve_film(self.client(net), FILM, 1999, []))

    def test_not_a_film_or_wrong_title(self):
        e = {"Q1": ent("Remo", cls=("Q5",), year=2016)}
        self.assertIsNone(sources.resolve_film(self.client(FakeNet({FILM: [("Q1", "Remo")]}, e)), FILM, 2016, []))
        self.assertIsNone(sources.resolve_film(self.client(FakeNet({FILM: [("Q1", "Remo 2")]}, ENT)), FILM, 2016, []))

    def test_two_indian_films_same_title_settled_by_composer_or_left_unknown(self):
        e = {"Q1": ent("Remo", year=2016, composer=["Q11"]), "Q3": ent("Remo", year=2017, composer=["Q13"]),
             "Q11": {"labels": {"en": {"value": "Anirudh Ravichander"}}}, "Q13": {"labels": {"en": {"value": "Someone Else"}}}}
        net = FakeNet({FILM: [("Q1", "Remo"), ("Q3", "Remo")]}, e)
        self.assertEqual(sources.resolve_film(self.client(net), FILM, None, ["Anirudh Ravichander"])["wikidata"], "Q1")
        self.assertIsNone(sources.resolve_film(self.client(net), FILM, None, []))

    def test_busy_service_is_retried_then_raises(self):
        calls = []
        def busy(url, h):
            calls.append(url)
            return 503, b"busy", {"retry-after": "1"}
        c = sources.Client("x", opener=busy, sleep=lambda s: None)
        with self.assertRaises(sources.RateLimited):
            c.wd(action="wbsearchentities")
        self.assertEqual(len(calls), sources.RETRIES)

    def test_one_request_per_second(self):
        t = [0.0]; slept = []
        c = sources.Client("x", opener=lambda u, h: (200, b"{}", {}), clock=lambda: t[0], sleep=lambda s: slept.append(s))
        c.wd(a=1); c.wd(a=2)
        self.assertTrue(slept and abs(slept[0] - sources.INTERVAL) < 1e-9)


class Tracklist(unittest.TestCase):
    REL = [{"id": "r1", "score": 100, "title": "Remo (Original Motion Picture Soundtrack)", "date": "2016-09-01", "track-count": 6,
            "artist-credit": [{"name": "Anirudh Ravichander"}]},
           {"id": "r2", "score": 100, "title": "Remo", "date": "1990", "track-count": 9, "artist-credit": [{"name": "Other"}]}]
    FULL = {"media": [{"tracks": [{"title": "Sirikkadhey", "length": 240000, "artist-credit": [{"name": "Anirudh", "joinphrase": ""}]},
                                  {"title": "Remo Theme", "length": 100000, "artist-credit": []}]}]}

    def test_accepts_the_matching_release(self):
        net = FakeNet(releases={"Remo": self.REL}, release_full=self.FULL)
        c = sources.Client("NaviVibe-FilmCredits/1.0 ( t )", opener=net, sleep=lambda s: None)
        t = sources.tracklist(c, "Remo", ["Anirudh Ravichander"], 2016)
        self.assertEqual((t["mbid"], [x["title"] for x in t["tracks"]]), ("r1", ["Sirikkadhey", "Remo Theme"]))

    def test_no_composer_match_is_a_miss(self):
        net = FakeNet(releases={"Remo": self.REL}, release_full=self.FULL)
        c = sources.Client("NaviVibe-FilmCredits/1.0 ( t )", opener=net, sleep=lambda s: None)
        self.assertIsNone(sources.tracklist(c, "Remo", ["Nobody"], 2016))


class EndToEnd(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.cat = os.path.join(self.d, "catalog.db")
        c = sqlite3.connect(self.cat)
        c.executescript("""CREATE TABLE songs(id TEXT PRIMARY KEY, title TEXT, artist TEXT, album TEXT, album_artist TEXT,
            composer TEXT, lyricist TEXT, year INTEGER, film TEXT, missing INTEGER DEFAULT 0);
            CREATE TABLE source_raw(song_id TEXT, source TEXT, ok INTEGER, fetched_at TEXT, payload TEXT, PRIMARY KEY(song_id, source));""")
        rows = [("1", "Sirikkadhey", "Anirudh Ravichander ; Thamarai", "Remo", "", "Anirudh Ravichander", "", 2016, "Remo"),
                ("2", "Remo Theme", "Anirudh Ravichander", "Remo (Original Motion Picture Soundtrack)", "", "Anirudh Ravichander", "", 2016, None),
                ("3", "Alone", "Alan Walker", "Alone", "", "", "", 2016, None)]
        c.executemany("INSERT INTO songs(id,title,artist,album,album_artist,composer,lyricist,year,film) VALUES (?,?,?,?,?,?,?,?,?)", rows)
        c.commit(); c.close()
        self.db = os.path.join(self.d, "fc.db")
        os.environ["FILMCREDITS_CONTACT"] = "https://example.invalid"

    def rows(self, sql):
        c = sqlite3.connect(self.db); r = c.execute(sql).fetchall(); c.close(); return r

    def test_offline_pass_writes_only_its_own_db(self):
        before = open(self.cat, "rb").read()
        self.assertEqual(cli.main(["--catalog", self.cat, "--db", self.db]), 0)
        self.assertEqual(open(self.cat, "rb").read(), before)
        self.assertEqual(self.rows("SELECT song_id, fk, film FROM songs ORDER BY 1"),
                         [("1", "remo", "Remo"), ("2", "remo", "Remo"), ("3", "", "")])
        self.assertEqual(self.rows("SELECT title, year FROM films"), [("Remo", 2016)])

    def test_run_fills_film_and_moves_lyricist_out_of_singers_and_caches(self):
        net = FakeNet(search={FILM: [("Q1", "Remo")]}, entities=ENT, releases={"Remo": Tracklist.REL}, release_full=Tracklist.FULL)
        a = ["--catalog", self.cat, "--db", self.db, "--run", "--tracklists"]
        self.assertEqual(cli.main(a, opener=net), 0)
        self.assertEqual(self.rows("SELECT directors, music_directors, wikidata FROM films"),
                         [('["Bakkiyaraj Kannan"]', '["Anirudh Ravichander"]', "Q1")])
        self.assertEqual(self.rows("SELECT ly, sg FROM songs WHERE song_id='1'"), [('["Thamarai"]', '["Anirudh Ravichander"]')])
        self.assertEqual(len(json.loads(self.rows("SELECT tracklist FROM films")[0][0])), 2)
        n = len(net.urls)
        cli.main(a, opener=net)                            # second run: everything cached, zero requests
        self.assertEqual(len(net.urls), n)

    def test_run_needs_a_contact(self):
        del os.environ["FILMCREDITS_CONTACT"]
        os.environ.pop("LIBENRICH_CONTACT", None)
        self.assertEqual(cli.main(["--catalog", self.cat, "--db", self.db, "--run"]), 2)


if __name__ == "__main__":
    unittest.main()
