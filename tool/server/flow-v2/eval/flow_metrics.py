"""Smoothness / quality measurements of a Flow queue. Independent of the Flow code under test:
uses REAL Spotify numbers (spotify_details.db) where the library has them."""
import math
from collections import Counter
import numpy as np

import flow_world as w

_REAL = None


def feats(eng):
    """{id: dict(energy, valence, tempo, danceability, loudness, key, mode, real)}"""
    global _REAL
    if _REAL is None:
        _REAL = w.real_overlay()
    out = {}
    for sid, r in eng.cat.meta.items():
        d = _REAL.get(sid)
        if d:
            out[sid] = dict(d, real=True)
            continue
        key, mode = None, None
        mk = (r.get("musical_key") or "").strip()
        parts = mk.split()
        if len(parts) == 2 and parts[0] in w.NOTE_PC:
            key, mode = w.NOTE_PC[parts[0]], 1 if parts[1] == "major" else 0
        out[sid] = dict(energy=r.get("energy"), valence=r.get("valence"), tempo=r.get("bpm"),
                        danceability=r.get("danceability"), loudness=r.get("loudness"), key=key, mode=mode,
                        real=(r.get("feature_source") == "spotify"))
    return out


def _tempo_gap(a, b):
    """relative tempo gap with half/double time folded (a 70 and a 140 bpm song mix fine)."""
    if not a or not b:
        return None
    best = min(abs(math.log2((a * m) / b)) for m in (0.5, 1, 2))
    return best


def _key_gap(a, b):
    """0 same / relative; up to 6 on the circle of fifths; None when unknown."""
    if a["key"] is None or b["key"] is None or a["mode"] is None or b["mode"] is None:
        return None
    ca = (a["key"] * 7) % 12 if a["mode"] == 1 else ((a["key"] + 3) * 7) % 12      # relative-major position
    cb = (b["key"] * 7) % 12 if b["mode"] == 1 else ((b["key"] + 3) * 7) % 12
    d = abs(ca - cb)
    return min(d, 12 - d)


def transitions(ids, F, emb=None, index=None):
    out = []
    for a, b in zip(ids, ids[1:]):
        fa, fb = F[a], F[b]
        t = {}
        if fa["energy"] is not None and fb["energy"] is not None:
            t["d_energy"] = abs(fa["energy"] - fb["energy"])
        if fa["valence"] is not None and fb["valence"] is not None:
            t["d_valence"] = abs(fa["valence"] - fb["valence"])
        g = _tempo_gap(fa["tempo"], fb["tempo"])
        if g is not None:
            t["d_tempo"] = g
        k = _key_gap(fa, fb)
        if k is not None:
            t["d_key"] = k
        if emb is not None:
            t["cos"] = float(emb[index[a]] @ emb[index[b]])
        out.append(t)
    return out


def summarize(queues, eng, user_langs=None, mood=None, meta=None):
    """queues: list of (user, mood, [ids]).  Returns dict of aggregate metrics."""
    F = feats(eng)
    meta = eng.cat.meta
    emb = eng.fb.au
    agg = {k: [] for k in ("d_energy", "d_valence", "d_tempo", "d_key", "cos")}
    n = same_artist = same_film = same_comp = 0
    short = long_ = instr = off_lang = 0
    songs = 0
    for user, md, ids in queues:
        for t in transitions(ids, F, emb, eng.cat.index):
            for k, v in t.items():
                agg[k].append(v)
        for a, b in zip(ids, ids[1:]):
            n += 1
            ra, rb = meta[a], meta[b]
            same_artist += bool(ra.get("artist") and ra.get("artist") == rb.get("artist"))
            same_film += bool(ra.get("film") and ra.get("film") == rb.get("film"))
            same_comp += bool(ra.get("composer") and ra.get("composer") == rb.get("composer"))
        for s in ids:
            songs += 1
            r = meta[s]
            d = r.get("duration") or 0
            short += d < 120
            long_ += d > 420
            instr += bool(r.get("instrumental"))
            if user_langs and (r.get("language") or "und") not in user_langs.get(user, set()):
                off_lang += 1
    res = {"queues": len(queues), "songs": songs, "transitions": n}
    for k, v in agg.items():
        if v:
            v = np.array(v)
            res[k] = {"mean": round(float(v.mean()), 3), "p90": round(float(np.percentile(v, 90)), 3), "n": len(v)}
    res.update(same_artist=round(same_artist / max(n, 1), 4), same_film=round(same_film / max(n, 1), 4),
               same_composer=round(same_comp / max(n, 1), 4), short_lt2min=round(short / max(songs, 1), 4),
               long_gt7min=round(long_ / max(songs, 1), 4), instrumental=round(instr / max(songs, 1), 4),
               off_language=round(off_lang / max(songs, 1), 4) if user_langs else None)
    return res


# independent mood check on REAL numbers (thresholds are plain, see docs/flow-better.md)
RULES = {
    "energetic": lambda f: f["energy"] >= 0.55,
    "calm": lambda f: f["energy"] <= 0.55,
    "happy": lambda f: f["valence"] >= 0.40,
    "sad": lambda f: f["valence"] <= 0.55,
    "romantic": lambda f: f["energy"] <= 0.80 and 0.15 <= f["valence"] <= 0.85,
    "angry": lambda f: f["energy"] >= 0.55 and f["valence"] <= 0.65,
    "devotional": lambda f: True,
    "gym": lambda f: f["energy"] >= 0.60 and (f["tempo"] or 0) >= 100,
}


def mood_agreement(queues, eng):
    """share of songs whose REAL numbers agree with the chip; only songs with real numbers are judged."""
    F = feats(eng)
    ok = tot = 0
    for user, md, ids in queues:
        if not md:
            continue
        for s in ids:
            f = F[s]
            if not f["real"] or f["energy"] is None or f["valence"] is None:
                continue
            tot += 1
            ok += bool(RULES[md](f))
    return {"judged": tot, "agree": round(ok / tot, 4) if tot else None}
