"""
navivibe/flow_v2.py                                                     (flow-v2)
───────────────────
Flow, second version: the same blend of familiar, fresh and new-language songs that flow.py
builds, but the songs are chosen and ordered with the SOUND of each song in mind.

  FLOW_V2=off      (default) flow.py behaves exactly as before.
  FLOW_V2=shadow   flow.py serves what it always did; this module only works out how it would
                   have ordered those same songs and logs both (flow_v2/shadow.jsonl).
  FLOW_V2=on       the v2 behaviour below is served (and logged the same way).

What v2 does, in the order a batch is made:

  real numbers   Spotify's own energy / valence / tempo / key (spotify_details.db) replace the
                 calibrated guesses in the catalog wherever Spotify has the song (2,109 of 2,487);
                 every other song keeps the guess and is marked "predicted".
  chip fit       with a mood chip, a song's sound is compared with what that mood's songs in this
                 library sound like (mean and spread of energy and valence of its labelled
                 songs). A song whose real numbers sit far outside is dropped; the rest are
                 ranked by closeness, so the batch is drawn from the best fits, not any fit.
  skip history   a familiar song the listener often skipped scores lower.
  one artist     no artist fills more than a quarter of a batch (two in eight).
  order          the songs of a batch are sequenced to minimise the jump between neighbours
                 (energy, valence, tempo, key, sound of the track), keep one artist, film or
                 composer from touching, start from the song already at the end of the queue, and
                 lean toward familiar songs first, new ones later (a small effect, see the report).
  why            every song carries `flow`: its numbers, whether they are real or predicted, how
                 well it fits the chip and its place in the session.

Tried and left out: an energy arc over the session (warm-up for energetic/gym/angry, wind-down for the
quiet chips). A chip's songs sit in a narrow energy band, so the arc moved the average energy by 0.02 to
0.04, inside the noise of the old queues (docs/flow-better.md).
"""

import json
import logging
import math
import os
import re
import threading

import numpy as np

log = logging.getLogger("navivibe.flow_v2")

MODES = ("off", "shadow", "on")

FIT_W = 0.7                 # weight of the chip fit in a song's score (the base scores are z-scores)
FIT_MAX = 2.5               # real numbers further than this many spreads from the chip's profile: dropped
FIT_KEEP = 3                # ... unless that would leave fewer than this many batches of songs
SKIP_W = 1.0                # familiar: minus this times the share of a song's weight that was skips
BEAM = 48                   # sequencing keeps this many partial orders
W_ENERGY, W_VALENCE, W_TEMPO, W_KEY, W_SOUND = 1.0, 0.6, 0.5, 0.3, 0.4
W_COLD = 0.6                # sequencing: a new song early in the batch costs this much (opening: x3)
SAME_ARTIST_NEXT, SAME_ARTIST_NEAR, SAME_FILM_NEXT, SAME_COMPOSER_NEXT = 3.0, 1.0, 1.0, 0.7
SHADOW_MAX_BYTES = 20 * 1024 * 1024

_PITCH = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7,
          "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
_SPLIT = re.compile(r"[;,•&/·�]")
_warned = set()
_lock = threading.Lock()


def mode() -> str:
    """off, shadow or on, read from FLOW_V2 on every call; an unknown value is off, said once in the log."""
    v = (os.environ.get("FLOW_V2") or "off").strip().lower()
    if v in MODES:
        return v
    if v not in _warned:
        _warned.add(v)
        log.error("FLOW_V2=%r is not one of %s: Flow v2 stays off", v, "/".join(MODES))
    return "off"


# ── sound of each song ───────────────────────────────────────────────────────

_sound_cache = {"key": None, "meta": None, "table": {}, "overlay": {}}


def _real_rows() -> tuple:
    from navivibe import spotify_details
    return spotify_details.stamp(), spotify_details.rows()


def _key_mode(row: dict) -> tuple:
    mk = (row.get("musical_key") or "").strip().split()
    if len(mk) == 2 and mk[0] in _PITCH:
        return _PITCH[mk[0]], 1 if mk[1].lower() == "major" else 0
    return None, None


def tables(meta: dict) -> tuple:
    """(sound, overlay): sound[id] = {energy, valence, bpm, key, mode, real}; overlay[id] = the catalog row with
    Spotify's numbers in place of the guesses. Rebuilt when the catalog object or spotify_details.db changes."""
    stamp, real = _real_rows()
    with _lock:
        c = _sound_cache
        if c["meta"] is meta and c["key"] == stamp:
            return c["table"], c["overlay"]
    table, overlay = {}, {}
    for sid, row in meta.items():
        r = real.get(sid)
        if r and r.get("energy") is not None and r.get("valence") is not None:
            key, md = r.get("key"), r.get("mode")
            table[sid] = {"energy": float(r["energy"]), "valence": float(r["valence"]), "bpm": r.get("tempo") or row.get("bpm"),
                          "key": key if isinstance(key, int) and key >= 0 else None, "mode": md if md in (0, 1) else None,
                          "real": True}
            overlay[sid] = dict(row, energy=table[sid]["energy"], valence=table[sid]["valence"], bpm=table[sid]["bpm"])
        else:
            key, md = _key_mode(row)
            table[sid] = {"energy": row.get("energy"), "valence": row.get("valence"), "bpm": row.get("bpm") or row.get("tempo"),
                          "key": key, "mode": md, "real": row.get("feature_source") == "spotify"}
            overlay[sid] = row
    with _lock:
        _sound_cache.update(key=stamp, meta=meta, table=table, overlay=overlay)
    return table, overlay


# ── what each chip sounds like, in this library ──────────────────────────────

_profile_cache = {"at": 0.0, "key": None, "p": {}}
PROFILE_TTL_S = 600
MIN_PROFILE = 12


def profiles(overlay: dict, table: dict, labels: dict, now: float) -> dict:
    """{mood: (mean energy, mean valence, spread energy, spread valence)} from the library's own labelled songs with
    REAL numbers: first label = the mood (gym: the songs gym_fit accepts)."""
    with _lock:
        c = _profile_cache
        if c["key"] is overlay and now - c["at"] < PROFILE_TTL_S:
            return c["p"]
    from navivibe.catalog import mood_tags
    out = {}
    for m in mood_tags.FLOW_MOODS:
        if m == mood_tags.GYM:
            ids = [s for s, row in overlay.items() if table[s]["real"] and mood_tags.gym_fit(row, labels.get(s) or [])]
        else:
            ids = [s for s in overlay if table[s]["real"] and (labels.get(s) or [None])[0] == m]
        if len(ids) < MIN_PROFILE:
            continue
        e = np.array([table[s]["energy"] for s in ids])
        v = np.array([table[s]["valence"] for s in ids])
        out[m] = (float(e.mean()), float(v.mean()), max(float(e.std()), 0.05), max(float(v.std()), 0.05))
    with _lock:
        _profile_cache.update(at=now, key=overlay, p=out)
    return out


def distance(prof: tuple, snd: dict) -> float | None:
    """How many spreads a song sits from the chip's profile (energy and valence together); None without numbers."""
    if prof is None or snd is None or snd["energy"] is None or snd["valence"] is None:
        return None
    return math.hypot((snd["energy"] - prof[0]) / prof[2], (snd["valence"] - prof[1]) / prof[3])


# ── one batch ────────────────────────────────────────────────────────────────

class Run:
    """What v2 knows while one batch is built (created by begin())."""

    def __init__(self, mode_, user, mood, taste, meta, now, session, seen, count):
        self.mode, self.user, self.mood, self.taste, self.now = mode_, user, mood, taste, now
        self.session, self.count = session, count
        self.sound, self.overlay = tables(meta)
        self.meta_in = meta
        self.relaxed = False
        self.error = None
        self._artist_n = {}
        self.prof = None
        self.tail = None                                    # the song at the end of the queue now
        self.k0 = len(seen or [])                           # songs Flow has already put in this session's queue
        for s in reversed(list(seen or [])):
            if s in self.sound:
                self.tail = s
                break

    @property
    def on(self) -> bool:
        return self.mode == "on"

    @property
    def meta(self) -> dict:
        """The catalog rows to use: with Spotify's numbers when v2 is on, unchanged otherwise."""
        return self.overlay if self.on else self.meta_in

    def start_labels(self, labels: dict, now: float):
        if self.mood:
            self.prof = profiles(self.overlay, self.sound, labels, now).get(self.mood)

    # selection ───────────────────────────────────────────────────────────────
    def keep(self, ids: list, need: int) -> list:
        """With a chip: drop songs whose real numbers sit far from what the chip sounds like. Never drops so much that
        the chip cannot fill FIT_KEEP batches: then it keeps the closest and says so (`relaxed`)."""
        if not (self.on and self.mood and self.prof):
            return ids
        keep, drop = [], []
        for s in ids:
            snd = self.sound.get(s)
            d = distance(self.prof, snd) if snd and snd["real"] else None
            (drop if d is not None and d > FIT_MAX else keep).append((d, s))
        if len(keep) >= need * FIT_KEEP:
            return [s for _, s in keep]
        self.relaxed = True
        log.warning("flow v2: chip %s keeps %d of %d songs under the fit limit; relaxing it", self.mood, len(keep), len(ids))
        return ids

    def bonus(self, cands: list, familiar: bool) -> np.ndarray:
        """Added to the candidates' scores: closeness to the chip, minus skip history (familiar songs)."""
        out = np.zeros(len(cands))
        if not self.on or not cands:
            return out
        if self.prof is not None:
            d = np.array([distance(self.prof, self.sound.get(s)) if self.sound.get(s) else np.nan for s in cands], float)
            ok = ~np.isnan(d)
            if ok.sum() >= 2:
                z = -d[ok]
                sd = z.std()
                zs = (z - z.mean()) / sd if sd > 1e-9 else np.zeros_like(z)
                out[ok] += FIT_W * zs
        if familiar:
            for i, s in enumerate(cands):
                sk = self.taste.skip.get(s, 0.0)
                if sk > 0:
                    out[i] -= SKIP_W * sk / (sk + self.taste.play.get(s, 0.0))
        return out

    # one artist cannot fill a batch ─────────────────────────────────────────
    def artist_room(self, s: str) -> bool:
        cap = max(2, math.ceil(self.count / 4))
        return all(self._artist_n.get(a, 0) < cap for a in _artists(self.meta_in.get(s) or {}))

    def artist_take(self, s: str) -> None:
        for a in _artists(self.meta_in.get(s) or {}):
            self._artist_n[a] = self._artist_n.get(a, 0) + 1

    # ordering ────────────────────────────────────────────────────────────────
    def sequence(self, items: list, kinds: dict, emb=None, index: dict = None) -> list:
        """The batch's payload items in the order that costs least (beam search); `kinds` maps id -> familiar|fresh|explore."""
        n = len(items)
        if n < 3:
            return list(items)
        ids = [p["navidrome_id"] for p in items]
        order = _beam(self, ids, kinds, emb, index)
        return [items[i] for i in order]

    def cost_of(self, ids: list, kinds: dict, emb=None, index: dict = None) -> float:
        """The same cost the sequencer minimises, for an order given (used to log old against new)."""
        c = 0.0
        prev = self.tail
        for i, s in enumerate(ids):
            c += _step_cost(self, prev, s, i, len(ids), ids[:i], kinds, emb, index)
            prev = s
        return c

    def summary(self) -> dict:
        """The `flow_v2` block of the /flow/next answer (only present when FLOW_V2 is not off)."""
        out = {"mode": self.mode, "chip_profile": bool(self.prof), "relaxed": self.relaxed}
        if self.error:
            out["error"] = self.error
        return out

    # per-song explanation ────────────────────────────────────────────────────
    def explain(self, items: list, kinds: dict) -> None:
        for i, p in enumerate(items):
            s = p["navidrome_id"]
            snd = self.sound.get(s) or {}
            info = {"step": self.k0 + i + 1, "sound": "real" if snd.get("real") else "predicted"}
            for k in ("energy", "valence", "bpm"):
                if snd.get(k) is not None:
                    info[k] = round(float(snd[k]), 2) if k != "bpm" else int(round(snd[k]))
            if self.prof is not None:
                d = distance(self.prof, snd)
                if d is not None:
                    info["fit"] = round(d, 2)
            p["flow"] = info


def begin(user, mood, taste, meta, now, session=None, seen=(), count=8):
    """A Run for this batch, or None when FLOW_V2 is off."""
    m = mode()
    if m == "off":
        return None
    try:
        return Run(m, user, mood, taste, meta, now, session, seen, count)
    except Exception:
        log.exception("flow v2: sound data unavailable, serving the old Flow")
        return None


# ── sequencing ───────────────────────────────────────────────────────────────

def _artists(row: dict) -> set:
    return {re.sub(r"[\s.]+", "", a).lower() for a in _SPLIT.split(row.get("artist") or "") if a.strip()}


def _composer(row: dict) -> str:
    return re.sub(r"[\s.]+", "", (row.get("composer") or "")).lower()


def _tempo_gap(a, b) -> float:
    if not a or not b:
        return 0.0
    return min(1.0, min(abs(math.log2((a * m) / b)) for m in (0.5, 1.0, 2.0)))


def _key_gap(a: dict, b: dict) -> float:
    if a["key"] is None or b["key"] is None or a["mode"] is None or b["mode"] is None:
        return 0.0
    ca = (a["key"] * 7) % 12 if a["mode"] == 1 else ((a["key"] + 3) * 7) % 12
    cb = (b["key"] * 7) % 12 if b["mode"] == 1 else ((b["key"] + 3) * 7) % 12
    d = abs(ca - cb)
    return min(d, 12 - d) / 6.0


def transition(run: "Run", a: str, b: str, emb=None, index=None) -> float:
    """What it costs to play b after a: how far apart they sound."""
    sa, sb = run.sound.get(a), run.sound.get(b)
    if not sa or not sb:
        return 0.0
    c = 0.0
    if sa["energy"] is not None and sb["energy"] is not None:
        c += W_ENERGY * abs(sa["energy"] - sb["energy"])
    if sa["valence"] is not None and sb["valence"] is not None:
        c += W_VALENCE * abs(sa["valence"] - sb["valence"])
    c += W_TEMPO * _tempo_gap(sa["bpm"], sb["bpm"]) + W_KEY * _key_gap(sa, sb)
    if emb is not None and index is not None and a in index and b in index:
        c += W_SOUND * (1.0 - float(emb[index[a]] @ emb[index[b]])) / 2.0
    return c


def _step_cost(run, prev, s, pos, n, before, kinds, emb, index) -> float:
    c = transition(run, prev, s, emb, index) if prev else 0.0
    row = run.meta_in.get(s) or {}
    if prev:
        prow = run.meta_in.get(prev) or {}
        if _artists(row) & _artists(prow):
            c += SAME_ARTIST_NEXT
        if row.get("film") and row.get("film") == prow.get("film"):
            c += SAME_FILM_NEXT
        if _composer(row) and _composer(row) == _composer(prow):
            c += SAME_COMPOSER_NEXT
    for back in before[-3:-1]:                              # two songs before the previous one
        if _artists(row) & _artists((run.meta_in.get(back) or {})):
            c += SAME_ARTIST_NEAR
    if kinds.get(s, "fresh") != "familiar":
        c += W_COLD * (3.0 if pos == 0 else 1.0) * (1.0 - pos / max(n - 1, 1))
    return c


def _beam(run, ids, kinds, emb, index) -> list:
    n = len(ids)
    states = [(0.0, [], run.tail)]
    for pos in range(n):
        nxt = []
        for cost, seq, prev in states:
            used = set(seq)
            before = [ids[i] for i in seq]
            for j in range(n):
                if j in used:
                    continue
                c = cost + _step_cost(run, prev, ids[j], pos, n, before, kinds, emb, index)
                nxt.append((c, seq + [j], ids[j]))
        nxt.sort(key=lambda t: (t[0], t[1]))                # ties: the original order, so the result is stable
        states = nxt[:BEAM]
    return states[0][1]


# ── the log ──────────────────────────────────────────────────────────────────

def log_path() -> str:
    from navivibe.feedback import DB_DIR
    return os.path.join(DB_DIR, "flow_v2", "shadow.jsonl")


def record(run: "Run", old: list, new: list, kinds: dict, emb=None, index=None) -> None:
    """One line per batch: the order flow.py made and the order v2 makes of the same songs (`mode` says which was
    served: shadow serves `old`, on serves `new`). A write that fails is logged with its reason, never swallowed."""
    try:
        p = log_path()
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if os.path.exists(p) and os.path.getsize(p) > SHADOW_MAX_BYTES:
            if "full" not in _warned:
                _warned.add("full")
                log.error("flow v2: %s is over %d bytes; no more lines are written until it is moved", p, SHADOW_MAX_BYTES)
            return
        line = {"ts": round(run.now, 1), "user": run.user, "session": run.session, "mood": run.mood, "mode": run.mode,
                "k0": run.k0, "tail": run.tail, "old": old, "new": new, "kinds": [kinds.get(s) for s in old],
                "cost_old": round(run.cost_of(old, kinds, emb, index), 3),
                "cost_new": round(run.cost_of(new, kinds, emb, index), 3), "relaxed": run.relaxed}
        with _lock, open(p, "a", encoding="utf-8") as f:
            f.write(json.dumps(line) + "\n")
    except Exception:
        log.exception("flow v2: could not write the shadow log")
