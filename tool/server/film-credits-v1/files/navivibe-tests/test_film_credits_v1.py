"""film-credits-v1, web server side: the reader, the /credits/films route and the /catalog/songs extras."""
import json
import sqlite3

import pytest
from flask import Flask

from navivibe import film_credits


@pytest.fixture
def db(tmp_path, monkeypatch):
    p = str(tmp_path / "film_credits.db")
    c = sqlite3.connect(p)
    c.executescript("""
    CREATE TABLE songs(song_id TEXT PRIMARY KEY, fk TEXT, film TEXT, md TEXT, ly TEXT, sg TEXT, film_src TEXT);
    CREATE TABLE films(fk TEXT PRIMARY KEY, title TEXT, year INTEGER, directors TEXT, music_directors TEXT, lyricists TEXT,
        wikidata TEXT, tracklist TEXT, tracklist_mbid TEXT, source TEXT, updated_at TEXT);""")
    c.execute("INSERT INTO songs VALUES ('s1','remo','Remo','[\"Anirudh\"]','[\"Thamarai\"]','[\"Anirudh\",\"Shweta\"]','tag')")
    c.execute("INSERT INTO songs VALUES ('s2','','','[]','[]','[\"Karthik\"]','')")
    c.execute("INSERT INTO films VALUES ('remo','Remo',2016,'[\"Bakkiyaraj Kannan\"]','[\"Anirudh\"]','[]','Q1',"
              "'[{\"title\":\"Sirikkadhey\"}]','mb','wikidata','2026-11-24')")
    c.execute("INSERT INTO films VALUES ('orphan','Orphan',2001,'[]','[]','[]','',NULL,'','tags','2026-11-24')")
    c.commit(); c.close()
    monkeypatch.setattr(film_credits, "PATH", p)
    return p


def client():
    app = Flask(__name__)
    film_credits.register_film_credits_routes(app, lambda f: f)
    return app.test_client()


def test_extend_entry_adds_keys_and_fills_a_missing_film_only(db):
    e = {"id": "s1"}
    film_credits.extend_entry(e, {"id": "s1"})
    assert e == {"id": "s1", "film": "Remo", "fk": "remo", "md": ["Anirudh"], "ly": ["Thamarai"], "sg": ["Anirudh", "Shweta"]}
    e = {"id": "s1", "film": "The Catalog's Own"}
    film_credits.extend_entry(e, {"id": "s1"})
    assert e["film"] == "The Catalog's Own"                      # the catalog's tag always wins
    e = {"id": "s2"}
    film_credits.extend_entry(e, {"id": "s2"})
    assert e == {"id": "s2", "sg": ["Karthik"]}                  # unknown stays absent


def test_no_file_no_table_no_row_is_no_answer(tmp_path, monkeypatch):
    monkeypatch.setattr(film_credits, "PATH", str(tmp_path / "none.db"))
    e = {"id": "x"}
    film_credits.extend_entry(e, {"id": "x"})
    assert e == {"id": "x"} and film_credits.stamp() is None
    assert json.loads(client().get("/credits/films").data) == {"films": []}
    bad = tmp_path / "bad.db"
    bad.write_bytes(b"not a database")
    monkeypatch.setattr(film_credits, "PATH", str(bad))
    assert json.loads(client().get("/credits/films").data) == {"films": []}


def test_films_route_lists_only_films_that_have_songs_with_etag(db):
    r = client().get("/credits/films")
    films = json.loads(r.data)["films"]
    assert [f["fk"] for f in films] == ["remo"]
    assert films[0] == {"fk": "remo", "title": "Remo", "year": 2016, "directors": ["Bakkiyaraj Kannan"],
                        "music_directors": ["Anirudh"], "wikidata": "Q1", "tracklist": [{"title": "Sirikkadhey"}]}
    again = client().get("/credits/films", headers={"If-None-Match": r.headers["ETag"]})
    assert again.status_code == 304


def test_catalog_document_carries_the_extras(db):
    from navivibe.catalog import api
    doc = api.build_document({"s1": {"id": "s1", "film": None, "composer": "Anirudh"}})
    s = doc["songs"][0]
    assert (s["film"], s["fk"], s["md"], s["sg"]) == ("Remo", "remo", ["Anirudh"], ["Anirudh", "Shweta"])
    assert s["composer"] == "Anirudh"                            # nothing renamed
