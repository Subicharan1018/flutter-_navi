"""Apply (or check) the smart-pick-v1 edits to the shuffle server's source.

    python patch.py <shuffle-root>            apply; every edit must match exactly once
    python patch.py <shuffle-root> --check    only report what is applied / pending / mismatching

Each edit is (file, marker, old, new); `marker` appears only after the edit, so a second run
changes nothing. An `old` that is missing or ambiguous aborts the run before any file is written
("the live code is not what this package was built on").
Built on the live server.py after play-events-v2 and hybrid-shadow-v1.
"""
import os
import sys

EDITS = []


def edit(rel, marker, old, new):
    EDITS.append((rel, marker, old, new))


# ── the candidates branch asks smart_pick.serve for the queue (it falls back to _smart_queue itself) ──
edit("navivibe/server.py", "_sp_serve(", '''            queue, engine = _smart_queue(model, username, context, session, count,
                                         candidate_pool=explicit_candidates, reshuffle=is_reshuffle)
            mode_used = "smart_candidates"''',
     '''            # smart-pick-v1: familiar first, cold last, the model chooses from the whole pool.
            # Never raises; off / no history / any error = the plain _smart_queue answer.
            from navivibe.smart_pick import serve as _sp_serve
            queue, engine = _sp_serve(_smart_queue, _v3_engine, model, username, context, session, count,
                                      explicit_candidates, is_reshuffle)
            mode_used = "smart_candidates"''')

# ── decisions leave the entries (never sent to the app) and go to the listener's log ──
edit("navivibe/server.py", "_sp_take(queue)", '''    served_id = log_served(username, session_id, queue, mode_used, engine, depth)
''', '''    served_id = log_served(username, session_id, queue, mode_used, engine, depth)
    try:    # smart-pick-v1: the private per-song decisions are removed and logged (table smart_pick_items)
        from navivibe.smart_pick import take_decisions as _sp_take, log_decisions as _sp_log
        _sp_log(username, served_id, _sp_take(queue))
    except Exception as _se:
        print(f"[smart-pick] decision log failed: {_se}")
''')

# ── DELETE /me/history also clears the decisions ──
edit("navivibe/server.py", "_sp_drop(c)", '''        erase_extra_tables(c)
''', '''        erase_extra_tables(c)
        from navivibe.smart_pick import erase_tables as _sp_drop
        _sp_drop(c)
''')

# ── the three input forms: titles (old apps), `candidate_ids` (song ids), `playlist_id` ──
edit("navivibe/server.py", "_sp_ids(data, explicit_candidates)", '''    # Auto-detect or switch mode based on present signals
''', '''    # smart-pick-v1: `candidate_ids` / `exclude_ids` (song ids) next to the old titles; same pool rules.
    from navivibe.smart_pick import (ids_request as _sp_ids, cached as _sp_cached,
                                     playlist_pool as _sp_pool)
    explicit_candidates, _sp_input, _sp_exclude = _sp_ids(data, explicit_candidates)

    # Auto-detect or switch mode based on present signals
''')
edit("navivibe/server.py", "list(_sp_exclude),", '''        "excluded_titles":      excluded_titles if is_reshuffle else [],
''', '''        "excluded_titles":      (excluded_titles if is_reshuffle else []) + list(_sp_exclude),
''')
edit("navivibe/server.py", '_sp_cached("pls"', '''        playlists = get_playlists(auth_header, username)
''', '''        playlists = _sp_cached("pls", username, lambda: get_playlists(auth_header, username))
''')
edit("navivibe/server.py", '_sp_cached("pl",', '''            nd_songs = get_playlist_songs(playlist_id, auth_header, username)
''', '''            nd_songs = _sp_cached("pl", (username, playlist_id),
                                  lambda: get_playlist_songs(playlist_id, auth_header, username))
''')
edit("navivibe/server.py", "_sp_pool(nd_songs", '''                candidate_pool = {s["title"] for s in nd_songs if s.get("title")}
''', '''                candidate_pool = _sp_pool(nd_songs, _sp_exclude)
''')
edit("navivibe/server.py", "# smart-pick-v1: the playlist the listener tapped", '''                queue, engine = _smart_queue(model, username, context, session, count,
                                             candidate_pool=candidate_pool, reshuffle=is_reshuffle)
''', '''                # smart-pick-v1: the playlist the listener tapped, read by id on the server
                from navivibe.smart_pick import serve as _sp_serve_pl
                queue, engine = _sp_serve_pl(_smart_queue, _v3_engine, model, username, context, session,
                                             count, candidate_pool, is_reshuffle)
''')
edit("navivibe/server.py", '"smart_pick": ({"v": 1', '''        "playlist_id": playlist_id or None,
''', '''        "playlist_id": playlist_id or None,
        "smart_pick": ({"v": 1, "input": _sp_input or ("playlist" if mode_used == "smart_playlist" else "")}
                       if mode_used in ("smart_candidates", "smart_playlist") else None),
''')
# ── v3 resolves a candidate given as a song id exactly (no title matching) ──
edit("navivibe/recsys/recommender.py", "# smart-pick-v1: an exact song id", '''        out = []
        for t in titles or []:
            sid = self.resolver.resolve(str(t))
''', '''        out = []
        for t in titles or []:
            if isinstance(t, str) and t.startswith("\\x1fid\\x1f"):   # smart-pick-v1: an exact song id
                if t[4:] in self.cat.index:
                    out.append(self.cat.index[t[4:]])
                continue
            sid = self.resolver.resolve(str(t))
''')


def run(root, check_only):
    texts, plan = {}, []
    for rel, marker, old, new in EDITS:
        path = os.path.join(root, rel)
        if rel not in texts:
            if not os.path.exists(path):
                print("!! missing file:", path)
                return 2
            with open(path, encoding="utf-8", newline="") as f:
                texts[rel] = f.read()
        text = texts[rel]
        if marker in text:
            plan.append((rel, marker, "applied"))
            continue
        n = text.count(old)
        if n != 1:
            plan.append((rel, marker, "MISMATCH (old text found %d times)" % n))
            continue
        plan.append((rel, marker, "pending"))
        texts[rel] = text.replace(old, new)
    for rel, marker, st in plan:
        print("  %-9s %-22s %s" % (st.split(" ")[0], rel, marker.strip()[:36].replace("\n", " ")))
    bad = [p for p in plan if p[2].startswith("MISMATCH")]
    for rel, marker, st in bad:
        print("!!", rel, marker.strip()[:36].replace("\n", " "), st)
    if bad:
        print("!! the live code is not what this package was built on; nothing written")
        return 1
    if check_only:
        return 0
    for rel, text in texts.items():
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8", newline="") as f:
            if f.read() == text:
                continue
        tmp = path + ".smart-pick-v1.tmp"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(run(sys.argv[1], "--check" in sys.argv))
