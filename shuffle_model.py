"""
Personal Shuffle System — Smart Model
Blueprint v2 · Weighted Markov Chain + Acoustic Fallback + Session Momentum
290-song Tamil library · 2 playlists (Melody · Kuthu/Action)

USAGE:
  # Step 1: Build and save the model from Apple Music CSV + FLAC metadata
  python shuffle_model.py --build \
      --apple  "Apple Music Play Activity.csv" \
      --flac   "flac_metadata.csv" \
      --likes  "Apple Music Likes and Dislikes.csv"   # optional

  # Step 2: Get next songs at runtime
  python shuffle_model.py --next \
      --current "Loosu Pennae" \
      --playlist melody \
      --count 15

  # Step 3: Inspect a song's profile
  python shuffle_model.py --profile "Loosu Pennae"

INPUTS expected:
  apple CSV  — Apple Music Play Activity (144-column export)
  flac  CSV  — columns: song_name, artist, energy, danceability,
               valence, tempo, acousticness, loudness, playlist
  likes CSV  — Apple Music Likes & Dislikes export (optional)

OUTPUTS:
  shuffle_model.json  — transition matrices + behavioural store (human-readable)
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd

# ──────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ──────────────────────────────────────────────────────────────────────────────

MODEL_PATH = Path("shuffle_model.json")

# Context windows → active playlist (hour 0–23)
CONTEXT_WINDOWS = {
    "melody": list(range(21, 24)) + list(range(0, 12)),   # 21:00–11:59
    "kuthu":  list(range(12, 21)),                          # 12:00–20:59
}

# Scoring weights (must sum to 1.0)
W_TRANSITION  = 0.45
W_COMPLETION  = 0.25
W_RECENCY     = 0.20
W_LOVED       = 0.10

# Hard elimination thresholds
SKIP_RATE_BLOCK   = 0.75   # skip_rate > this → never queue
MIN_MATRIX_COUNT  = 3      # minimum raw transition count to use L1
RECENCY_HALF_LIFE = 14     # days — decay half-life for recency score

# Session / queue settings
SESSION_GAP_MINUTES  = 20  # gap that breaks a session
QUEUE_SIZE           = 15  # songs to return per call
TOP_N_SAMPLE         = 20  # weighted-sample pool size
SESSION_ENERGY_LOOKBACK = 3

# Cold-start
COLD_START_PLAYS     = 5       # plays needed to graduate
COLD_START_DISCOUNT  = 0.30    # score multiplied by (1 − discount)
COLD_START_NEIGHBOURS = 5      # audio-similar neighbours to inherit from

# Acoustic features used for cosine similarity
ACOUSTIC_FEATURES = ["energy", "danceability", "valence", "tempo", "acousticness"]


# ──────────────────────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────────────────────

def _recency_decay(days: float) -> float:
    """exp(−days / half_life) → 1.0 when just played, → 0 after ~6 weeks."""
    return math.exp(-max(days, 0) / RECENCY_HALF_LIFE)


def _cosine_sim(a: list[float], b: list[float]) -> float:
    """Cosine similarity between two feature vectors."""
    na = np.linalg.norm(a)
    nb = np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0
    return float(np.dot(a, b) / (na * nb))


def _playlist_from_hour(hour: int) -> str:
    """Deterministic context routing — returns 'melody' or 'kuthu'."""
    return "melody" if hour in CONTEXT_WINDOWS["melody"] else "kuthu"


def _normalise_song_name(name: str) -> str:
    """Lowercase + strip for fuzzy join."""
    return str(name).lower().strip()


# ──────────────────────────────────────────────────────────────────────────────
# PHASE 1 — PARSE APPLE MUSIC CSV
# ──────────────────────────────────────────────────────────────────────────────

def load_apple_csv(path: str) -> pd.DataFrame:
    """
    Load + filter Apple Music Play Activity CSV.
    Keeps only: PLAY_END · AUDIO · ORIGINATING_DEVICE
    Returns clean DataFrame sorted by Event Start Timestamp.
    """
    print(f"[load] Reading Apple Music CSV: {path}")
    df = pd.read_csv(path, low_memory=False)
    print(f"[load] Raw rows: {len(df):,}")

    # Core filters
    df = df[
        (df["Event Type"]  == "PLAY_END") &
        (df["Media Type"]  == "AUDIO") &
        (df["Source Type"] == "ORIGINATING_DEVICE")
    ].copy()
    print(f"[load] After PLAY_END + AUDIO + ORIGINATING_DEVICE: {len(df):,}")

    # Parse timestamps (UTC)
    df["Event Start Timestamp"] = pd.to_datetime(
        df["Event Start Timestamp"], format="mixed", utc=True, errors="coerce"
    )
    df["Event End Timestamp"] = pd.to_datetime(
        df["Event End Timestamp"], format="mixed", utc=True, errors="coerce"
    )
    df = df.dropna(subset=["Event Start Timestamp", "Song Name"])
    df = df.sort_values("Event Start Timestamp").reset_index(drop=True)
    print(f"[load] After timestamp parse + dropna: {len(df):,}")

    # Convert UTC → IST (UTC+5:30) for context-window hour
    df["ist_hour"] = (
        df["Event Start Timestamp"]
        .dt.tz_convert("Asia/Kolkata")
        .dt.hour
    )

    # Numeric columns
    df["Play Duration Milliseconds"]  = pd.to_numeric(df.get("Play Duration Milliseconds",  0), errors="coerce").fillna(0)
    df["Media Duration In Milliseconds"] = pd.to_numeric(df.get("Media Duration In Milliseconds", 0), errors="coerce").fillna(0)
    df["Start Position In Milliseconds"] = pd.to_numeric(df.get("Start Position In Milliseconds", 0), errors="coerce").fillna(0)

    # Completion ratio  (0–1)
    df["completion_ratio"] = np.where(
        df["Media Duration In Milliseconds"] > 0,
        (df["Play Duration Milliseconds"] / df["Media Duration In Milliseconds"]).clip(0, 1),
        0.0,
    )

    # Skip flag:  manual skip AND completed < 30% of track
    skip_reasons = {
        "MANUALLY_SELECTED_PLAYBACK_OF_DIFFERENT_ITEM",
        "TRACK_SKIPPED_FORWARDS",
    }
    df["is_skip"] = (
        df["End Reason Type"].isin(skip_reasons) &
        (df["completion_ratio"] < 0.30)
    )

    # Time gap between consecutive events → session ID
    df["time_gap_min"] = df["Event Start Timestamp"].diff().dt.total_seconds().div(60).fillna(0)
    df["session_id"]   = (df["time_gap_min"] > SESSION_GAP_MINUTES).cumsum()

    # Normalised song name for joins
    df["song_key"] = df["Song Name"].map(_normalise_song_name)

    # Active playlist from context window
    df["context_playlist"] = df["ist_hour"].map(_playlist_from_hour)

    return df


# ──────────────────────────────────────────────────────────────────────────────
# PHASE 2 — BUILD BEHAVIOURAL FEATURE STORE
# ──────────────────────────────────────────────────────────────────────────────

def build_behavioural_store(df: pd.DataFrame) -> dict:
    """
    Compute per-song behavioural features from filtered Apple Music data.
    Returns dict: song_key → feature dict.
    """
    print("[features] Building behavioural feature store …")
    now = df["Event Start Timestamp"].max()

    store = {}
    for song_key, grp in df.groupby("song_key"):
        total_plays   = len(grp)
        skip_count    = grp["is_skip"].sum()
        skip_rate     = skip_count / total_plays if total_plays > 0 else 0.0
        completion_mean = grp["completion_ratio"].mean()

        last_play_ts  = grp["Event Start Timestamp"].max()
        days_since    = (now - last_play_ts).total_seconds() / 86400
        recency       = _recency_decay(days_since)

        cutoff_30d    = now - pd.Timedelta(days=30)
        plays_30d     = int((grp["Event Start Timestamp"] >= cutoff_30d).sum())

        # Repeat count: played again within same session
        session_counts = grp.groupby("session_id").size()
        repeat_count  = int((session_counts > 1).sum())

        # Artist (take most common value)
        artist = ""
        if "Artist Name" in grp.columns:
            artist = grp["Artist Name"].mode().iloc[0] if not grp["Artist Name"].mode().empty else ""
        elif "Container Artist Name" in grp.columns:
            artist = grp["Container Artist Name"].mode().iloc[0] if not grp["Container Artist Name"].mode().empty else ""

        # Canonical display name
        display_name = grp["Song Name"].mode().iloc[0]

        store[song_key] = {
            "display_name":      display_name,
            "artist":            str(artist).strip(),
            "total_plays":       total_plays,
            "skip_rate":         round(skip_rate, 4),
            "completion_mean":   round(float(completion_mean), 4),
            "days_since_last":   round(float(days_since), 2),
            "recency_decay":     round(float(recency), 4),
            "plays_last_30d":    plays_30d,
            "repeat_count":      repeat_count,
            "loved":             0,   # filled later from Likes CSV
            "cold_start":        total_plays < COLD_START_PLAYS,
        }

    print(f"[features] {len(store):,} songs in behavioural store")
    return store


# ──────────────────────────────────────────────────────────────────────────────
# PHASE 3 — BUILD TRANSITION MATRICES (per playlist)
# ──────────────────────────────────────────────────────────────────────────────

def build_transition_matrices(df: pd.DataFrame) -> dict:
    """
    Build weighted transition matrices separately for 'melody' and 'kuthu'.
    Weight = completion_ratio of the song that JUST ENDED (A).
    Only transitions within the same session and same context_playlist count.
    Returns dict: playlist → {song_a → {song_b → probability}}
                  + playlist → {song_a → {song_b → raw_count}}
    """
    print("[matrix] Building transition matrices …")

    raw_counts = {"melody": defaultdict(lambda: defaultdict(float)),
                  "kuthu":  defaultdict(lambda: defaultdict(float))}
    raw_weight  = {"melody": defaultdict(lambda: defaultdict(float)),
                   "kuthu":  defaultdict(lambda: defaultdict(float))}

    for (session_id, playlist), session_df in df.groupby(["session_id", "context_playlist"]):
        songs  = session_df["song_key"].tolist()
        ratios = session_df["completion_ratio"].tolist()

        for i in range(len(songs) - 1):
            a = songs[i]
            b = songs[i + 1]
            w = ratios[i]  # completion of A weights the A→B transition

            if a == "nan" or b == "nan" or a == b:
                continue

            raw_counts[playlist][a][b] += 1
            raw_weight[playlist][a][b] += w

    # Normalise to probabilities
    matrices  = {}
    count_maps = {}
    for pl in ("melody", "kuthu"):
        matrices[pl]   = {}
        count_maps[pl] = {}
        for a, nexts in raw_weight[pl].items():
            total = sum(nexts.values())
            if total > 0:
                matrices[pl][a]   = {b: round(w / total, 4) for b, w in nexts.items()}
                count_maps[pl][a] = dict(raw_counts[pl][a])

    melody_songs = sum(len(v) for v in matrices["melody"].values())
    kuthu_songs  = sum(len(v) for v in matrices["kuthu"].values())
    print(f"[matrix] Melody: {len(matrices['melody'])} source songs, {melody_songs} transitions")
    print(f"[matrix] Kuthu:  {len(matrices['kuthu'])}  source songs, {kuthu_songs}  transitions")
    return matrices, count_maps


# ──────────────────────────────────────────────────────────────────────────────
# PHASE 4 — LOAD FLAC METADATA
# ──────────────────────────────────────────────────────────────────────────────

def load_flac_metadata(path: str) -> dict:
    """
    Load FLAC metadata CSV.
    Expected columns: song_name, artist, energy, danceability, valence,
                      tempo, acousticness, loudness, playlist
    Returns dict: song_key → acoustic feature dict
    """
    print(f"[flac] Reading FLAC metadata: {path}")
    df = pd.read_csv(path, low_memory=False)

    # Normalise column names (lowercase, strip)
    df.columns = [c.lower().strip().replace(" ", "_") for c in df.columns]

    # Detect song name column
    name_col = next((c for c in df.columns if "song" in c or "title" in c or "name" in c), None)
    if name_col is None:
        raise ValueError("[flac] Cannot find song name column in FLAC CSV")

    flac = {}
    for _, row in df.iterrows():
        key = _normalise_song_name(row[name_col])
        flac[key] = {
            "energy":       float(row.get("energy",       0.5)),
            "danceability": float(row.get("danceability", 0.5)),
            "valence":      float(row.get("valence",      0.5)),
            "tempo":        float(row.get("tempo",        120)),
            "acousticness": float(row.get("acousticness", 0.3)),
            "loudness":     float(row.get("loudness",     -10)),
            "playlist":     str(row.get("playlist", "melody")).lower().strip(),
            "artist":       str(row.get("artist", "")).strip(),
            "display_name": str(row[name_col]),
        }
    print(f"[flac] {len(flac):,} songs with acoustic features")
    return flac


# ──────────────────────────────────────────────────────────────────────────────
# PHASE 5 — LOAD LIKES / DISLIKES
# ──────────────────────────────────────────────────────────────────────────────

def _parse_favorites_description(desc: str) -> list[str]:
    """
    Apple Music Favorites CSV encodes 'Item Description' as:
        "Artist1, Artist2 & Artist3 - Song Title"
    or multi-dash cases:
        "A.R. Rahman - Hosanna (From "Movie")"

    Strategy: split on ALL ' - ' occurrences and try every suffix
    as the candidate song title (longest → shortest), so we don't
    accidentally truncate song names that contain ' - ' themselves.
    Returns a list of candidate song_keys to try against the store,
    most-specific first.
    """
    desc = str(desc).strip()
    # Remove surrounding quotes Apple sometimes wraps around the field
    if desc.startswith('"') and desc.endswith('"'):
        desc = desc[1:-1]

    parts = desc.split(" - ")
    # Try: everything after first dash, then after second dash, etc.
    candidates = []
    for i in range(1, len(parts)):
        candidate = " - ".join(parts[i:]).strip()
        # Strip trailing parenthetical e.g. "(Tamil)" or "(From "Movie")"
        # but keep it as a fallback too
        candidates.append(_normalise_song_name(candidate))
        # Also try stripping the last parenthetical
        paren_stripped = candidate.split(" (")[0].strip()
        if paren_stripped != candidate:
            candidates.append(_normalise_song_name(paren_stripped))

    # Also try the full description as a last resort (some entries have no dash)
    candidates.append(_normalise_song_name(desc))
    # Deduplicate while preserving order
    seen = set()
    unique = []
    for c in candidates:
        if c not in seen:
            seen.add(c)
            unique.append(c)
    return unique


def load_likes(path: str, behaviour_store: dict) -> dict:
    """
    Load Apple Music Favorites CSV (Apple_Music_-_Favorites.csv format).

    Expected columns:
        Favorite Type   — 'Song' or 'Playlist'  (filter to Song)
        Item Description — 'Artist - Song Title' format
        Preference       — 'LIKE' or 'DISLIKE'
        Last Modified    — ISO timestamp (ignored here)
        Item Reference   — Apple song ID (ignored here)

    Also handles generic Likes & Dislikes CSVs with title/rating columns.

    Marks loved=+1 (liked) or loved=-1 (disliked) in behavioural store.
    Returns updated store.
    """
    print(f"[likes] Reading Favorites CSV: {path}")
    df = pd.read_csv(path, low_memory=False)

    # Normalise column names
    df.columns = [c.strip() for c in df.columns]

    # ── Detect format ──────────────────────────────────────────────────────
    is_favorites_format = (
        "Favorite Type" in df.columns and
        "Item Description" in df.columns and
        "Preference" in df.columns
    )

    applied   = 0
    not_found = []

    if is_favorites_format:
        print("[likes] Detected Apple Music Favorites format")

        # Filter to songs only (ignore playlist favourites)
        songs_df = df[df["Favorite Type"].str.strip() == "Song"].copy()
        print(f"[likes] Song entries: {len(songs_df)} "
              f"(filtered from {len(df)} total rows)")

        for _, row in songs_df.iterrows():
            desc       = str(row["Item Description"])
            preference = str(row["Preference"]).strip().upper()

            val = 1 if preference == "LIKE" else (-1 if preference == "DISLIKE" else None)
            if val is None:
                continue

            # Try each candidate key against the behavioural store
            candidates = _parse_favorites_description(desc)
            matched = False
            for key in candidates:
                if key in behaviour_store:
                    behaviour_store[key]["loved"] = val
                    applied += 1
                    matched = True
                    break

            if not matched:
                not_found.append(desc)

    else:
        # ── Generic fallback format ────────────────────────────────────────
        print("[likes] Detected generic Likes/Dislikes format")
        df.columns = [c.lower().strip() for c in df.columns]

        title_col  = next((c for c in df.columns if "title" in c or "song" in c or "name" in c), None)
        rating_col = next((c for c in df.columns if "rating" in c or "love" in c
                           or "reaction" in c or "preference" in c), None)

        if title_col is None or rating_col is None:
            print("[likes] Warning: could not find title or rating column — skipping")
            return behaviour_store

        for _, row in df.iterrows():
            key    = _normalise_song_name(row[title_col])
            rating = str(row[rating_col]).lower()
            if "love" in rating or "like" in rating or rating in ("1", "true", "loved"):
                val = 1
            elif "dislike" in rating or rating in ("-1", "disliked"):
                val = -1
            else:
                continue
            if key in behaviour_store:
                behaviour_store[key]["loved"] = val
                applied += 1
            else:
                not_found.append(str(row[title_col]))

    # ── Report ─────────────────────────────────────────────────────────────
    print(f"[likes] Applied {applied} like/dislike labels")
    if not_found:
        print(f"[likes] {len(not_found)} entries had no match in behavioural store "
              f"(they may be songs not in your play history):")
        for desc in not_found[:10]:
            print(f"         · {desc}")
        if len(not_found) > 10:
            print(f"         … and {len(not_found) - 10} more")

    # ── Summary ────────────────────────────────────────────────────────────
    liked    = sum(1 for v in behaviour_store.values() if v.get("loved") ==  1)
    disliked = sum(1 for v in behaviour_store.values() if v.get("loved") == -1)
    print(f"[likes] Store totals — liked: {liked}  disliked: {disliked}")

    return behaviour_store


# ──────────────────────────────────────────────────────────────────────────────
# PHASE 6 — COLD-START SYNTHETIC PROFILES
# ──────────────────────────────────────────────────────────────────────────────

def apply_cold_start_profiles(
    behaviour_store: dict,
    flac_meta: dict,
    matrices: dict,
    count_maps: dict,
) -> tuple[dict, dict]:
    """
    For any song in FLAC metadata with < COLD_START_PLAYS plays (or missing
    from behavioural store), synthesise a behavioural profile by inheriting
    from the N audio-closest songs in the same playlist.
    Also injects synthetic rows into the transition matrix at discounted weight.
    Returns updated (behaviour_store, matrices).
    """
    print("[cold_start] Processing cold-start songs …")
    cold_count = 0

    for key, meta in flac_meta.items():
        plays = behaviour_store.get(key, {}).get("total_plays", 0)
        if plays >= COLD_START_PLAYS:
            continue  # graduated, nothing to do

        playlist = meta.get("playlist", "melody")

        # Find N nearest audio neighbours in same playlist
        vec_a = [meta[f] for f in ACOUSTIC_FEATURES]
        # Normalise tempo to [0,1] range (rough: 60–200 BPM)
        vec_a[3] = (vec_a[3] - 60) / 140

        neighbours = []
        for other_key, other_meta in flac_meta.items():
            if other_key == key:
                continue
            if other_meta.get("playlist", "melody") != playlist:
                continue
            other_plays = behaviour_store.get(other_key, {}).get("total_plays", 0)
            if other_plays < COLD_START_PLAYS:
                continue  # don't inherit from other cold-start songs
            vec_b = [other_meta[f] for f in ACOUSTIC_FEATURES]
            vec_b[3] = (vec_b[3] - 60) / 140
            sim = _cosine_sim(vec_a, vec_b)
            neighbours.append((sim, other_key))

        neighbours.sort(reverse=True)
        neighbours = neighbours[:COLD_START_NEIGHBOURS]

        if not neighbours:
            # No neighbours — create minimal profile
            synthetic = {
                "display_name":    meta.get("display_name", key),
                "artist":          meta.get("artist", ""),
                "total_plays":     plays,
                "skip_rate":       0.30,
                "completion_mean": 0.50,
                "days_since_last": 999,
                "recency_decay":   0.0,
                "plays_last_30d":  0,
                "repeat_count":    0,
                "loved":           0,
                "cold_start":      True,
            }
        else:
            total_sim = sum(s for s, _ in neighbours)
            weights   = [(s / total_sim, k) for s, k in neighbours]

            def _wavg(field):
                return sum(w * behaviour_store[k].get(field, 0) for w, k in weights)

            existing = behaviour_store.get(key, {})
            synthetic = {
                "display_name":    existing.get("display_name", meta.get("display_name", key)),
                "artist":          existing.get("artist", meta.get("artist", "")),
                "total_plays":     plays,
                "skip_rate":       round(_wavg("skip_rate"), 4),
                "completion_mean": round(_wavg("completion_mean"), 4),
                "days_since_last": round(_wavg("days_since_last"), 2),
                "recency_decay":   round(_wavg("recency_decay"), 4),
                "plays_last_30d":  0,
                "repeat_count":    0,
                "loved":           existing.get("loved", 0),
                "cold_start":      True,
            }

            # Inject synthetic transitions from each neighbour's outgoing matrix
            # at discounted weight (30% discount applied at scoring time)
            pl = playlist
            for sim, nbr_key in neighbours:
                if nbr_key in matrices[pl]:
                    for target, prob in matrices[pl][nbr_key].items():
                        matrices[pl].setdefault(key, {})[target] = round(
                            matrices[pl].get(key, {}).get(target, 0.0) + sim * prob * 0.5, 4
                        )
            # Renormalise synthetic transitions
            if key in matrices[pl]:
                total = sum(matrices[pl][key].values())
                if total > 0:
                    matrices[pl][key] = {t: round(p / total, 4) for t, p in matrices[pl][key].items()}

        behaviour_store[key] = synthetic
        cold_count += 1

    print(f"[cold_start] Synthesised profiles for {cold_count} cold-start songs")
    return behaviour_store, matrices


# ──────────────────────────────────────────────────────────────────────────────
# PHASE 7 — SAVE / LOAD MODEL
# ──────────────────────────────────────────────────────────────────────────────

def save_model(matrices: dict, count_maps: dict, behaviour_store: dict, flac_meta: dict):
    model = {
        "built_at":        datetime.now(timezone.utc).isoformat(),
        "matrices":        matrices,
        "count_maps":      count_maps,
        "behaviour_store": behaviour_store,
        "flac_meta":       flac_meta,
    }
    with open(MODEL_PATH, "w", encoding="utf-8") as f:
        json.dump(model, f, ensure_ascii=False, indent=2)
    size_mb = MODEL_PATH.stat().st_size / 1_048_576
    print(f"[save] Model written to {MODEL_PATH} ({size_mb:.1f} MB)")


def load_model() -> tuple[dict, dict, dict, dict]:
    if not MODEL_PATH.exists():
        sys.exit(f"[error] Model file not found: {MODEL_PATH}\nRun with --build first.")
    with open(MODEL_PATH, "r", encoding="utf-8") as f:
        m = json.load(f)
    return m["matrices"], m["count_maps"], m["behaviour_store"], m["flac_meta"]


# ──────────────────────────────────────────────────────────────────────────────
# INFERENCE ENGINE
# ──────────────────────────────────────────────────────────────────────────────

class ShuffleEngine:
    """
    Runtime inference engine.
    Call .next_songs() to get the next N song keys.
    """

    def __init__(self, matrices: dict, count_maps: dict, behaviour_store: dict, flac_meta: dict):
        self.matrices        = matrices
        self.count_maps      = count_maps
        self.behaviour       = behaviour_store
        self.flac            = flac_meta
        self._build_playlist_index()

    def _build_playlist_index(self):
        """Pre-build list of all songs per playlist from FLAC metadata."""
        self.playlist_songs = {"melody": [], "kuthu": []}
        for key, meta in self.flac.items():
            pl = meta.get("playlist", "melody")
            if pl in self.playlist_songs:
                self.playlist_songs[pl].append(key)
        # Also include any songs only in the behavioural store (no FLAC yet)
        for key, info in self.behaviour.items():
            for pl in ("melody", "kuthu"):
                if key in self.matrices.get(pl, {}) and key not in self.playlist_songs[pl]:
                    self.playlist_songs[pl].append(key)
        print(f"[engine] Playlist index: melody={len(self.playlist_songs['melody'])} "
              f"kuthu={len(self.playlist_songs['kuthu'])}")

    # ── Hard Elimination ─────────────────────────────────────────────────────

    def _hard_eliminate(
        self,
        candidates: list[str],
        last_artist: str,
        played_today: set[str],
        explicit_dislikes: set[str],
    ) -> list[str]:
        """Return candidates that pass all hard elimination rules."""
        surviving = []
        for key in candidates:
            b = self.behaviour.get(key, {})
            if b.get("loved", 0) == -1:
                continue                                        # explicit dislike
            if b.get("skip_rate", 0) > SKIP_RATE_BLOCK:
                continue                                        # skipped too often
            if key in played_today:
                continue                                        # already heard today
            artist = b.get("artist", "") or self.flac.get(key, {}).get("artist", "")
            if artist and artist.lower() == last_artist.lower() and last_artist:
                continue                                        # no back-to-back artist
            if key in explicit_dislikes:
                continue
            surviving.append(key)
        return surviving

    # ── Level 1: Markov Transition ───────────────────────────────────────────

    def _l1_transition_scores(self, current_key: str, playlist: str) -> dict[str, float]:
        """Direct Markov transition probabilities, filtered by min count."""
        probs    = self.matrices.get(playlist, {}).get(current_key, {})
        counts   = self.count_maps.get(playlist, {}).get(current_key, {})
        filtered = {
            song: prob
            for song, prob in probs.items()
            if counts.get(song, 0) >= MIN_MATRIX_COUNT
        }
        return filtered

    # ── Level 2: Audio Similarity ────────────────────────────────────────────

    def _l2_audio_similarity_scores(
        self, current_key: str, playlist: str, candidates: list[str]
    ) -> dict[str, float]:
        """Cosine similarity in acoustic feature space."""
        src = self.flac.get(current_key)
        if src is None:
            return {}

        vec_src = [src.get(f, 0.5) for f in ACOUSTIC_FEATURES]
        vec_src[3] = (vec_src[3] - 60) / 140  # normalise tempo

        scores = {}
        for key in candidates:
            tgt = self.flac.get(key)
            if tgt is None:
                continue
            vec_tgt = [tgt.get(f, 0.5) for f in ACOUSTIC_FEATURES]
            vec_tgt[3] = (vec_tgt[3] - 60) / 140
            scores[key] = _cosine_sim(vec_src, vec_tgt)
        return scores

    # ── Level 3: Pure Behavioural Rank ───────────────────────────────────────

    def _l3_behavioural_scores(self, candidates: list[str]) -> dict[str, float]:
        """Completion + recency + loved as a last resort."""
        scores = {}
        for key in candidates:
            b = self.behaviour.get(key, {})
            s = (
                0.50 * b.get("completion_mean", 0.5) +
                0.40 * b.get("recency_decay",   0.5) +
                0.10 * (1.0 if b.get("loved", 0) == 1 else 0.0)
            )
            scores[key] = s
        return scores

    # ── Main Scoring Formula ─────────────────────────────────────────────────

    def _score_candidates(
        self,
        current_key:  str,
        playlist:     str,
        candidates:   list[str],
        session_last3: list[str],
    ) -> dict[str, float]:
        """
        score = 0.45×transition + 0.25×completion + 0.20×recency + 0.10×loved
        + session momentum modifier
        + cold-start discount
        """
        # Determine which level to use for transition component
        l1_scores = self._l1_transition_scores(current_key, playlist)

        if not l1_scores:
            # Level 2 fallback
            l2_scores = self._l2_audio_similarity_scores(current_key, playlist, candidates)
            if l2_scores:
                max_sim = max(l2_scores.values()) or 1.0
                transition_scores = {k: v / max_sim for k, v in l2_scores.items()}
                level_used = 2
            else:
                # Level 3 — pure behavioural
                l3_scores = self._l3_behavioural_scores(candidates)
                max_beh = max(l3_scores.values()) or 1.0
                transition_scores = {k: v / max_beh for k, v in l3_scores.items()}
                level_used = 3
        else:
            transition_scores = l1_scores
            level_used = 1

        # Session energy momentum
        session_energy_mean = self._session_energy_mean(session_last3)

        final_scores = {}
        for key in candidates:
            b = self.behaviour.get(key, {})

            t_score   = transition_scores.get(key, 0.01)   # default 0.01 for unseen
            c_score   = b.get("completion_mean", 0.5)
            r_score   = b.get("recency_decay",   0.5)
            l_bonus   = 0.10 if b.get("loved", 0) == 1 else 0.0

            score = (
                W_TRANSITION * t_score +
                W_COMPLETION * c_score +
                W_RECENCY    * r_score +
                W_LOVED      * l_bonus
            )

            # Session momentum modifier (±0.05)
            if session_energy_mean is not None:
                cand_energy = self.flac.get(key, {}).get("energy", 0.5)
                energy_diff = abs(cand_energy - session_energy_mean)
                if session_energy_mean > 0.75:
                    score += 0.05 if energy_diff < 0.15 else -0.05
                elif session_energy_mean < 0.40:
                    score += 0.05 if energy_diff < 0.15 else -0.05

            # Cold-start discount
            if b.get("cold_start", False):
                score *= (1 - COLD_START_DISCOUNT)

            final_scores[key] = max(score, 0.001)

        return final_scores, level_used

    def _session_energy_mean(self, last3: list[str]) -> Optional[float]:
        """Mean energy of the last N played songs (from FLAC meta)."""
        energies = [
            self.flac[k]["energy"]
            for k in last3
            if k in self.flac
        ]
        return float(np.mean(energies)) if energies else None

    # ── Public API ────────────────────────────────────────────────────────────

    def next_songs(
        self,
        current_song: str,
        playlist:     Optional[str] = None,
        hour:         Optional[int] = None,
        count:        int = QUEUE_SIZE,
        last_artist:  str = "",
        played_today: Optional[set] = None,
        session_last3: Optional[list] = None,
        already_queued: Optional[set] = None,
        verbose: bool = False,
    ) -> list[dict]:
        """
        Core inference call.

        Args:
            current_song:   Display name or song_key of the song that just ended.
            playlist:       'melody' or 'kuthu'. Auto-detected from hour if None.
            hour:           IST hour (0–23). Uses system clock if None.
            count:          Number of songs to return (default 15).
            last_artist:    Artist of current_song (for no-back-to-back rule).
            played_today:   Set of song_keys played today (for recency rule).
            session_last3:  List of last 3 song_keys in this session.
            already_queued: Song_keys already in the queue (exclude from results).
            verbose:        Print scoring debug info.

        Returns:
            List of dicts: [{song_key, display_name, artist, score, level}]
        """
        if hour is None:
            hour = datetime.now(timezone.utc).astimezone().hour
        if playlist is None:
            playlist = _playlist_from_hour(hour)
        if played_today is None:
            played_today = set()
        if session_last3 is None:
            session_last3 = []
        if already_queued is None:
            already_queued = set()

        current_key = _normalise_song_name(current_song)

        # Pool = all songs in the target playlist except current
        pool = [
            k for k in self.playlist_songs.get(playlist, [])
            if k != current_key and k not in already_queued
        ]

        if not pool:
            print(f"[engine] Warning: playlist '{playlist}' has no candidates")
            return []

        # Hard elimination
        surviving = self._hard_eliminate(pool, last_artist, played_today, set())
        if not surviving:
            print("[engine] Warning: all candidates eliminated — relaxing rules")
            surviving = [k for k in pool if self.behaviour.get(k, {}).get("loved", 0) != -1]

        # Score all surviving candidates
        scores, level_used = self._score_candidates(
            current_key, playlist, surviving, session_last3
        )

        if verbose:
            print(f"\n[engine] Current: '{current_song}' | Playlist: {playlist} | Level: {level_used}")
            top10 = sorted(scores.items(), key=lambda x: -x[1])[:10]
            for i, (k, s) in enumerate(top10, 1):
                name = self.behaviour.get(k, {}).get("display_name", k)
                print(f"  {i:2}. {name:40} score={s:.4f}")

        # Weighted sample from top-N pool
        sorted_candidates = sorted(scores.items(), key=lambda x: -x[1])
        top_pool = sorted_candidates[:TOP_N_SAMPLE]

        if not top_pool:
            return []

        keys   = [k for k, _ in top_pool]
        wts    = np.array([s for _, s in top_pool], dtype=float)
        wts   /= wts.sum()

        chosen_indices = np.random.choice(
            len(keys),
            size=min(count, len(keys)),
            replace=False,
            p=wts,
        )
        chosen = [keys[i] for i in chosen_indices]

        results = []
        for key in chosen:
            b    = self.behaviour.get(key, {})
            name = b.get("display_name") or self.flac.get(key, {}).get("display_name", key)
            artist = b.get("artist") or self.flac.get(key, {}).get("artist", "")
            results.append({
                "song_key":     key,
                "display_name": name,
                "artist":       artist,
                "score":        round(scores[key], 4),
                "level":        level_used,
                "cold_start":   b.get("cold_start", False),
            })

        return results

    # ── Profile Inspection ────────────────────────────────────────────────────

    def song_profile(self, song: str) -> dict:
        """Return all features for a song (useful for debugging)."""
        key = _normalise_song_name(song)
        profile = {
            "song_key":       key,
            "behavioural":    self.behaviour.get(key, {}),
            "acoustic":       self.flac.get(key, {}),
            "melody_transitions": dict(
                sorted(self.matrices.get("melody", {}).get(key, {}).items(), key=lambda x: -x[1])[:10]
            ),
            "kuthu_transitions": dict(
                sorted(self.matrices.get("kuthu", {}).get(key, {}).get(key, {}).items() if False else
                       self.matrices.get("kuthu", {}).get(key, {}).items(), key=lambda x: -x[1])[:10]
            ),
        }
        return profile


# ──────────────────────────────────────────────────────────────────────────────
# BUILD PIPELINE (offline — run monthly)
# ──────────────────────────────────────────────────────────────────────────────

def build_pipeline(apple_path: str, flac_path: str, likes_path: Optional[str]):
    """
    Full offline build:
      1. Parse Apple Music CSV
      2. Build behavioural store
      3. Build transition matrices
      4. Load FLAC metadata
      5. Load likes/dislikes
      6. Apply cold-start profiles
      7. Save model to JSON
    """
    print("=" * 60)
    print("SHUFFLE MODEL BUILD PIPELINE")
    print("=" * 60)

    # 1. Apple Music
    df = load_apple_csv(apple_path)

    # 2. Behavioural store
    behaviour_store = build_behavioural_store(df)

    # 3. Transition matrices
    matrices, count_maps = build_transition_matrices(df)

    # 4. FLAC metadata (optional but strongly recommended)
    flac_meta = {}
    if flac_path:
        try:
            flac_meta = load_flac_metadata(flac_path)
        except Exception as e:
            print(f"[flac] Warning: could not load FLAC metadata: {e}")

    # 5. Likes / Dislikes
    if likes_path:
        try:
            behaviour_store = load_likes(likes_path, behaviour_store)
        except Exception as e:
            print(f"[likes] Warning: could not load likes: {e}")

    # 6. Cold-start
    if flac_meta:
        behaviour_store, matrices = apply_cold_start_profiles(
            behaviour_store, flac_meta, matrices, count_maps
        )

    # 7. Save
    save_model(matrices, count_maps, behaviour_store, flac_meta)

    print("\n" + "=" * 60)
    print("BUILD COMPLETE")
    print(f"  Behavioural profiles : {len(behaviour_store)}")
    print(f"  Melody transitions   : {len(matrices.get('melody', {}))}")
    print(f"  Kuthu  transitions   : {len(matrices.get('kuthu', {}))}")
    print(f"  FLAC songs           : {len(flac_meta)}")
    print("=" * 60)


# ──────────────────────────────────────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────────────────────────────────────

def cli():
    parser = argparse.ArgumentParser(
        description="Personal Shuffle Model — Blueprint v2",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--build",   action="store_true", help="Build model from CSVs")
    group.add_argument("--next",    action="store_true", help="Get next N songs")
    group.add_argument("--profile", metavar="SONG",      help="Inspect a song's profile")

    # Build args
    parser.add_argument("--apple",    metavar="PATH", help="Apple Music Play Activity CSV")
    parser.add_argument("--flac",     metavar="PATH", help="FLAC metadata CSV (optional)")
    parser.add_argument("--likes",    metavar="PATH", help="Apple Music Likes & Dislikes CSV (optional)")

    # Inference args
    parser.add_argument("--current",  metavar="SONG",     help="Song that just ended")
    parser.add_argument("--playlist", metavar="PLAYLIST", help="melody or kuthu (auto from hour if omitted)")
    parser.add_argument("--hour",     metavar="HOUR",     type=int, help="IST hour 0–23 (default: system clock)")
    parser.add_argument("--count",    metavar="N",        type=int, default=QUEUE_SIZE, help=f"Songs to return (default {QUEUE_SIZE})")
    parser.add_argument("--artist",   metavar="ARTIST",   default="", help="Artist of current song (no-back-to-back rule)")
    parser.add_argument("--verbose",  action="store_true", help="Print scoring debug output")

    args = parser.parse_args()

    if args.build:
        if not args.apple:
            parser.error("--build requires --apple PATH")
        build_pipeline(args.apple, args.flac, args.likes)

    elif args.next:
        if not args.current:
            parser.error("--next requires --current SONG")
        matrices, count_maps, behaviour_store, flac_meta = load_model()
        engine = ShuffleEngine(matrices, count_maps, behaviour_store, flac_meta)
        results = engine.next_songs(
            current_song=args.current,
            playlist=args.playlist,
            hour=args.hour,
            count=args.count,
            last_artist=args.artist,
            verbose=args.verbose,
        )
        print(f"\nNext {len(results)} songs after '{args.current}':")
        for i, r in enumerate(results, 1):
            cold = " [cold]" if r["cold_start"] else ""
            print(f"  {i:2}. {r['display_name']:<40} "
                  f"score={r['score']:.4f}  L{r['level']}{cold}")

    elif args.profile:
        matrices, count_maps, behaviour_store, flac_meta = load_model()
        engine = ShuffleEngine(matrices, count_maps, behaviour_store, flac_meta)
        profile = engine.song_profile(args.profile)
        print(json.dumps(profile, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    cli()