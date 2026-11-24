"""
navivibe/smart_pick.py  (smart-pick-v1)
───────────────────────────────────────
Smart Shuffle from a playlist: the model chooses the songs AND the order, and the owner's rule
holds: familiar songs first, cold songs last, never a cold opener.

The app sends the WHOLE remaining playlist as `candidates` (not a random 16). For that request
(`smart_candidates`), `serve()`:

  1. opener (session has no kept song yet): the v3 OPENER model scores the familiar candidates
     and one is drawn from the top (same sampling v3 uses for openers, restricted to familiar);
  2. the rest: v3 (+ the listener-memory order, as before) picks and orders songs among the
     FAMILIAR candidates by its own scores, conditioned on that opener; then, only after them, the
     cold candidates: one cold song closes a batch that is otherwise familiar (so new songs still
     get heard), more fill the end if there are not enough familiar songs;
  3. guardrails: no artist / film twice in a row where avoidable, no song twice, cold never first,
     at most one cold song in positions 2-7 (unless there are fewer than six familiar songs).

Familiar = this listener has played the song at least SMART_PICK_COLD_PLAYS times (default 3) AND
last played it no more than SMART_PICK_STALE_DAYS days ago (default 30). Chosen from the owner's
own log: songs with <3 earlier plays are skipped 22-30% in a session's first 7 slots against
8-15% for familiar ones, and a "familiar" song not played for over 30 days is skipped 31% (44% over
60 days) against 12.7%.

A listener with no familiar candidate (new account, or a playlist of unheard songs) gets exactly
the queue v3 gave before this package: nothing is left empty. Any error does the same.

SMART_PICK=on|off (default on). Decisions are written to the listener's log, table
`smart_pick_items` (served_id, rank, title, plays, days_since, familiar, decision, from_rank);
rank 0 is the batch summary. `served_items` / `served_batches` are untouched (play-events-v2).
"""
import os
import re
import time

COLD_PLAYS = int(float(os.getenv("SMART_PICK_COLD_PLAYS", "3")))
STALE_DAYS = float(os.getenv("SMART_PICK_STALE_DAYS", "30"))
EARLY = 7            # positions 2..7 may hold at most EARLY_COLD_CAP cold songs
EARLY_COLD_CAP = 1
DAY = 86400.0
KEY = "_sp"          # private per-entry decision, removed before the response is built
ID_PREFIX = "\x1fid\x1f"   # a candidate given by song id travels through v3 as this + the id
MAX_IDS = 3000
PLAYLIST_TTL = float(os.getenv("SMART_PICK_PLAYLIST_TTL", "30"))


def mode() -> str:
    return "off" if (os.getenv("SMART_PICK") or "on").strip().lower() == "off" else "on"


# ── the three input forms: titles (old apps), song ids, a playlist id ────────

def id_token(sid) -> str:
    return ID_PREFIX + str(sid)


def _id_list(raw) -> list:
    if isinstance(raw, str):
        sep = "|" if "|" in raw else ","
        raw = [x for x in raw.split(sep)]
    if not isinstance(raw, (list, tuple)):
        return []
    out, seen = [], set()
    for x in raw:
        x = str(x).strip()[:64]
        if x and x not in seen:
            seen.add(x)
            out.append(x)
        if len(out) >= MAX_IDS:
            break
    return out


def ids_request(data: dict, explicit_candidates):
    """(candidates, input_kind, exclude_tokens) for /next. `candidate_ids` (song ids) are added to
    whatever titles came; `exclude_ids` (songs already queued) are removed from the pool and are
    never picked. Without any of the new fields the request is returned untouched."""
    try:
        ids = _id_list(data.get("candidate_ids"))
        ex = _id_list(data.get("exclude_ids"))
    except Exception:  # noqa: BLE001
        return explicit_candidates, "titles" if explicit_candidates else "", []
    ex_tok = [id_token(x) for x in ex]
    cands = explicit_candidates
    kind = "titles" if cands else ""
    if ids:
        cands = set(cands or ()) | {id_token(x) for x in ids}
        kind = "ids" if not explicit_candidates else "ids+titles"
    if cands and ex_tok:
        cands = set(cands) - set(ex_tok)
    return cands, kind, ex_tok


def playlist_pool(nd_songs: list, exclude_tokens=()) -> set:
    """A Navidrome playlist's songs as candidates: by id when it has one (exact), else by title."""
    ex = set(exclude_tokens)
    out = set()
    for s in nd_songs or []:
        tok = id_token(s["id"]) if s.get("id") else s.get("title")
        if tok and tok not in ex:
            out.add(tok)
    return out


_pl_cache = {}


def cached(kind, key, fetch, ttl=None):
    """Small TTL cache for Navidrome playlist reads (the playlist the listener just tapped is read
    once per half minute, not once per refill). Empty answers are never cached."""
    ttl = PLAYLIST_TTL if ttl is None else ttl
    now = time.time()
    hit = _pl_cache.get((kind, key))
    if ttl > 0 and hit and now - hit[0] < ttl:
        return hit[1]
    val = fetch()
    if val and ttl > 0:
        if len(_pl_cache) > 200:
            _pl_cache.clear()
        _pl_cache[(kind, key)] = (now, val)
    return val


def resolve_one(eng, t):
    """Catalog id for a candidate: exact for an id token, the title resolver otherwise."""
    t = str(t)
    if t.startswith(ID_PREFIX):
        sid = t[len(ID_PREFIX):]
        return sid if sid in eng.cat.index else None
    return eng.resolver.resolve(t)


# ── pure part ────────────────────────────────────────────────────────────────

def is_familiar(plays: float, last_ts, now_ts: float, cold_plays: int = None, stale_days: float = None) -> bool:
    cold_plays = COLD_PLAYS if cold_plays is None else cold_plays
    stale_days = STALE_DAYS if stale_days is None else stale_days
    if plays < cold_plays:
        return False
    if stale_days > 0 and last_ts == last_ts and last_ts is not None and (now_ts - last_ts) / DAY > stale_days:
        return False
    return True


def _artist(e: dict) -> str:
    raw = (e.get("artist") or e.get("composer") or "")
    return re.split(r"[;,&/•]", raw)[0].strip().lower()


def _album(e: dict) -> str:
    return (e.get("album") or "").strip().lower()


def _space(items: list, prev: dict = None) -> list:
    """Same order, except that a song by the artist (or from the film) just played waits for the
    next song that is not. Unknown artist / album never clash. Nothing is dropped."""
    rest, out = list(items), []
    while rest:
        last = out[-1] if out else prev
        pick = None
        if last is not None:
            la, lf = _artist(last), _album(last)
            for e in rest:
                if (not la or _artist(e) != la) and (not lf or _album(e) != lf):
                    pick = e
                    break
            if pick is None:
                for e in rest:
                    if not la or _artist(e) != la:
                        pick = e
                        break
        pick = pick if pick is not None else rest[0]
        rest.remove(pick)
        out.append(pick)
    return out


def arrange(entries: list, fam, n: int, prev: dict = None, reserve_cold: bool = True) -> tuple:
    """(ordered, summary). `entries` = the model's picks in the model's order; `fam(e)` says whether
    the listener is familiar with the song. Returns at most n entries: familiar first (model
    order), cold after; if there are enough familiar songs one cold song still closes the batch.
    Nobody familiar: the model's own order, untouched (summary['degraded'])."""
    seen, uniq = set(), []
    for e in entries:                                   # no song twice
        k = e.get("navidrome_id") or e.get("title")
        if k in seen:
            continue
        seen.add(k)
        uniq.append(e)
    pos = {id(e): i + 1 for i, e in enumerate(uniq)}
    fams = [e for e in uniq if fam(e)]
    colds = [e for e in uniq if not fam(e)]
    summary = {"familiar": len(fams), "cold": len(colds), "degraded": ""}
    if not fams:
        summary["degraded"] = "no_familiar_model_order"
        return uniq[:n], summary, pos
    if len(fams) >= n and colds and reserve_cold and n >= 3:
        head, tail = fams[:n - 1], colds[:1]
    else:
        head, tail = fams[:n], colds[:max(0, n - len(fams[:n]))]
    head = _space(head, prev)
    tail = _space(tail, head[-1] if head else prev)
    out = head + tail
    early_cold = sum(1 for e in out[:EARLY - 1] if not fam(e))      # positions 2..7 after an opener
    if early_cold > EARLY_COLD_CAP:
        summary["degraded"] = "too_few_familiar_for_cold_cap"
    for e in head:
        e.setdefault(KEY, {})["decision"] = "familiar"
    for e in tail:
        e.setdefault(KEY, {})["decision"] = "cold_last"
    return out, summary, pos


# ── engine part ──────────────────────────────────────────────────────────────

class _Plays:
    """The listener's play counts and last-play times from v3's own user state (taken once)."""

    def __init__(self, eng, username, now_ts):
        with eng._lock_for(username):
            us = eng._user(username)
            self.raw = us.raw.copy()
            self.last = us.last_ts.copy()
        self.eng, self.now, self._memo = eng, now_ts, {}

    def index(self, title=None, sid=None):
        if sid is None:
            if title not in self._memo:                 # resolving can be fuzzy: once per title
                self._memo[title] = resolve_one(self.eng, title)
            sid = self._memo[title]
        return None if sid is None else self.eng.cat.index.get(sid)

    def familiar_idx(self, i) -> bool:
        return i is not None and is_familiar(float(self.raw[i]), float(self.last[i]), self.now)

    def info(self, i) -> dict:
        if i is None:
            return {"plays": 0, "days": None, "familiar": False}
        last = float(self.last[i])
        return {"plays": int(self.raw[i]), "days": None if last != last else round((self.now - last) / DAY, 1),
                "familiar": self.familiar_idx(i)}


def serve(smart_queue, v3_engine, model, username, context, session, count, candidates, reshuffle,
          now_ts=None):
    """(queue, engine) for a candidates request. Same contract as `_smart_queue`; never raises:
    off / no engine / no familiar candidate / any error -> the unchanged `_smart_queue` answer."""
    def plain():
        return smart_queue(model, username, context, session, count,
                           candidate_pool=candidates, reshuffle=reshuffle)
    try:
        if mode() != "on" or not candidates:
            return plain()
        eng = v3_engine()
        if eng is None:
            return plain()
        now_ts = now_ts or time.time()
        P = _Plays(eng, username, now_ts)
        with eng._lock_for(username):
            ctx = eng._session_ctx(username, session)
        played = set(ctx.played)
        fam_titles, n_cold = set(), 0
        for t in candidates:
            i = P.index(title=t)
            if i is None or i in played:
                continue
            if P.familiar_idx(i):
                fam_titles.add(t)
            else:
                n_cold += 1
        if not fam_titles:
            q, engine = plain()
            if q:
                q[0].setdefault(KEY, {})["batch"] = "all_cold n_cold=%d: model order" % n_cold
            return q, engine

        opener = None
        if not ctx.kept:
            res = eng.recommend(username, dict(session), n=1, candidate_titles=set(fam_titles),
                                reshuffle=False, frustration=bool(session.get("frustration_mode")))
            if res.get("queue"):
                opener = res["queue"][0]
        sess2 = dict(session)
        o_idx = P.index(sid=opener.get("navidrome_id")) if opener is not None else None
        if opener is not None:
            sess2["seed_title"] = id_token(opener["navidrome_id"]) if opener.get("navidrome_id") else opener["title"]
        fam_pool = {t for t in fam_titles if o_idx is None or P.index(title=t) != o_idx}
        cold_pool = {t for t in candidates if t not in fam_titles and P.index(title=t) is not None
                     and P.index(title=t) not in played}
        need = max(1, count - (1 if opener is not None else 0))
        # the model picks among the FAMILIAR songs (its own scores, the listener-memory order), then,
        # after them, among the cold ones; one cold song closes a batch that is otherwise familiar.
        close_cold = bool(cold_pool) and len(fam_pool) >= need and need >= 3
        n_fam = min(len(fam_pool), need - (1 if close_cold else 0))
        n_cold = min(len(cold_pool), need - n_fam)
        main, tail, engine, meta = [], [], "v3+memory", {}
        if n_fam > 0:
            main, engine = smart_queue(model, username, context, sess2, n_fam,
                                       candidate_pool=fam_pool, reshuffle=reshuffle)
        if n_cold > 0:
            sess3 = dict(sess2)
            if main:
                sess3["seed_title"] = id_token(main[-1]["navidrome_id"]) if main[-1].get("navidrome_id") else main[-1]["title"]
            tail, e2 = smart_queue(model, username, context, sess3, n_cold,
                                   candidate_pool=cold_pool, reshuffle=reshuffle)
            engine = engine if main else e2
        queue2 = list(main) + list(tail)
        if not queue2 and opener is None:
            return plain()
        for q in queue2:
            for k in ("_context_meta", "_starter_meta"):
                if k in q:
                    meta.setdefault(k, q.pop(k))

        def fam(e):
            return P.familiar_idx(P.index(sid=e.get("navidrome_id")))

        prev = opener if opener is not None else None
        ordered, summ, pos = arrange(queue2, fam, need, prev=prev, reserve_cold=False)
        out = ([opener] if opener is not None else []) + ordered
        for r, e in enumerate(out, 1):
            e["rank"] = r
            d = e.setdefault(KEY, {})
            d.update(P.info(P.index(sid=e.get("navidrome_id"))))
            if e is opener:
                d["decision"] = "opener_best_familiar"
                d["from_rank"] = 0
            else:
                d["from_rank"] = pos.get(id(e))
                d.setdefault("decision", "model_order")
        if out:
            for k, v in meta.items():
                out[0].setdefault(k, v)
            out[0].setdefault(KEY, {})["batch"] = (
                "opener=%s familiar=%d cold=%d%s" % ("yes" if opener is not None else "no", summ["familiar"],
                                                      summ["cold"], (" " + summ["degraded"]) if summ["degraded"] else ""))
        return out, engine
    except Exception as e:  # noqa: BLE001
        import traceback
        traceback.print_exc()
        print("[smart-pick] failed, the plain v3 queue is served: %s: %s" % (type(e).__name__, e))
        return plain()


# ── log ──────────────────────────────────────────────────────────────────────

_SCHEMA = """CREATE TABLE IF NOT EXISTS smart_pick_items (
    served_id TEXT NOT NULL, rank INTEGER NOT NULL, title TEXT, plays INTEGER, days_since REAL,
    familiar INTEGER, decision TEXT, from_rank INTEGER, PRIMARY KEY (served_id, rank))"""


def take_decisions(queue) -> list:
    """Remove the private decision from every entry (always, so it never reaches the client) and
    return rows (rank, title, plays, days, familiar, decision, from_rank); rank 0 = batch summary."""
    rows = []
    for i, q in enumerate(queue or []):
        if not isinstance(q, dict):
            continue
        d = q.pop(KEY, None)
        if not d:
            continue
        if d.get("batch"):
            rows.append((0, "", None, None, None, str(d["batch"])[:200], None))
        if "decision" in d:
            rows.append((int(q.get("rank") or i + 1), str(q.get("title") or "")[:300], d.get("plays"),
                         d.get("days"), 1 if d.get("familiar") else 0, str(d["decision"])[:60], d.get("from_rank")))
    return rows


def log_decisions(username, served_id, rows):
    """Best-effort, never raises."""
    if not rows:
        return
    try:
        from navivibe.play_events import _fb, ensure_schema
        fb = _fb()
        conn = fb._connect(ensure_schema(username))
        try:
            conn.execute(_SCHEMA)
            conn.executemany("INSERT OR REPLACE INTO smart_pick_items VALUES (?,?,?,?,?,?,?,?)",
                             [(served_id,) + r for r in rows])
            conn.commit()
        finally:
            conn.close()
    except Exception as e:  # noqa: BLE001
        print("[smart-pick] could not log decisions: %s" % e)


def erase_tables(conn):
    """DELETE /me/history."""
    try:
        conn.execute("DELETE FROM smart_pick_items")
    except Exception:  # noqa: BLE001  (table not created yet)
        pass
