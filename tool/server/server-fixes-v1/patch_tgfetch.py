"""server-fixes-v1: small anchored patches to tg-fetcher's existing files.

The new behaviour lives in new files (tgfetch/library_sweep.py, search_owned.py,
titles.py, youtube_list.py, youtube_batch.py, autoimport.py); these patches only
hook them in:

  links.py     YouTube / YouTube Music playlist links are accepted (ids checked
               by youtube_list), canonical link, track list via ytmusicapi
  worker.py    song search: in_library only when title AND artist are named,
               owned_hint otherwise; a superseded search stops; YouTube link
               preview cleaned + owned-checked; a YouTube batch is never sent
               to the bot (by name, youtube_batch.run)
  api.py       a newer search supersedes the user's older one; owned_hint,
               source_title, unreadable in GET /searches/{id}
  db.py        resolved_failures table; failed_songs leaves resolved ones out;
               a superseded search is never finished / re-queued over
  trending.py  library sweep at snapshot and after library changes; the chart
               API hands out only live song ids
  tests/test_links.py, test_api_batches.py  YouTube links are no longer refused
  tests/test_trending.py  a chart only hands out ids that are live library songs
  tests/test_worker.py    "in library" needs the title and the artist

usage: python patch_tgfetch.py <tg-fetcher root>
exit 0: patched or already patched; exit 2: a file is not the expected one
(nothing is written to any file).
"""
import sys
from pathlib import Path

P = []   # (relative file, old, new)

# ── links.py ─────────────────────────────────────────────────────────────────
P.append(("tgfetch/links.py",
'''    if host.endswith("youtube.com") or host == "youtu.be" or host.endswith("music.apple.com"):
        raise LinkError("Only Deezer and Spotify playlist links work. The music bot doesn't take this site.")
    raise LinkError("Only Deezer and Spotify playlist links work.")
''',
'''    from tgfetch import youtube_list            # server-fixes-v1: YouTube lists are read as names only
    if youtube_list.is_youtube_host(host):
        return "youtube", youtube_list.list_id(u)
    if host.endswith("music.apple.com"):
        raise LinkError("Only Deezer, Spotify and YouTube playlist links work. The music bot doesn't take this site.")
    raise LinkError("Only Deezer, Spotify and YouTube playlist links work.")
'''))
P.append(("tgfetch/links.py",
'''    """The link sent to the bot (and stored), without tracking parameters."""
    return (f"https://www.deezer.com/playlist/{pid}" if site == "deezer"
''',
'''    """The link sent to the bot (and stored), without tracking parameters."""
    if site == "youtube":                       # server-fixes-v1 (stored only; never sent to the bot)
        from tgfetch import youtube_list
        return youtube_list.canonical(pid)
    return (f"https://www.deezer.com/playlist/{pid}" if site == "deezer"
'''))
P.append(("tgfetch/links.py",
'''    own = http is None
    http = http or httpx.AsyncClient(timeout=TIMEOUT_S, headers=UA, follow_redirects=True)
''',
'''    if site == "youtube":                       # server-fixes-v1: ytmusicapi names only, never plain HTTP
        from tgfetch import youtube_list
        return await youtube_list.fetch(pid)
    own = http is None
    http = http or httpx.AsyncClient(timeout=TIMEOUT_S, headers=UA, follow_redirects=True)
'''))

# ── worker.py ────────────────────────────────────────────────────────────────
P.append(("tgfetch/worker.py",
'''from tgfetch import db, extras, links, llm
''',
'''from tgfetch import db, extras, links, llm, search_owned
'''))
P.append(("tgfetch/worker.py",
'''            owned = await asyncio.to_thread(lambda: check(query, library=library))
            if owned["verdict"] == "in_library":
                db.finish_search(self.conn, sid, "in_library", library=owned)
                return

            async def step(variant: str, n: int, total: int) -> None:
''',
'''            owned = await asyncio.to_thread(lambda: check(query, library=library))
            # server-fixes-v1: only a query naming the song AND its artist ends here; a title
            # alone is searched on the bot, and the owned song comes back as owned_hint.
            named = await asyncio.to_thread(search_owned.clearly_named, query, library)
            if named is not None:
                db.finish_search(self.conn, sid, "in_library", library=search_owned.verdict_for(named, query))
                return
            owned = search_owned.with_hint(owned)

            async def step(variant: str, n: int, total: int) -> None:
                if search_owned.is_superseded(self.conn, sid):     # server-fixes-v1: a newer search replaced it
                    raise search_owned.Superseded()
'''))
P.append(("tgfetch/worker.py",
'''        except SourceError as e:
            self._search_source_error(row, e)
        except Exception as e:
            log.exception("search %s failed", sid)
            db.finish_search(self.conn, sid, "failed", error=type(e).__name__)

    def _requeue_search(''',
'''        except search_owned.Superseded:
            log.info("search %s superseded by a newer search of the same user", sid)
        except SourceError as e:
            self._search_source_error(row, e)
        except Exception as e:
            log.exception("search %s failed", sid)
            db.finish_search(self.conn, sid, "failed", error=type(e).__name__)

    def _requeue_search('''))
P.append(("tgfetch/worker.py",
'''                library = self.load_library()
                for c in found:
                    c.library = "in_library" if self._owned_track(c, library) else "not_found"
                for i, c in enumerate(found):
''',
'''                library = self.load_library()
                from tgfetch import youtube_list    # server-fixes-v1
                if youtube_list.is_youtube_link(row["query"]):
                    from tgfetch import youtube_batch
                    youtube_batch.prepare(found, library, self._owned_track)
                else:
                    for c in found:
                        c.library = "in_library" if self._owned_track(c, library) else "not_found"
                for i, c in enumerate(found):
'''))
P.append(("tgfetch/worker.py",
'''        if not waiting:
            return
        silent = False
''',
'''        if not waiting:
            return
        from tgfetch import youtube_list            # server-fixes-v1: the bot never gets a YouTube link
        if youtube_list.is_youtube_link(b.get("link") or ""):
            from tgfetch import youtube_batch
            await youtube_batch.run(self, b, waiting)
            return
        silent = False
'''))

# ── api.py ───────────────────────────────────────────────────────────────────
P.append(("tgfetch/api.py",
'''from tgfetch import db, links, signing, trending
''',
'''from tgfetch import db, links, search_owned, signing, trending, youtube_batch
'''))
P.append(("tgfetch/api.py",
'''        return {"search_id": db.create_search(conn, who, query, kind=body.kind)}
''',
'''        sid = db.create_search(conn, who, query, kind=body.kind)
        search_owned.supersede_older(conn, who, sid)      # server-fixes-v1: the newer search replaces the older
        return {"search_id": sid}
'''))
P.append(("tgfetch/api.py",
'''        out["library"] = s["library"]
        out["candidates"] = [_pick(c, CANDIDATE_FIELDS) for c in s["candidates"]]
        return out
''',
'''        out["library"] = s["library"]
        out["candidates"] = [_pick(c, CANDIDATE_FIELDS) for c in s["candidates"]]
        # server-fixes-v1: the owned song with this title (a title-only search still searches);
        # for YouTube links, each song's original YouTube title and whether it could be read.
        out["owned_hint"] = search_owned.hint_of(s["library"])
        for c, row in zip(out["candidates"], s["candidates"]):
            yt = youtube_batch.meta(row)
            c["source_title"] = yt.get("raw") if yt else None
            c["unreadable"] = bool(yt.get("unreadable")) if yt else False
        return out
'''))

# ── db.py ────────────────────────────────────────────────────────────────────
P.append(("tgfetch/db.py",
'''    updated_at      REAL NOT NULL
);
"""
''',
'''    updated_at      REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS resolved_failures (
    job_id      INTEGER PRIMARY KEY,
    nd_song_id  TEXT,
    how         TEXT NOT NULL,
    resolved_at REAL NOT NULL
);
"""
'''))
P.append(("tgfetch/db.py",
'''    where, args = (f"j.status IN ({marks}) AND COALESCE(j.error, '') != 'cancelled'", list(FAILED_JOB))
''',
'''    where, args = (f"j.status IN ({marks}) AND COALESCE(j.error, '') != 'cancelled'", list(FAILED_JOB))
    # server-fixes-v1: a song that is in the library now (by any route) is not a failure any more.
    where += " AND j.id NOT IN (SELECT job_id FROM resolved_failures)"
'''))
P.append(("tgfetch/db.py",
'''        "title=COALESCE(?, title), note=?, updated_at=? WHERE id=?",
''',
'''        "title=COALESCE(?, title), note=?, updated_at=? WHERE id=? AND status!='superseded'",
'''))
P.append(("tgfetch/db.py",
'''    conn.execute("UPDATE searches SET status='queued', next_attempt_at=?, note=?, updated_at=? WHERE id=?",
''',
'''    conn.execute("UPDATE searches SET status='queued', next_attempt_at=?, note=?, updated_at=? "
                 "WHERE id=? AND status!='superseded'",
'''))

# ── trending.py ──────────────────────────────────────────────────────────────
P.append(("tgfetch/trending.py",
'''from tgfetch import db, extras, signing
''',
'''from tgfetch import db, extras, library_sweep, signing
'''))
P.append(("tgfetch/trending.py",
'''        date = date or today_ist(self.clock())
        library = self.load_library()
        result, queued = {}, 0
''',
'''        date = date or today_ist(self.clock())
        library = self.load_library()
        # server-fixes-v1: chart songs whose library id died (file replaced / re-tagged) are re-matched first.
        library_sweep.sweep(self.conn, library, owned=library_sweep.chart_owned(self, library), today=date)
        result, queued = {}, 0
'''))
P.append(("tgfetch/trending.py",
'''        await self.step()
        await self.maybe_summarise()
''',
'''        try:
            await library_sweep.maybe_sweep(self)       # server-fixes-v1: after a library scan / a new failure
        except Exception:
            log.exception("library sweep failed")
        await self.step()
        await self.maybe_summarise()
'''))
P.append(("tgfetch/trending.py",
'''            song_id = r["song_nd"] or r["nd_song_id"]        # the song's own, kept up to date
''',
'''            song_id = library_sweep.live_id(self, r["song_nd"], r["nd_song_id"])   # server-fixes-v1: live songs only
'''))

# ── tests/test_links.py (the old refusal of YouTube links) ───────────────────
P.append(("tests/test_links.py",
'''    ("https://www.youtube.com/playlist?list=PLx", "doesn't take this site"),
    ("https://music.youtube.com/playlist?list=PLx", "doesn't take this site"),
''',
'''    ("https://www.youtube.com/playlist?list=PLx", "doesn't look right"),
    ("https://music.youtube.com/playlist?list=PLx", "doesn't look right"),
'''))
P.append(("tests/test_links.py",
'''    ("https://example.com/playlist/1", "Only Deezer and Spotify"),
''',
'''    ("https://example.com/playlist/1", "Only Deezer, Spotify and YouTube"),
'''))
P.append(("tests/test_api_batches.py",
'''    assert r.status_code == 422 and "doesn't take this site" in r.json()["detail"]
''',
'''    assert r.status_code == 422 and "doesn't look right" in r.json()["detail"]     # server-fixes-v1
'''))

# ── tests that assumed any stored id plays, or a bare title means "owned" ───
P.append(("tests/test_trending.py",
'''    conn.execute("UPDATE trending_songs SET nd_song_id='nd1-full' WHERE key='saavn:s1'")
    assert t.chart("tamil")["entries"][0]["song_id"] == "nd1-full"
''',
'''    conn.execute("UPDATE trending_songs SET nd_song_id='nd1-full' WHERE key='saavn:s1'")
    # server-fixes-v1: only a live library song is handed out
    t.load_library = lambda: [dict(r) for r in LIB] + [{**LIB[0], "id": "nd1-full"}]
    assert t.chart("tamil")["entries"][0]["song_id"] == "nd1-full"
'''))
P.append(("tests/test_trending.py",
'''    conn.execute("UPDATE trending_songs SET status='added', nd_song_id='nd9' WHERE key='c'")
    e = t.chart("tamil")["entries"]
''',
'''    conn.execute("UPDATE trending_songs SET status='added', nd_song_id='nd9' WHERE key='c'")
    t.load_library = lambda: [dict(r) for r in LIB] + [{**LIB[0], "id": "nd9"}]   # server-fixes-v1: live ids only
    e = t.chart("tamil")["entries"]
'''))
P.append(("tests/test_worker.py",
'''    s = _search(conn, w, "kanne kanne")
    assert s["status"] == "in_library"
    assert src.searches == 0
''',
'''    s = _search(conn, w, "kanne kanne sam cs")     # server-fixes-v1: title AND artist named
    assert s["status"] == "in_library"
    assert src.searches == 0
'''))


def main(root: str) -> int:
    base = Path(root)
    texts, todo = {}, []
    for rel, old, new in P:
        path = base / rel
        if rel not in texts:
            if not path.exists():
                print(f"!! {path} not found")
                return 2
            texts[rel] = path.read_text(encoding="utf-8")
        text = texts[rel]
        if new in text:
            continue                                   # already patched
        n = text.count(old)
        if n != 1:
            print(f"!! {rel}: expected text found {n} times (not the version this package was built on)")
            print("   first line: " + old.strip().splitlines()[0][:100])
            return 2
        texts[rel] = text.replace(old, new)
        todo.append(rel)
    for rel in dict.fromkeys(todo):
        (base / rel).write_text(texts[rel], encoding="utf-8")
    print(f"patched: {', '.join(dict.fromkeys(todo)) or 'nothing (already patched)'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
