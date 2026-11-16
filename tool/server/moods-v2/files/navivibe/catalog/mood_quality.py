"""
navivibe/catalog/mood_quality.py   (moods-v2)
────────────────────────────────
Turns the labeller's raw guesses (mood_tags.json) into the labels the server actually uses.

    effective label = admin label (mood_admin.json)            if an admin set one
                    = raw LLM label - moods the evidence rules out
                      (nothing at all when the labeller itself was unsure)

Why: a sample of 54 songs (tests/fixtures/mood_reference.json) had the first label wrong for 9.
Most were "sad" on upbeat love songs (the labeller over-uses sad), a word in the title or a short
prayer taken for the mood ("Pudikala" = "I don't like" read as angry; "Rab" said to a lover read
as devotional), and "calm" on fast loud songs. Each rule below needs the audio AND the missing
lyric evidence to agree before it drops a mood, so a correct label survives; when nothing is
left the song has no label, which is better than a wrong one (it just doesn't join mood lists).

Admin labels (the mood editor, GET /moods/editor) are the truth for everyone, stored with who
and when, and never overwritten by a relabel. Per-listener "Not this mood" marks stay in
navivibe/mood_overrides.py and apply on top.

The rule facts (energy, valence, bpm, essentia scores, lyric word counts) come from catalog.db
and are cached per catalog change; a refresh runs in the background so no request waits.
"""

import json
import logging
import os
import re
import threading
import time

log = logging.getLogger(__name__)

MIN_CONFIDENCE = 0.5         # a label the labeller rated below this is not used

# Added to both labeller prompts (mood_tags.SYSTEM, mood_lyrics.SYSTEM_EN): the mistakes the
# reference sample showed, and the confidence the rules read.
PROMPT_RULES = (
    " Rules: judge what the lyrics say as a whole, never one word of the title or film name (a hook "
    "like 'I don't like this, I like only you' is a playful love song, not angry; 'God' or 'heaven' "
    "said to a lover is romantic, not devotional). 'sad' only when the lyrics are about loss, "
    "separation, pain or longing; a happy or loving song with a slow beat is romantic or calm, not "
    "sad. 'devotional' only when the song prays to or praises a god or saint. 'calm' only for "
    "gentle, quiet songs. For each song also give confidence (0 to 1) and basis: 'lyrics' when the "
    "lyrics decided it, 'knowledge' when you know the song, 'sound' when only the audio numbers "
    "were there. When unsure, give confidence below 0.5.")

# ── lyric evidence ───────────────────────────────────────────────────────────

_SAD_WORDS = re.compile(
    r"\b(?:cry|crying|cried|tears?|alone|lonely|goodbye|broken|heartbreak|heartbroken|hurts?|pain|"
    r"miss you|lost you|without you|gone|dying|sorrow|grief|kanneer|kaneer|azhu\w*|pirivu|pirindh\w*|"
    r"thanimai|sogam|soham|udaindh\w*|izhandh\w*|yengu\w*|maranam|aansu|dard|tanha|judaa?|akela)\b|"
    r"கண்ணீர்|அழு|பிரிவ|பிரிந்|வலி|தனிமை|சோக|உடைந்|இழந்|மரண|ஏங்கு|"
    r"आँसू|आंसू|दर्द|तन्हा|जुदा|अकेल|"
    r"കണ്ണീര്|കണ്ണീർ|വേദന|വിരഹ|ഏകാന്ത", re.I)
_ANGER_WORDS = re.compile(
    r"\b(?:hate|kill|fight|war|revenge|enemy|blood|rage|fury|pagai|kobam|kovam|veri|ratham|kolla\w*)\b|"
    r"போர்|எதிரி|ரத்த|கொல்|வெறி|பகை|கோப|"
    r"युद्ध|दुश्मन|खून|बदला", re.I)


def _devotional():
    from navivibe.catalog.mood_audit import _DEVOTIONAL
    return _DEVOTIONAL


def song_facts(row: dict, ev: dict = None) -> dict:
    """What the rules look at for one song (row from catalog.db, ev from mood_tags.evidence)."""
    ev = ev or {}
    lyrics = ev.get("lyrics") or ""
    dev = _devotional()
    return {
        "energy": row.get("energy"),
        "valence": row.get("valence"),
        "bpm": row.get("bpm") or row.get("tempo"),
        "audio": ev.get("audio_mood") or {},
        "has_lyrics": bool(lyrics.strip()),
        "sad_words": len(_SAD_WORDS.findall(lyrics)),
        "anger_words": len(_ANGER_WORDS.findall(lyrics)),
        "devotional_lyrics": bool(dev.search(lyrics)),
        "devotional_title": bool(dev.search(str(row.get("title") or ""))),
        "devotional_other": bool(dev.search(" ".join(str(row.get(k) or "") for k in ("film", "album", "genre_display")))),
    }


def _ge(v, x):
    return v is not None and v >= x


def _lt(v, x):
    return v is not None and v < x


def ruled_out(mood: str, f: dict) -> str | None:
    """Why the evidence rules this mood out for the song (None: it doesn't)."""
    a = f.get("audio") or {}
    happy, sad = a.get("happy"), a.get("sad")
    e, v, bpm = f.get("energy"), f.get("valence"), f.get("bpm")
    if mood == "sad" and f.get("sad_words", 0) < 2:
        # With no lyrics to read, the sound alone must be clearly happy.
        gap = 0.2 if f.get("has_lyrics") else 0.3
        if _ge(v, 0.6) and happy is not None and sad is not None and happy - sad >= gap:
            return "sounds happy, lyrics don't say sad"
        if _ge(e, 0.8) and _ge(v, 0.55):
            return "loud and bright, lyrics don't say sad"
    if mood == "happy" and _lt(v, 0.3) and _ge(sad, 0.6) and happy is not None and happy <= 0.3:
        return "sounds sad"
    if mood == "angry" and not f.get("anger_words") and _lt(a.get("aggressive"), 0.25) and _ge(v, 0.6):
        return "sounds bright and gentle, lyrics aren't angry"
    if mood == "calm":
        if _ge(e, 0.75):
            return "too loud for calm"
        if _ge(e, 0.6) and _ge(bpm, 140) and _lt(a.get("relaxed"), 0.75):
            return "fast and loud"
    # No "too quiet for energetic" rule: the energy number misreads rap and folk (Without Me,
    # Oorum Blood, Ei Suzhali, Superman all lost a right "energetic" in the held-out check).
    if mood == "devotional" and f.get("has_lyrics") and f.get("devotional_title") \
            and not f.get("devotional_lyrics") and not f.get("devotional_other"):
        return "only the title sounds devotional"
    return None


def sanity(tags: list, facts: dict = None, meta: dict = None) -> list:
    """The labels that survive the rules (most fitting first, at most 2)."""
    if not tags:
        return []
    if meta and isinstance(meta.get("c"), (int, float)) and meta["c"] < MIN_CONFIDENCE:
        return []
    if not facts:
        return list(tags)[:2]
    return [m for m in tags if not ruled_out(m, facts)][:2]


def explain(tags: list, facts: dict = None, meta: dict = None) -> list:
    """[(mood, reason)] for every raw label the rules drop (for the editor's "flagged")."""
    out = []
    if meta and isinstance(meta.get("c"), (int, float)) and meta["c"] < MIN_CONFIDENCE:
        return [(m, f"labeller unsure ({meta['c']:.2f})") for m in tags or []]
    for m in tags or []:
        why = ruled_out(m, facts or {}) if facts else None
        if why:
            out.append((m, why))
    return out


# ── files next to mood_tags.json ─────────────────────────────────────────────

def _dir(path: str = None) -> str:
    from navivibe.catalog import mood_tags
    return os.path.dirname(path or mood_tags.PATH)


def admin_path(path: str = None) -> str:
    return os.path.join(_dir(path), "mood_admin.json")


def meta_path(path: str = None) -> str:
    return os.path.join(_dir(path), "mood_meta.json")


def _read(p: str) -> dict:
    try:
        with open(p, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _write(p: str, data: dict) -> None:
    with open(p + ".tmp", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(p + ".tmp", p)


_write_lock = threading.Lock()


def load_admin(path: str = None) -> dict:
    """{song_id: {"moods": [..], "by": user, "at": iso time}}; moods may be [] ("no mood")."""
    from navivibe.catalog import mood_tags
    out = {}
    for sid, e in _read(admin_path(path)).items():
        if isinstance(e, dict) and isinstance(e.get("moods"), list):
            out[sid] = {**e, "moods": [m for m in e["moods"] if m in mood_tags.FLOW_MOODS][:2]}
    return out


def clean_moods(raw) -> list | None:
    """Well-formed admin moods: a list of known moods, no repeats, at most 2, in order; None if not."""
    from navivibe.catalog import mood_tags
    if not isinstance(raw, list) or len(raw) > 2:
        return None
    out = []
    for m in raw:
        m = str(m).strip().lower() if isinstance(m, str) else None
        if m not in mood_tags.FLOW_MOODS or m in out:
            return None
        out.append(m)
    return out


def set_admin(song_id: str, moods: list, user: str, path: str = None, now: float = None) -> dict:
    """An admin's label for the song: it becomes everyone's label and beats the labeller."""
    with _write_lock:
        data = _read(admin_path(path))
        entry = {"moods": list(moods), "by": user,
                 "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now or time.time()))}
        data[song_id] = entry
        _write(admin_path(path), data)
        return entry


def clear_admin(song_id: str, path: str = None) -> bool:
    """Back to the labeller's label. True when there was an admin label."""
    with _write_lock:
        data = _read(admin_path(path))
        if song_id not in data:
            return False
        data.pop(song_id)
        _write(admin_path(path), data)
        return True


def load_meta(path: str = None) -> dict:
    return _read(meta_path(path))


def meta_from(answer, rows: list) -> dict:
    """{song_id: {"c": confidence, "b": basis}} from a set_moods answer."""
    out = {}
    for it in (answer or {}).get("songs") or []:
        n = it.get("n") if isinstance(it, dict) else None
        if not isinstance(n, int) or isinstance(n, bool) or not 1 <= n <= len(rows):
            continue
        m = {}
        c = it.get("confidence")
        if isinstance(c, (int, float)) and not isinstance(c, bool):
            m["c"] = round(min(max(float(c), 0.0), 1.0), 2)
        if it.get("basis") in ("lyrics", "knowledge", "sound"):
            m["b"] = it["basis"]
        if m:
            out[rows[n - 1]["id"]] = m
    return out


def record_meta(meta: dict, path: str = None) -> None:
    """Keep the labeller's confidence next to the labels (bookkeeping: never fails the labelling)."""
    if not meta:
        return
    try:
        with _write_lock:
            data = _read(meta_path(path))
            data.update(meta)
            _write(meta_path(path), data)
    except OSError as e:
        log.warning("mood meta not saved: %s", e)


# ── facts cache (catalog.db) ────────────────────────────────────────────────

class _Facts:
    def __init__(self):
        self.lock = threading.Lock()
        self.stamp = None
        self.data = None
        self.busy = False

    @staticmethod
    def _stamp():
        from navivibe.catalog import store
        out = []
        for p in (store.CATALOG_DB, store.CATALOG_DB + "-wal"):
            try:
                out.append(os.stat(p).st_mtime_ns)
            except OSError:
                out.append(0)
        return tuple(out)

    @staticmethod
    def _build() -> dict:
        from navivibe.catalog import mood_tags, store
        if not os.path.exists(store.CATALOG_DB):
            return {}
        rows = store.load_catalog()
        ids = list(rows)
        ev = {}
        for i in range(0, len(ids), 400):
            ev.update(mood_tags.evidence(ids[i:i + 400]))
        return {s: song_facts(rows[s], ev.get(s)) for s in ids}

    def _refresh(self, stamp):
        try:
            data = self._build()
            with self.lock:
                self.data, self.stamp = data, stamp
        except Exception as e:                        # the old facts stay in use
            log.warning("mood facts refresh failed: %s", e)
        finally:
            self.busy = False

    def get(self) -> dict:
        stamp = self._stamp()
        if self.data is None:                          # the first time: build now
            self._refresh(stamp)
            return self.data or {}
        if stamp != self.stamp and not self.busy:
            self.busy = True
            threading.Thread(target=self._refresh, args=(stamp,), daemon=True).start()
        return self.data


_facts = _Facts()


def facts() -> dict:
    """{song_id: song_facts}, cached per catalog change. Tests replace this function."""
    return _facts.get()


def facts_version() -> int:
    return id(_facts.data)


# ── effective labels ─────────────────────────────────────────────────────────

_eff_lock = threading.Lock()
_eff = {"key": None, "labels": None}


def _mtime(p):
    try:
        st = os.stat(p)
        return st.st_mtime_ns, st.st_size, st.st_ino
    except OSError:
        return 0


def effective(raw: dict, path: str = None, fx: dict = None) -> dict:
    """{song_id: [moods]} as the server uses them: admin label, else the raw label minus what the
    evidence rules out."""
    fx = facts() if fx is None else fx
    admin, meta = load_admin(path), load_meta(path)
    out = {sid: sanity(tags or [], fx.get(sid), meta.get(sid)) for sid, tags in raw.items()}
    for sid, e in admin.items():
        out[sid] = list(e["moods"])
    return out


def load_effective(path: str = None) -> dict:
    """effective() of the labels file, cached until the file, the admin labels, the confidences or
    the catalog facts change (Flow asks for it on every request)."""
    from navivibe.catalog import mood_tags
    p = path or mood_tags.PATH
    fx = facts()
    key = (p, _mtime(p), _mtime(admin_path(p)), _mtime(meta_path(p)), id(fx))
    with _eff_lock:
        if _eff["key"] == key and _eff["labels"] is not None:
            return dict(_eff["labels"])
    out = effective(mood_tags.load_raw(p), p, fx)
    with _eff_lock:
        _eff.update(key=key, labels=out)
    return dict(out)


def admin_ids(path: str = None) -> set:
    return set(load_admin(path))
