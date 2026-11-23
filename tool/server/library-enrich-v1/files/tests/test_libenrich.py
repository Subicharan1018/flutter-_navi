"""No network: a fake opener serves recorded-shape API fixtures."""
import argparse
import json
import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from libenrich import core, genres, match, net, store  # noqa: E402

FIX = os.path.join(os.path.dirname(__file__), "fixtures")


def fx(name):
    with open(os.path.join(FIX, name), encoding="utf-8") as f:
        return f.read().encode("utf-8")


BUSY = {"retry-after": "1", "x-ratelimit-zone": "search", "x-ratelimit-who": "search-shed"}   # as MusicBrainz sent it


class FakeOpener:
    """Routes a URL to a fixture; records every URL (to check rate, UA and that nothing leaks).
    `script` = [(status, fixture or None, headers)] answered first, in order, whatever the URL.
    `status` != 200 answers every URL containing `only` (default: all) with that status and the busy body."""
    def __init__(self, routes, status=200, script=None, headers=None, only=None):
        self.routes, self.status, self.calls = routes, status, []
        self.script, self.headers, self.only = list(script or []), headers or {}, only

    def __call__(self, url, headers, timeout=30):
        self.calls.append((url, dict(headers)))
        if self.script:
            st, name, hd = self.script.pop(0)
            return st, (fx(name) if name else b""), hd
        if self.status != 200 and (self.only is None or self.only in url):
            return self.status, fx("mb_busy.json"), dict(self.headers)
        for frag, name in self.routes:
            if frag in url:
                return 200, (fx(name) if name else b'{"recordings":[]}'), {}
        return 404, b"", {}


def make_client(opener, sleeps=None):
    t = [0.0]
    return net.Client("NaviVibe-LibraryEnrich/1.0 ( https://example.invalid )", opener, clock=lambda: t[0],
                      sleep=lambda s: (sleeps.append(s) if sleeps is not None else None, t.__setitem__(0, t[0] + s)))


SONG = {"id": "s1", "title": "Kadhal Kan Kattudhe", "artist": "Anirudh Ravichander ; Shakthisree Gopalan",
        "album_artist": "", "composer": "Anirudh Ravichander", "duration": 300.0, "year": 2014, "isrc": "", "mbid": ""}


class GenreTests(unittest.TestCase):
    def test_junk_dropped_and_synonyms_merged(self):
        tags = {"tamil": 100, "Melody": 80, "seen live": 60, "Anirudh Ravichander": 50, "romantic": 40, "2010s": 30,
                "favorites": 25, "hip-hop": 90, "rap": 70}
        g = genres.normalise([(tags, 1.0)], ["Anirudh Ravichander"])
        self.assertEqual(g, ["hip hop", "melody"])

    def test_artist_name_tag_never_a_genre(self):
        self.assertEqual(genres.normalise([({"Pop": 100}, 1.0)], ["Pop"]), [])      # an artist literally called Pop

    def test_weights_and_cap(self):
        g = genres.normalise([({"rock": 100, "pop": 90, "jazz": 80, "blues": 70, "folk": 60}, 1.0)])
        self.assertEqual(len(g), 3)
        self.assertEqual(genres.normalise([({"kollywood": 100}, 0.6)]), ["soundtrack"])
        self.assertEqual(genres.normalise([({"rock": 100}, 0.1)]), [])          # weak evidence: nothing
        self.assertEqual(genres.normalise([({"rock": 100, "jazz": 10}, 1.0)]), ["rock"])

    def test_vocab_is_small(self):
        self.assertLess(len(genres.VOCAB), 60)
        self.assertNotIn("sad", genres.VOCAB)          # moods are not genres
        self.assertNotIn("tamil", genres.VOCAB)        # nor are languages


class ParseTests(unittest.TestCase):
    def test_recording(self):
        r = match.parse_recording(json.loads(fx("mb_recording.json")))
        self.assertEqual(r["isrc"], "INS171400001")
        self.assertEqual(r["release_date"], "2014-12-12")
        self.assertEqual(r["genres"], {"filmi": 3, "pop": 1})

    def test_releases_label_is_earliest_real_label(self):
        self.assertEqual(match.parse_releases(json.loads(fx("mb_releases.json")))["label"],
                         "Sony Music Entertainment India Pvt. Ltd.")

    def test_search_picks_only_the_same_song(self):
        hit = match.pick_search_hit(SONG, json.loads(fx("mb_search.json")))
        self.assertEqual(hit["id"], "27d76a88-5946-4d8a-8106-0945043fdd87")
        far = dict(SONG, duration=200.0)
        self.assertIsNone(match.pick_search_hit(far, json.loads(fx("mb_search.json"))))

    def test_tamil_title_matching(self):
        s = dict(SONG, title="காதல் கண் கட்டுதே")
        self.assertTrue(match.same_song(s, "காதல் கண் கட்டுதே", "Anirudh Ravichander", 301))
        self.assertFalse(match.same_song(s, "காதல் கண்", "Anirudh Ravichander", 301))

    def test_lastfm(self):
        self.assertEqual(match.parse_lastfm(json.loads(fx("lastfm_artist.json")))["pop"], 65)
        self.assertEqual(match.parse_lastfm({}), {})


class ClientTests(unittest.TestCase):
    def test_throttle_and_user_agent(self):
        op = FakeOpener([("recording/", "mb_recording.json")])
        sleeps = []
        c = make_client(op, sleeps)
        for _ in range(3):
            c.mb_recording("27d76a88-5946-4d8a-8106-0945043fdd87")
        self.assertEqual(len(op.calls), 3)
        self.assertEqual(len(sleeps), 2)
        self.assertTrue(all(s >= 1.0 for s in sleeps))                      # at most 1 request per second
        self.assertTrue(op.calls[0][1]["User-Agent"].startswith("NaviVibe-LibraryEnrich/1.0"))

    def test_busy_then_ok_retries_the_same_request(self):
        op = FakeOpener([], script=[(503, "mb_busy.json", BUSY), (200, "mb_recording.json", {})])
        sleeps = []
        r = make_client(op, sleeps).mb_recording("27d76a88-5946-4d8a-8106-0945043fdd87")
        self.assertEqual(r["title"], "Kadhal Kan Kattudhe")
        self.assertEqual(len(op.calls), 2)
        self.assertEqual(op.calls[0][0], op.calls[1][0])            # the very same request again
        self.assertTrue(any(x >= 2.0 for x in sleeps))              # backed off

    def test_retry_after_is_honoured_when_longer(self):
        op = FakeOpener([], script=[(503, None, {"retry-after": "30"}), (200, "mb_recording.json", {})])
        c = make_client(op)
        c.mb_recording("x")
        self.assertGreaterEqual(c.waited, 30)

    def test_persistent_busy_names_the_service_and_signal(self):
        op = FakeOpener([], status=503, headers=BUSY)
        with self.assertRaises(net.RateLimited) as cm:
            make_client(op).mb_search("Duvet", "Boa")
        self.assertEqual(cm.exception.service, "musicbrainz")
        self.assertIn("HTTP 503", str(cm.exception))
        self.assertIn("zone=search", str(cm.exception))
        self.assertIn("who=search-shed", str(cm.exception))
        self.assertEqual(len(op.calls), net.RETRIES)

    def test_lastfm_error_29_in_body_is_retried_then_named(self):
        op = FakeOpener([("method=", "lastfm_ratelimit.json")])
        with self.assertRaises(net.RateLimited) as cm:
            make_client(op).lf_tags("KEY", "track.getTopTags", "a", "b")
        self.assertEqual(cm.exception.service, "lastfm")
        self.assertIn("error 29", str(cm.exception))
        self.assertNotIn("KEY", str(cm.exception))
        op2 = FakeOpener([], script=[(200, "lastfm_ratelimit.json", {}), (200, "lastfm_artist.json", {})])
        self.assertIn("toptags", make_client(op2).lf_tags("KEY", "artist.getTopTags", "a"))

    def test_http_429_with_json_body_for_lastfm(self):
        op = FakeOpener([], script=[(429, "lastfm_ratelimit.json", {}), (200, "lastfm_artist.json", {})])
        self.assertIn("toptags", make_client(op).lf_tags("KEY", "artist.getTopTags", "a"))

    def test_old_two_tuple_openers_still_work(self):
        c = make_client(lambda url, headers, timeout=30: (200, fx("lastfm_artist.json")))
        self.assertIn("toptags", c.lf_tags("KEY", "artist.getTopTags", "a"))

    def test_lastfm_notfound_is_a_miss(self):
        op = FakeOpener([("method=", "lastfm_notfound.json")])
        self.assertIsNone(make_client(op).lf_tags("KEY", "track.getTopTags", "a", "b"))


class Env(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.cfg = {"catalog": os.path.join(d, "catalog.db"), "details": os.path.join(d, "spotify_details.db"),
                    "cache": os.path.join(d, "enrich.db"), "contact": "https://example.invalid", "env_file": ""}
        c = sqlite3.connect(self.cfg["catalog"])
        c.execute("create table songs(id,title,artist,album_artist,composer,duration,year,isrc,mbid,missing)")
        c.execute("create table source_raw(song_id,source,ok,fetched_at,payload)")
        c.execute("insert into songs values('s1','Kadhal Kan Kattudhe','Anirudh Ravichander ; Shakthisree Gopalan','','Anirudh Ravichander',300,2014,'','',0)")
        c.execute("insert into songs values('s2','Other Song','Someone','','',200,2010,'INS000000001','',0)")
        c.execute("insert into songs values('s3','Done Song','Else','','',200,2010,'INS000000002','',0)")
        c.execute("insert into source_raw values('s2','lastfm',1,'2026-11-01 10:00','%s')" % json.dumps(
            {"track_tags": {}, "artist_tags": {"pop": 100, "indian": 50}}))
        c.execute("insert into source_raw values('s2','musicbrainz',1,'2026-11-01 10:00','%s')" % json.dumps(
            {"mbid": "m2", "first_release_date": "2010-05-05", "match": 1.0}))
        c.commit()
        c.close()
        self.args = argparse.Namespace(apply_only=False, limit=0, max_minutes=0, end_by=None, no_lastfm=False,
                                       no_musicbrainz=False, dry_run=False)

    def tearDown(self):
        self.tmp.cleanup()

    def details(self):
        c = sqlite3.connect(self.cfg["details"])
        c.row_factory = sqlite3.Row
        try:
            return {r["song_id"]: dict(r) for r in c.execute("select * from spotify_details")}
        finally:
            c.close()


class RunTests(Env):
    routes = [("recording?query", "mb_search.json"), ("recording/", "mb_recording.json"),
              ("/release?", "mb_releases.json"), ("track.getTopTags", "lastfm_track.json"),
              ("artist.getTopTags", "lastfm_artist.json")]

    def seed_exportify_row(self):
        c = sqlite3.connect(self.cfg["details"])
        c.execute("CREATE TABLE spotify_details (%s)" % store.DETAILS_COLUMNS)
        c.execute("INSERT INTO spotify_details (song_id,isrc,genres,label,release_date,energy,valence,matched_by,updated_at) "
                  "VALUES ('s3','INS000000002','[\"tamil pop\"]','Spotify Label','2001-01-01',0.9,0.8,'isrc',1)")
        c.commit()
        c.close()

    def test_full_run_fills_and_records_provenance(self):
        self.seed_exportify_row()
        op = FakeOpener(self.routes)
        out = core.run(self.cfg, self.args, make_client(op), "KEY", log=lambda *_: None)
        d = self.details()
        s1 = d["s1"]
        self.assertEqual((s1["isrc"], s1["label"], s1["release_date"]),
                         ("INS171400001", "Sony Music Entertainment India Pvt. Ltd.", "2014-12-12"))
        self.assertEqual(json.loads(s1["genres"]), ["soundtrack", "pop"])
        self.assertEqual(s1["matched_by"], "libenrich")
        self.assertIsNone(s1["energy"])
        # s2's ISRC is in the catalog already: never copied
        self.assertIsNone(d["s2"]["isrc"])
        # exportify's row is untouched
        self.assertEqual((d["s3"]["label"], d["s3"]["energy"], d["s3"]["genres"]), ("Spotify Label", 0.9, '["tamil pop"]'))
        c = sqlite3.connect(self.cfg["details"])
        prov = {(r[0], r[1]): (r[2], r[3]) for r in c.execute("select song_id, field, source, source_date from enrich_provenance")}
        c.close()
        self.assertEqual(prov[("s1", "label")][0], "musicbrainz")
        self.assertNotIn(("s3", "label"), prov)
        self.assertEqual(out["lastfm_lookups"], 0)        # s1's genres came with MB (filmi) + Last.fm below
        self.assertTrue(all("KEY" not in u or "api_key" in u for u, _ in op.calls))

    def test_cached_and_resumable(self):
        op = FakeOpener(self.routes)
        core.run(self.cfg, self.args, make_client(op), "KEY", log=lambda *_: None)
        n = len(op.calls)
        self.assertGreater(n, 0)
        op2 = FakeOpener(self.routes)
        core.run(self.cfg, self.args, make_client(op2), "KEY", log=lambda *_: None)
        self.assertEqual(len(op2.calls), 0)               # nothing missing, nothing fetched

    def test_miss_is_cached_with_retry_date(self):
        op = FakeOpener([("recording?query", None)])
        core.run(self.cfg, self.args, make_client(op), "", log=lambda *_: None)
        self.assertEqual(len(op.calls), 3)             # s1 (search), s2 (mbid), s3 (search)
        c = store.Cache(self.cfg["cache"])
        e = c.get("s1", "mb")
        c.close()
        self.assertEqual(e["status"], "miss")
        self.assertGreater(e["retry_after"], store.today())
        op2 = FakeOpener([("recording?query", None)])
        core.run(self.cfg, self.args, make_client(op2), "", log=lambda *_: None)
        self.assertEqual(len(op2.calls), 0)               # not retried before the retry-after date

    def test_musicbrainz_busy_does_not_stop_lastfm_and_nothing_is_cached(self):
        op = FakeOpener(self.routes, status=503, headers=BUSY, only="musicbrainz.org")
        logs = []
        out = core.run(self.cfg, self.args, make_client(op), "KEY", log=logs.append)
        self.assertEqual(out["paused"], ["musicbrainz"])
        self.assertGreater(out["deferred"], 0)
        self.assertGreater(out["lastfm_lookups"], 0)            # Last.fm carried on for the genres
        self.assertTrue(any("musicbrainz is busy" in m and "zone=search" in m for m in logs))
        c = store.Cache(self.cfg["cache"])
        self.assertIsNone(c.get("s1", "mb"))                    # a busy answer is not a miss and not cached
        self.assertEqual(c.get("s1", "lastfm")["status"], "ok")
        c.close()
        self.assertEqual(json.loads(self.details()["s1"]["genres"]), ["melody", "soundtrack", "pop"])

    def test_all_services_busy_stops_the_run(self):
        out = core.run(self.cfg, self.args, make_client(FakeOpener([], status=429)), "KEY", log=lambda *_: None)
        c = sqlite3.connect(self.cfg["catalog"])
        for i in range(6):
            c.execute("insert into songs values('x%d','T%d','A%d','','',200,2010,'','',0)" % (i, i, i))
        c.commit()
        c.close()
        out = core.run(self.cfg, self.args, make_client(FakeOpener([], status=429)), "KEY", log=lambda *_: None)
        self.assertTrue(out["stopped"].startswith("paused"), out)
        self.assertEqual(sorted(out["paused"]), ["lastfm", "musicbrainz"])

    def test_busy_then_ok_inside_a_run_finishes_the_song(self):
        op = FakeOpener(self.routes, script=[(503, "mb_busy.json", BUSY)])
        out = core.run(self.cfg, self.args, make_client(op), "KEY", log=lambda *_: None)
        self.assertEqual(out["deferred"], 0)
        self.assertEqual(self.details()["s1"]["label"], "Sony Music Entertainment India Pvt. Ltd.")

    def test_a_miss_is_not_a_failure(self):
        out = core.run(self.cfg, self.args, make_client(FakeOpener([("recording?query", None)])), "", log=lambda *_: None)
        self.assertEqual(out["stopped"], "")                    # misses only: no failure counted, run finished

    def test_network_errors_stop_after_five(self):
        def boom(url, headers, timeout=30):
            raise net.NetError("URLError")
        c = sqlite3.connect(self.cfg["catalog"])
        for i in range(10):
            c.execute("insert into songs values('x%d','T%d','A%d','','',200,2010,'','',0)" % (i, i, i))
        c.commit()
        c.close()
        out = core.run(self.cfg, self.args, make_client(boom), "", log=lambda *_: None)
        self.assertEqual(out["stopped"], "errors")

    def test_no_musicbrainz_and_no_lastfm_paths(self):
        self.args.no_musicbrainz = True
        op = FakeOpener(self.routes)
        out = core.run(self.cfg, self.args, make_client(op), "KEY", log=lambda *_: None)
        self.assertEqual(out["mb_lookups"], 0)
        self.assertTrue(all("musicbrainz" not in u for u, _ in op.calls))
        self.assertGreater(out["lastfm_lookups"], 0)
        self.args.no_musicbrainz, self.args.no_lastfm = False, True
        op = FakeOpener(self.routes)
        core.run(self.cfg, self.args, make_client(op), "KEY", log=lambda *_: None)
        self.assertTrue(all("audioscrobbler" not in u for u, _ in op.calls))
        self.args.no_musicbrainz = True
        out = core.run(self.cfg, self.args, make_client(FakeOpener([])), "KEY", log=lambda *_: None)
        self.assertEqual(out["stopped"], "nothing enabled")

    def test_estimate_counts_requests(self):
        e = core.estimate(self.cfg, key=True)
        self.assertEqual(e["mb_songs"], 3)
        self.assertEqual(e["mb_requests"], 3 + 2 + 3)           # s1 search+2, s2 has an mbid, s3 search+2
        self.assertGreater(e["hours"], 0)

    def test_limit_and_dry_run(self):
        self.args.dry_run = True
        out = core.run(self.cfg, self.args, make_client(FakeOpener(self.routes)), "KEY", log=lambda *_: None)
        self.assertFalse(os.path.exists(self.cfg["details"]))
        self.assertEqual(out["to_write"]["label"], 2)

    def test_never_overwrites_a_filled_field_and_reimport_is_handled(self):
        core.run(self.cfg, self.args, make_client(FakeOpener(self.routes)), "KEY", log=lambda *_: None)
        c = sqlite3.connect(self.cfg["details"])
        c.execute("UPDATE spotify_details SET label='Admin Label' WHERE song_id='s1'")     # an admin edit
        c.execute("DELETE FROM spotify_details WHERE song_id='s2'")                         # exportify replaced a row
        c.commit()
        c.close()
        self.args.apply_only = True
        core.run(self.cfg, self.args, None, "", log=lambda *_: None)
        d = self.details()
        self.assertEqual(d["s1"]["label"], "Admin Label")
        self.assertEqual(d["s2"]["release_date"], "2014-12-12")        # refilled from the cache, no network
        c = sqlite3.connect(self.cfg["details"])
        self.assertEqual(c.execute("select count(*) from enrich_provenance where song_id='s1' and field='label'").fetchone()[0], 0)   # the admin's value is not ours
        c.close()

    def test_reader_contract_unchanged(self):
        """The columns are exactly exportify-v1's, so navivibe/spotify_details.py reads the file as before."""
        core.run(self.cfg, self.args, make_client(FakeOpener(self.routes)), "KEY", log=lambda *_: None)
        c = sqlite3.connect(self.cfg["details"])
        cols = [r[1] for r in c.execute("PRAGMA table_info(spotify_details)")]
        c.close()
        self.assertEqual(cols[:9], ["song_id", "isrc", "popularity", "genres", "label", "release_date", "explicit",
                                    "duration_s", "matched_by"])
        self.assertEqual(cols[9:-1], list(store.FEATURES))
        self.assertEqual(cols[-1], "updated_at")


class OfflineTests(Env):
    def test_catalog_payloads_alone_fill_date_and_genres(self):
        self.args.no_musicbrainz = True
        op = FakeOpener([])
        core.run(self.cfg, self.args, make_client(op), "", log=lambda *_: None)
        self.assertEqual(len(op.calls), 0)
        d = self.details()
        self.assertEqual(d["s2"]["release_date"], "2010-05-05")
        self.assertEqual(json.loads(d["s2"]["genres"]), ["pop"])
        c = sqlite3.connect(self.cfg["details"])
        prov = {(r[0], r[1]): (r[2], r[3]) for r in c.execute("select song_id, field, source, source_date from enrich_provenance")}
        c.close()
        self.assertEqual(prov[("s2", "release_date")], ("musicbrainz(catalog)", "2026-11-01"))
        self.assertEqual(prov[("s2", "genres")], ("lastfm", "2026-11-01"))


class KeyTests(unittest.TestCase):
    def test_key_from_env_file_by_name(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, ".env")
            with open(p, "w") as f:
                f.write("OTHER=1\nLASTFM_API_KEY='abc123'\n")
            self.assertEqual(core.lastfm_key({}, p), "abc123")
            self.assertEqual(core.lastfm_key({"LASTFM_API_KEY": "fromenv"}, p), "fromenv")
            self.assertEqual(core.lastfm_key({}, os.path.join(d, "none")), "")

    def test_contact_required(self):
        from libenrich import cli
        os.environ.pop("LIBENRICH_CONTACT", None)
        self.assertEqual(cli.main(["--run"]), 2)


if __name__ == "__main__":
    unittest.main()
