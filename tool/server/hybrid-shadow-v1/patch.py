"""Apply (or check) the hybrid-shadow-v1 edits to the shuffle server's source.

    python patch.py <shuffle-root>            apply; every edit must match exactly once
    python patch.py <shuffle-root> --check    only report what is applied / pending / mismatching

Needs play-events-v2 (it provides `served_id` in /next). Each edit is (file, marker, old, new);
`marker` appears only after the edit, so a second run changes nothing. An `old` that is missing
or ambiguous aborts the run before any file is written.
"""
import os
import sys

EDITS = []


def edit(rel, marker, old, new):
    EDITS.append((rel, marker, old, new))


# ── server.py: serve the hybrid order when HYBRID_ORDER=on (next-song positions only) ──
edit("navivibe/server.py", "_hybrid_serve(", '''    from navivibe.play_events import log_served
    served_id = log_served(username, session_id, queue, mode_used, engine, depth)''',
     '''    # hybrid-shadow-v1: with HYBRID_ORDER=on, next-song positions are served in the hybrid's
    # order (openers stay on v3). Off / shadow: returns the queue untouched. Never raises.
    try:
        from navivibe.hybrid_shadow import maybe_serve as _hybrid_serve
        queue, engine = _hybrid_serve(queue, engine, username, session, explicit_candidates,
                                      mode_used, is_reshuffle, count)
    except Exception as _he:
        print(f"[hybrid-shadow] serve hook failed, v3 queue kept: {_he}")
    from navivibe.play_events import log_served
    served_id = log_served(username, session_id, queue, mode_used, engine, depth)''')

# ── server.py: the response is built into `resp`, the shadow job is queued after it is sent ──
edit("navivibe/server.py", "resp = jsonify({\n        \"queue\": queue,", '''    return jsonify({
        "queue": queue,
        "served_id": served_id,''', '''    resp = jsonify({
        "queue": queue,
        "served_id": served_id,''')
edit("navivibe/server.py", "_hybrid_hook(resp", '''            "n_plays_in_profile": ctx_meta.get("n_plays_in_profile"),
        },
    })
''', '''            "n_plays_in_profile": ctx_meta.get("n_plays_in_profile"),
        },
    })
    # hybrid-shadow-v1: queued from call_on_close, i.e. after the body is sent. Never raises.
    try:
        from navivibe.hybrid_shadow import hook as _hybrid_hook
        _hybrid_hook(resp, username, session, served_id, queue, mode_used, is_reshuffle, explicit_candidates)
    except Exception as _he:
        print(f"[hybrid-shadow] hook failed: {_he}")
    return resp
''')

# ── recsys/recommender.py: score the hybrid on each kept play, BEFORE the state learns it ──
edit("navivibe/recsys/recommender.py", "play_hook(self, user", '''            kept = s.ctx.kept
            self._user(user).update(i, now.timestamp(), hour_of_play, when.weekday(), ratio, skipped,''',
     '''            kept = s.ctx.kept
            try:    # hybrid-shadow-v1: rank the played song with v3 / blend / hybrid, pre-update state
                from navivibe.hybrid_shadow import play_hook
                play_hook(self, user, i, s, ratio, now, hour_of_play, when, data)
            except Exception as _he:
                print(f"[hybrid-shadow] play hook failed: {_he}")
            self._user(user).update(i, now.timestamp(), hour_of_play, when.weekday(), ratio, skipped,''')

# ── server.py: DELETE /me/history also clears the shadow rows ──
edit("navivibe/server.py", "erase_tables(c)", '''        erase_extra_tables(c)
''', '''        erase_extra_tables(c)
        from navivibe.hybrid_shadow import erase_tables
        erase_tables(c)
''')

# ── scheduler.py: nightly fit with timeout and back-off ──
edit("navivibe/scheduler.py", "def hybrid_fit_loop", '''def start_background_scheduler(model_manager: dict = None, on_v3_update=None):''',
     '''HYBRID_FIT_HOUR_IST = float(os.getenv("HYBRID_FIT_HOUR_IST", "3.9"))   # 03:54 IST, after the v3 retrain
HYBRID_FIT_TIMEOUT_S = int(float(os.getenv("HYBRID_FIT_TIMEOUT_S", "1800")))
HYBRID_FIT_TRIES = 3


def hybrid_fit_loop():
    """hybrid-shadow-v1: nightly fit of the hybrid re-ranker (a separate small process, so a
    crash or a hang cannot touch the server). Skipped while HYBRID_ORDER=off. A failure is
    retried after 10, 20, 40 minutes (max 1 h) and then left until the next night."""
    while True:
        time.sleep(_seconds_until_ist(HYBRID_FIT_HOUR_IST))
        if (os.getenv("HYBRID_ORDER") or "shadow").strip().lower() == "off":
            continue
        for attempt in range(HYBRID_FIT_TRIES):
            try:
                r = subprocess.run([PYTHON, "-m", "navivibe.hybrid_train"], cwd="/opt/shuffle-server",
                                   env=ENV, capture_output=True, text=True, timeout=HYBRID_FIT_TIMEOUT_S)
                if r.returncode == 0:
                    print(f"[Scheduler] hybrid fit done: {r.stdout[-600:]}")
                    break
                print(f"[Scheduler] hybrid fit failed ({r.returncode}): {(r.stderr or r.stdout)[-600:]}")
            except Exception as e:
                print(f"[Scheduler] hybrid fit error: {e}")
            time.sleep(min(600 * 2 ** attempt, 3600))


def start_background_scheduler(model_manager: dict = None, on_v3_update=None):''')
edit("navivibe/scheduler.py", "target=hybrid_fit_loop", '''    threading.Thread(target=weekly_mix_loop, daemon=True).start()''',
     '''    threading.Thread(target=weekly_mix_loop, daemon=True).start()
    threading.Thread(target=hybrid_fit_loop, daemon=True).start()''')


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
            hint = " (is play-events-v2 installed?)" if "served_id" in old else ""
            plan.append((rel, marker, "MISMATCH (old text found %d times)%s" % (n, hint)))
            continue
        plan.append((rel, marker, "pending"))
        texts[rel] = text.replace(old, new)
    for rel, marker, st in plan:
        print("  %-9s %-30s %s" % (st.split(" ")[0], rel, marker.strip()[:36].replace("\n", " ")))
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
        tmp = path + ".hybrid-shadow-v1.tmp"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(run(sys.argv[1], "--check" in sys.argv))
