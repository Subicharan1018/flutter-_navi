"""Apply (or check) the play-events-v2 edits to the shuffle server's source.

    python patch.py <shuffle-root>            apply; every edit must match exactly once
    python patch.py <shuffle-root> --check    only report what is applied / pending / mismatching

Each edit is (file, marker, old, new). `marker` appears only after the edit, so a second run
changes nothing. An `old` that is missing or ambiguous aborts the whole run before any file
is written (the live code changed since this package was made: re-read it first).
"""
import os
import sys

EDITS = []


def edit(rel, marker, old, new):
    EDITS.append((rel, marker, old, new))


# ── server.py: /feedback ─────────────────────────────────────────────────────
edit("navivibe/server.py", "handle_feedback(", '''def feedback():
    username = g.username
    data = request.json or {}
    if not record_play(data, username):
        # Same play_id as one already stored: an app retry. Nothing more to do,
        # and the app must still get a 2xx so it can forget the play.
        return jsonify({"ok": True, "duplicate": True})
    title = data.get("title") or data.get("track_title") or "Unknown"
    print(f"[Feedback:{username}] Recorded play event for: {title}")

    # ── Update server-side session cache so the next /next call excludes it ──
    fb_session_id = str(data.get("session_id", "") or "").strip()
    # NB: `float(x or 1.0)` turned a 0.0 ratio (an instant skip) into a full listen.
    try:
        listen_ratio = float(data.get("listen_ratio"))
    except (TypeError, ValueError):
        listen_ratio = 1.0
    # Only add to played-history if the user actually listened (not a quick skip)
    if fb_session_id and title != "Unknown" and listen_ratio >= 0.3:
        cache_key = (username, fb_session_id)
        with _session_lock:
            cached = _session_played.setdefault(cache_key, [])
            if title not in set(cached):
                cached.append(title)
                print(f"[Session:{username}] +'{title}' via feedback → {len(cached)} played this session.")

    # Fold the play into the v3 user state right away, so the very next /next
    # already reflects what was just played or skipped.
    eng = _v3_engine()
    if eng is not None:
        try:
            eng.on_feedback(username, data)
        except Exception as e:
            print(f"[v3] feedback update failed: {e}")

    return jsonify({"ok": True})
''', '''def feedback():
    # play-events-v2: validated, idempotent, counted. See navivibe/play_events.py.
    from navivibe.play_events import handle_feedback
    body, code = handle_feedback(g.username, request.get_json(silent=True), _session_played,
                                 _session_lock, SESSION_CACHE_MAX, _v3_engine())
    return jsonify(body), code
''')

# ── server.py: /feedback/impressions ─────────────────────────────────────────
edit("navivibe/server.py", "record_impressions_once", '''    username = g.username
    data = request.json or {}

    def _as_list(v):''', '''    username = g.username
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        data = {}

    def _as_list(v):''')
edit("navivibe/server.py", "record_impressions_once(", '''    from navivibe.feedback import record_impressions
    record_impressions(username, shown, played)
    print(f"[Impressions:{username}] {len(shown)} shown, {len(played)} played.")
    return jsonify({"ok": True, "recorded": len(shown)})''', '''    from navivibe.play_events import record_impressions_once
    n = record_impressions_once(username, data.get("batch_id"), shown, played)
    print(f"[Impressions:{username}] {len(shown)} shown, {len(played)} played, counted {n}.")
    return jsonify({"ok": True, "recorded": n, "duplicate": n == 0})''')

# ── server.py: /next input parsing (a bad value was a 500) ───────────────────
edit("navivibe/server.py", "safe_int(data.get(\"depth\"", '''    if request.method == "POST":
        data = request.json or {}
    else:
        data = request.args.to_dict()

    depth        = int(data.get("depth", 0))
    streak_type  = data.get("genre_streak_type", "")
    streak_count = int(data.get("genre_streak_count", 0))
    count        = int(data.get("count", 15))

    # ── Source signals ──────────────────────────────────────────────────────
    playlist_id = data.get("playlist_id", "").strip()
    playlist_name = (data.get("playlist_name", "") or data.get("playlist", "")).strip()
    source      = data.get("source", "").strip().lower()
''', '''    if request.method == "POST":
        data = request.get_json(silent=True)
        if not isinstance(data, dict):
            data = {}
    else:
        data = request.args.to_dict()

    from navivibe.play_events import safe_int, safe_str
    depth        = safe_int(data.get("depth"), 0, 0, 100000)
    streak_type  = safe_str(data.get("genre_streak_type", ""))
    streak_count = safe_int(data.get("genre_streak_count"), 0, 0, 100000)
    count        = safe_int(data.get("count"), 15, 1, 200)

    # ── Source signals ──────────────────────────────────────────────────────
    playlist_id = safe_str(data.get("playlist_id", "")).strip()
    playlist_name = (safe_str(data.get("playlist_name", "")) or safe_str(data.get("playlist", ""))).strip()
    source      = safe_str(data.get("source", "")).strip().lower()
''')
edit("navivibe/server.py", "depth_in_reported", '''    if played_titles and int(data.get("depth", 0)) < len(played_titles):
        depth = len(played_titles)''', '''    if played_titles and safe_int(data.get("depth"), 0) < len(played_titles):  # depth_in_reported
        depth = len(played_titles)''')
edit("navivibe/server.py", "bound_session_cache(_session_played", '''            # Evict oldest sessions if cache is too large
            if len(_session_played) > SESSION_CACHE_MAX:
                oldest = next(iter(_session_played))
                del _session_played[oldest]
''', '''            # Evict oldest sessions if cache is too large (never the live one)
            from navivibe.play_events import bound_session_cache
            bound_session_cache(_session_played, max(1, SESSION_CACHE_MAX - 1), keep_key=cache_key)
''')

# ── server.py: record what /next served, hand the id back ────────────────────
edit("navivibe/server.py", "log_served(username", '''    ctx_meta     = queue[0].pop("_context_meta", {}) if queue else {}''',
     '''    from navivibe.play_events import log_served
    served_id = log_served(username, session_id, queue, mode_used, engine, depth)
    ctx_meta     = queue[0].pop("_context_meta", {}) if queue else {}''')
edit("navivibe/server.py", '"served_id": served_id', '''        "queue": queue,
        "mode":  mode_used,
        "engine": engine,''', '''        "queue": queue,
        "served_id": served_id,
        "mode":  mode_used,
        "engine": engine,''')

# ── server.py: erasing history must erase the v2 tables too ───────────────────
edit("navivibe/server.py", "erase_extra_tables", '''        n = c.execute("DELETE FROM play_events").rowcount
        c.commit()''', '''        n = c.execute("DELETE FROM play_events").rowcount
        from navivibe.play_events import erase_extra_tables
        erase_extra_tables(c)
        c.commit()''')

# ── weather.py: write the cache atomically (a reader never sees half a file) ──
edit("navivibe/weather.py", "os.replace(tmp, CACHE_PATH)", '''        with open(CACHE_PATH, "w") as f:
            json.dump(weather_data, f)''', '''        tmp = CACHE_PATH + ".tmp"
        with open(tmp, "w") as f:
            json.dump(weather_data, f)
        os.replace(tmp, CACHE_PATH)  # atomic: a reader never sees half a file''')

# ── recommender.py: fold a play by when it was played ────────────────────────
edit("navivibe/recsys/recommender.py", "_played_at", '''        now = datetime.now(IST)
        i = self.cat.index[sid]
        skipped = ratio < SKIP_RATIO''', '''        now = datetime.now(IST)
        # A play the app delivered late (offline outbox) keeps the hour it was played in. Decay
        # timestamps stay "now" so the counters never see time go backwards.
        try:
            hour_of_play = int(data["_local_hour"]) if data.get("_local_hour") is not None else None
            when = datetime.fromtimestamp(float(data["_played_at"]), IST) if data.get("_played_at") else now
        except (TypeError, ValueError, OverflowError, OSError):
            hour_of_play, when = None, now
        if hour_of_play is None or not 0 <= hour_of_play <= 23:
            hour_of_play = when.hour
        i = self.cat.index[sid]
        skipped = ratio < SKIP_RATIO''')
edit("navivibe/recsys/recommender.py", "hour_of_play, when.weekday()",
     '''            self._user(user).update(i, now.timestamp(), now.hour, now.weekday(), ratio, skipped,''',
     '''            self._user(user).update(i, now.timestamp(), hour_of_play, when.weekday(), ratio, skipped,''')

# ── scheduler.py: a failing rebuild no longer retries every minute forever ───
edit("navivibe/scheduler.py", "_rebuild_blocked", '''def model_rebuild_loop():
    while True:''', '''REBUILD_TIMEOUT_S = int(float(os.getenv("NAVIVIBE_REBUILD_TIMEOUT_S", "1800")))
_rebuild_fails = {}   # username -> (consecutive failures, retry not before epoch s)


def _rebuild_blocked(username):
    n, until = _rebuild_fails.get(username, (0, 0.0))
    return n > 0 and time.time() < until


def _rebuild_failed(username):
    n = _rebuild_fails.get(username, (0, 0.0))[0] + 1
    _rebuild_fails[username] = (n, time.time() + min(60 * 2 ** n, 3600))


def model_rebuild_loop():
    while True:''')
edit("navivibe/scheduler.py", "if _rebuild_blocked(username)", '''                    unprocessed = count_unprocessed(username)
''', '''                    if _rebuild_blocked(username):
                        continue
                    unprocessed = count_unprocessed(username)
''')
edit("navivibe/scheduler.py", "timeout=REBUILD_TIMEOUT_S", '''                            check=True
                        )
                        print(f"[Scheduler] {username}: preprocess complete. Reloading model...")''',
     '''                            check=True, timeout=REBUILD_TIMEOUT_S
                        )
                        _rebuild_fails.pop(username, None)
                        print(f"[Scheduler] {username}: preprocess complete. Reloading model...")''')
edit("navivibe/scheduler.py", "_rebuild_failed(username)\n", '''                except Exception as e:
                    print(f"[Scheduler] Error processing user '{username}': {e}")''',
     '''                except Exception as e:
                    _rebuild_failed(username)
                    print(f"[Scheduler] Error processing user '{username}': {e} (backing off)")''')

# ── sync_navidrome.py: the nightly import that wrote the burst rows ──────────
edit("navivibe/sync_navidrome.py", "ensure_schema(username)", '''    init_db(username)
    user_db_path = get_db_path(username)''', '''    from navivibe.play_events import ensure_schema
    ensure_schema(username)
    user_db_path = get_db_path(username)''')
edit("navivibe/sync_navidrome.py", "stand for a listen Navidrome would have counted", '''    user_conn = sqlite3.connect(user_db_path)
    existing_counts = {}
    try:
        cur = user_conn.cursor()
        cur.execute("SELECT track_title, COUNT(*) FROM play_events GROUP BY track_title")''', '''    user_conn = sqlite3.connect(user_db_path, timeout=30)
    existing_counts = {}
    try:
        cur = user_conn.cursor()
        # Only rows that stand for a listen Navidrome would have counted (>= 50 %, or an
        # earlier sync row). Counting skips made every skipped song look "already synced".
        cur.execute("SELECT track_title, COUNT(*) FROM play_events "
                    "WHERE (session_id = 'navidrome_sync' OR COALESCE(listen_ratio, 1.0) >= 0.5) "
                    "AND COALESCE(quality, '') != 'suspect_burst' GROUP BY track_title")''')
edit("navivibe/sync_navidrome.py", "no weather for past plays", '''    weather = get_cached_weather()
    weather_code = weather.get("weather_code") if weather else None
    temp_c = weather.get("temperature_c") if weather else None
''', '''    # no weather for past plays: the cache holds NOW, and the key read here ("weather_code")
    # never existed in it, so every synced row had a NULL code but today's temperature.
    weather_code = None
    temp_c = None
''')
edit("navivibe/sync_navidrome.py", "ndsync:", '''        for _ in range(diff):
            records_to_insert.append((''', '''        import hashlib
        title_key = hashlib.sha1(title.encode("utf-8")).hexdigest()[:16]
        for k in range(diff):
            # Navidrome only knows the LAST play time; the other `diff - 1` plays share it.
            # They are marked so an evaluation can drop the invented timestamps.
            synthetic_time = "synthetic_time" if k < diff - 1 else None
            records_to_insert.append((''')
edit("navivibe/sync_navidrome.py", "'ndsync:%s:%d'", '''                0,                 # processed (for scheduler rebuild)
            ))''', '''                0,                 # processed (for scheduler rebuild)
                'ndsync:%s:%d' % (title_key, existing_cnt + k + 1),   # idempotency key
                "navidrome_sync",  # origin
                synthetic_time,    # quality
                1,                 # schema_version
                "complete",        # event_type
            ))''')
edit("navivibe/sync_navidrome.py", "INSERT OR IGNORE INTO play_events", '''        user_conn = sqlite3.connect(user_db_path)
        try:
            user_conn.executemany(
                """
                INSERT INTO play_events (
                    track_title, file_path, genre_bucket, composer, played_at,
                    ist_timestamp, ist_hour, day_of_week, month, weather_code, temperature_c,
                    listen_ratio, duration_s, end_reason, session_id, session_depth,
                    genre_streak_type, genre_streak_count, volume, processed
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,''', '''        user_conn = sqlite3.connect(user_db_path, timeout=30)
        try:
            user_conn.executemany(
                """
                INSERT OR IGNORE INTO play_events (
                    track_title, file_path, genre_bucket, composer, played_at,
                    ist_timestamp, ist_hour, day_of_week, month, weather_code, temperature_c,
                    listen_ratio, duration_s, end_reason, session_id, session_depth,
                    genre_streak_type, genre_streak_count, volume, processed,
                    play_id, origin, quality, schema_version, event_type
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,''')


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
        print("  %-9s %-34s %s" % (st.split(" ")[0], rel, marker.strip()[:40]))
    if any(st.startswith("MISMATCH") for _, _, st in plan):
        print("!! the live code is not what this package was built on; nothing written")
        return 1
    if check_only:
        return 0
    for rel, text in texts.items():
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8", newline="") as f:
            if f.read() == text:
                continue
        tmp = path + ".play-events-v2.tmp"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(run(sys.argv[1], "--check" in sys.argv))
