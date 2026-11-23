"""
navivibe/catalog/mood_fusion.py   (moods-v3)
────────────────────────────────────────────
One mood decision from all the evidence: the labeller's guess, the real sound, the tags, the lyrics.

Why. moods-v2 started from the labeller's answer and only removed a mood when a narrow rule fired, so
a wrong label survived by default. "Thalaivane" (Kanguva) is the case: an October label (calm, sad)
made with no lyrics and without the genre, never asked again; energy 0.69 is under v2's 0.75, its tempo
90 is under v2's 140, and the Action / Mass tag was not read by any rule. Here a mood must EARN its place:
the labeller's word is one vote, and a label with too little support is dropped (no mood, not a wrong one).

Sound numbers, best source first: spotify_details.db, then catalog.db rows with feature_source 'spotify',
then the essentia-calibrated estimate (trusted at 0.6: on 1,656 songs that have both, it is off by 0.10
energy and 0.14 valence on average).

Tempo is only a nudge: in this library calm and sad songs span the same 81-160 BPM as happy ones (half
and double time), so a hard "calm is slow" rule would be noise. It counts against calm only when the
energy is already middling.

score(mood) = labeller + sound x trust + tags + lyrics; a mood needs THRESHOLD and no conflict.
`confidence` is that score squashed to 0-1. It is an ordering, NOT a measured probability, until the
owner's marks (mood_review) calibrate it. Nothing here writes a file.
"""

import math

THRESHOLD = 1.0
NEED = {"romantic": 0.4, "devotional": 0.55}     # the words decide these: the sound can't add to their score
TRUST = {"spotify": 1.0, "estimate": 0.6, None: 0.0}
MOODS = ["sad", "romantic", "happy", "energetic", "calm", "devotional", "angry"]

_MASS = {"mass", "action", "action / mass"}
_DANCE = {"kuthu", "dance", "kuthu / dance", "party", "house", "dance-pop", "edm"}
_HYPE = {"hip hop", "hip-hop", "rap", "hip-hop/rap", "trap", "rock", "metal", "electronic", "rock / electronic"}


def tag_set(row: dict) -> set:
    out = {str(row.get("genre_primary") or "").lower()}
    for k in ("nd_genres", "tags"):
        raw = row.get(k)
        if isinstance(raw, str):
            import json
            try:
                raw = json.loads(raw)
            except ValueError:
                raw = None
        if isinstance(raw, dict):
            out |= {str(t).lower() for t, w in raw.items() if isinstance(w, (int, float)) and w >= 0.5}
        elif isinstance(raw, list):
            out |= {str(t).lower() for t in raw}
    return out - {""}


def sound(row: dict, details: dict = None) -> dict:
    """The best numbers we hold, all from ONE source (never a mix), and which source it was."""
    d = details or {}
    if d.get("energy") is not None and d.get("valence") is not None:
        src, r, tempo = "spotify", d, d.get("tempo")
    elif row.get("energy") is not None and row.get("valence") is not None:
        src, r, tempo = ("spotify" if row.get("feature_source") == "spotify" else "estimate"), row, row.get("bpm")
    else:
        return {"src": None}
    return {"src": src, "energy": float(r["energy"]), "valence": float(r["valence"]), "tempo": tempo,
            "danceability": r.get("danceability"), "acousticness": r.get("acousticness")}


def distinct(rx, text: str) -> int:
    """Different words matched: a chorus repeating one word is one piece of evidence, not eight."""
    return len({m.lower() for m in rx.findall(text or "")})


def features(row: dict, ev: dict = None, details: dict = None, sad_rx=None, anger_rx=None, devotional_rx=None) -> dict:
    ev = ev or {}
    lyrics = ev.get("lyrics") or ""
    tags = tag_set(row)
    meta_text = " ".join(str(row.get(k) or "") for k in ("film", "album", "genre_display"))
    return {**sound(row, details), "audio": ev.get("audio_mood") or {}, "has_lyrics": bool(lyrics.strip()),
            "sad_words": distinct(sad_rx, lyrics) if sad_rx else 0,
            "anger_words": distinct(anger_rx, lyrics) if anger_rx else 0,
            "devotional_lyrics": bool(devotional_rx and devotional_rx.search(lyrics)),
            "devotional_title": bool(devotional_rx and devotional_rx.search(str(row.get("title") or ""))),
            "devotional_other": bool(devotional_rx and devotional_rx.search(meta_text)),
            "mass": bool(tags & _MASS), "dance": bool(tags & _DANCE), "hype": bool(tags & _HYPE)}


def _ramp(x, lo, hi):
    """-1 at lo, +1 at hi, linear between; 0 when unknown."""
    if x is None:
        return 0.0
    return max(-1.0, min(1.0, 2 * (float(x) - lo) / (hi - lo) - 1))


def sound_score(mood: str, f: dict) -> float:
    """How much the sound supports the mood (about -1.5 to +1.5). Uninformative moods score 0."""
    if f.get("src") is None:
        return 0.0
    e, v, d, ac = f["energy"], f["valence"], f.get("danceability"), f.get("acousticness")
    a = f.get("audio") or {}
    gap = (a["happy"] - a["sad"]) if isinstance(a.get("happy"), (int, float)) and isinstance(a.get("sad"), (int, float)) else None
    if mood == "sad":
        return 0.6 * _ramp(v, 0.6, 0.2) + 0.4 * _ramp(e, 0.75, 0.35) + 0.3 * _ramp(gap, 0.3, -0.3) + 0.2 * _ramp(d, 0.75, 0.45)
    if mood == "happy":
        return 0.9 * _ramp(v, 0.3, 0.7) + 0.3 * _ramp(e, 0.35, 0.65) + 0.3 * _ramp(gap, -0.3, 0.3)
    if mood == "energetic":
        return 1.1 * _ramp(e, 0.45, 0.8) + 0.3 * _ramp(d, 0.4, 0.7) + 0.1 * _ramp(ac, 0.7, 0.1)
    if mood == "calm":
        return 1.0 * _ramp(e, 0.65, 0.4) + 0.3 * _ramp(ac, 0.1, 0.6) + 0.2 * _ramp(a.get("relaxed"), 0.4, 0.9)
    if mood == "angry":
        return 0.6 * _ramp(e, 0.5, 0.8) + 0.4 * _ramp(v, 0.8, 0.35) + 0.4 * _ramp(a.get("aggressive"), 0.1, 0.4)
    return 0.0                                  # romantic, devotional: the words decide, not the sound


def labeller_score(mood: str, raw: list, f: dict, meta: dict = None) -> float:
    """The labeller's vote: first label more than second; much less when it had no lyrics to read; a
    confident answer from lyrics (moods-v2 prompt) more than the unrated October labels."""
    if mood not in (raw or [])[:2]:
        return 0.0
    vote = 1.0 if raw[0] == mood else 0.7
    c = (meta or {}).get("c")
    if isinstance(c, (int, float)):
        vote *= {"lyrics": 1.4, "knowledge": 0.8, "sound": 0.5}.get(meta.get("b"), 1.0) * min(1.0, c / 0.8)
    if not f.get("has_lyrics"):
        vote *= 0.6
    return vote


def lyric_tag_score(mood: str, f: dict) -> float:
    if mood == "sad":
        return min(1.2, 0.5 * f.get("sad_words", 0)) if f.get("has_lyrics") else 0.0
    if mood == "angry":
        return min(0.8, 0.4 * f.get("anger_words", 0)) + (0.3 if f.get("mass") else 0)
    if mood == "energetic":
        return (0.6 if f.get("mass") else 0) + (0.5 if f.get("dance") else 0) + (0.2 if f.get("hype") else 0)
    if mood == "calm":
        return -0.5 if f.get("dance") else 0.0
    if mood == "romantic":
        return 0.2 if f.get("has_lyrics") else 0.0
    if mood == "devotional":
        return 0.6 * f.get("devotional_lyrics", False) + 0.5 * f.get("devotional_other", False) + 0.3 * f.get("devotional_title", False)
    return 0.0


def conflict(mood: str, f: dict) -> str | None:
    """Explicit contradictions: the mood is out whatever its score. Only from Spotify's own numbers or the
    curated tags, except where said."""
    e, v, tempo = f.get("energy"), f.get("valence"), f.get("tempo")
    real = f.get("src") == "spotify"
    e_hi = 0.0 if real else 0.07                # an estimate must be clearer
    strong_sad = f.get("sad_words", 0) >= 3
    if mood == "calm":
        if f.get("mass"):
            return "action / mass song"
        if e is not None and e >= 0.62 + e_hi:
            return f"energy {e:.2f} is too high for calm"
        if e is not None and e >= 0.52 + e_hi and f.get("dance"):
            return f"dance song with energy {e:.2f}"
        if e is not None and e >= 0.55 + e_hi and tempo and 125 <= tempo <= 180 and (f.get("acousticness") or 0) < 0.4:
            return f"energy {e:.2f} at {tempo:.0f} BPM"
    if mood == "sad":
        if f.get("mass") and (e or 0) >= 0.6:
            return f"action / mass song with energy {e:.2f}"
        if v is not None and v >= 0.55 + e_hi and not strong_sad:
            return f"valence {v:.2f} is too bright for sad"
        if e is not None and e >= 0.75 + e_hi and not strong_sad:
            return f"energy {e:.2f} is too high for sad"
    if mood == "happy" and v is not None and v < 0.28 - e_hi:
        return f"valence {v:.2f} is too dark for happy"
    if mood == "energetic" and e is not None and e < 0.4 - e_hi and not (f.get("hype") or f.get("dance")):
        return f"energy {e:.2f} is too low for energetic"       # rap and dance are spared: their energy number misreads
    if mood == "angry" and e is not None and e < 0.4 - e_hi and not f.get("anger_words"):
        return f"energy {e:.2f} is too low for angry"
    if mood == "devotional" and f.get("has_lyrics") and f.get("devotional_title") \
            and not f.get("devotional_lyrics") and not f.get("devotional_other"):
        return "only the title sounds devotional"
    if mood == "romantic" and f.get("mass") and (e or 0) >= 0.65 and not f.get("has_lyrics"):
        return "action / mass song with no lyrics to say it is a love song"
    return None


def may_add(mood: str, f: dict) -> bool:
    """Moods the evidence may give although the labeller didn't say them. Only 'energetic', only from
    Spotify's numbers: the other moods need words."""
    if mood != "energetic" or f.get("src") != "spotify":
        return False
    e = f["energy"]
    return bool((f.get("mass") and e >= 0.62) or (f.get("dance") and e >= 0.75) or
                (e >= 0.85 and (f.get("danceability") or 0) >= 0.6))


def decide(raw: list, f: dict, meta: dict = None) -> dict:
    """{"moods": [..2], "confidence": {mood: 0-1}, "dropped": [(mood, why)], "added": [..]}"""
    f = f or {"src": None}
    raw = [m for m in (raw or [])[:2] if m in MOODS]
    margin, dropped, added = {}, [], []
    trust = TRUST.get(f.get("src"), 0.0)
    if meta and isinstance(meta.get("c"), (int, float)) and meta["c"] < 0.5:      # moods-v2: unsure = no label
        return {"moods": [], "confidence": {}, "dropped": [(m, f"labeller unsure ({meta['c']:.2f})") for m in raw], "added": []}
    for m in raw + [m for m in MOODS if m not in raw and may_add(m, f)]:
        s = labeller_score(m, raw, f, meta) + trust * sound_score(m, f) + lyric_tag_score(m, f)
        need = NEED.get(m, THRESHOLD)
        why = conflict(m, f)
        if why is None and s < need:
            why = f"too little evidence ({s:.2f} of {need:.2f})"
        if why is None:
            margin[m] = s - need
            if m not in raw:
                added.append(m)
        elif m in raw:
            dropped.append((m, why))
    # The sound removes and adds moods; it does not reorder them. One exception: the labeller put "sad"
    # ahead of "romantic" for hundreds of plain love songs, so sad needs a sad word to come first.
    moods = [m for m in raw if m in margin]
    if moods == ["sad", "romantic"] and f.get("sad_words", 0) == 0:
        if sound_score("sad", f) < 0.5:
            dropped.append(("sad", "a love song: no sad words, and the sound is not clearly sad"))
            moods = ["romantic"]
        else:
            moods = ["romantic", "sad"]
    if added and len(moods) < 2:
        moods = added[:1] + moods if f.get("mass") else moods + added[:1]
    conf = {m: round(1 / (1 + math.exp(-2.0 * margin[m] - 0.4)), 2) for m in moods}
    return {"moods": moods, "confidence": conf, "dropped": dropped, "added": [m for m in added if m in moods]}


# ── agreement with Spotify's numbers: a fixed yardstick, NOT the rules above ─────────────────────

def disagreements(moods: list, snd: dict) -> list:
    """Plain contradictions between labels and Spotify's numbers. The same yardstick for old and new
    labels. It is circular for the new ones (the rules read the same numbers), so a better score here
    says the rules work as written, not that the moods are right. Only the owner's marks say that."""
    if snd.get("src") != "spotify":
        return []
    e, v, out = snd["energy"], snd["valence"], []
    for m in (moods or [])[:2]:
        if m == "calm" and e >= 0.6 or m == "sad" and v >= 0.5 or m == "sad" and e >= 0.7 \
                or m == "happy" and v < 0.35 or m in ("energetic", "angry") and e < 0.5:
            out.append(m)
    return out
