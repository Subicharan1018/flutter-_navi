"""Hybrid next-song ranker: blend picks 100 candidates, LightGBM re-ranks them.

Reusable part of the bake-off (docs/smart-shuffle-bakeoff.md). Needs only numpy,
lightgbm and the server's own navivibe.recsys feature code; does no I/O.
"""
import numpy as np
import lightgbm as lgb

from navivibe.recsys.features import F, FEATURES
from navivibe.recsys.state import circular_kernel

N_CAND = 100
TRAIN_DAYS = 60            # re-ranker training window before the cutoff
MIN_ROUNDS = 20
EARLY_STOP = 40
VAL_FRAC = 0.15            # newest groups, time-ordered

# Columns added to the server's FEATURES. See README for definitions.
EXTRA = ["hb", "is_cold", "same_artist_last", "same_mood_last", "mood_hour", "mood_session",
         "energy_hour_gap", "valence_hour_gap", "energy_session_gap", "valence_session_gap",
         "msin", "mcos"]
AUDIO_MOOD = ["energy", "valence", "d_energy_last", "d_bpm_last", "au_last", "au_session",
              "au_hour_taste", "au_last_skipped", "same_mood_last", "mood_hour", "mood_session",
              "energy_hour_gap", "valence_hour_gap", "energy_session_gap", "valence_session_gap"]
ALL_COLS = list(FEATURES) + EXTRA
NO_AUDIO_MOOD_COLS = [c for c in ALL_COLS if c not in AUDIO_MOOD]   # recommended live set

LGB_PARAMS = dict(
    objective="lambdarank", metric="ndcg", ndcg_eval_at=[10], learning_rate=0.05, num_leaves=15,
    min_data_in_leaf=40, feature_fraction=0.8, bagging_fraction=0.8, bagging_freq=1, lambda_l2=1.0,
    seed=7, num_threads=2, deterministic=True, force_row_wise=True, verbose=-1)


def zscore(v):
    v = np.nan_to_num(np.asarray(v, np.float64))
    return (v - v.mean()) / (v.std() + 1e-9)


def impute(v):
    """Mean-filled COPY. One NaN poisons every weighted mean over the catalog
    (0 * NaN = NaN), and a later nan_to_num turns that into a dead all-zero column."""
    v = np.array(v, np.float64)
    v[np.isnan(v)] = np.nanmean(v)
    return v


def blend(X, empty):
    """Stage 1 over the whole catalog. X is FeatureBuilder output (FEATURES columns)."""
    def g(f):
        return X[:, F[f]]
    s = zscore(g("cnt_7d")) + zscore(g("hour_affinity") * g("cnt_180d"))
    if empty:                              # openers: kept for training parity; v3 serves them
        return s + zscore(g("starter_share"))
    return s + 1.5 * zscore(g("p_next") + 0.4 * g("p_next2")) + 0.5 * zscore(g("p_from_session"))


def candidates(hb, allowed, n=N_CAND):
    """Indices of the top-n allowed songs. Stable sort: light users have hundreds of tied
    scores, where argpartition picks an arbitrary set."""
    s = np.where(allowed, hb, -np.inf)
    top = np.argsort(-s, kind="stable")[:n]
    return top[np.isfinite(s[top])]


class FeatureMatrix:
    """Full (N x len(ALL_COLS)) float32 matrix for one request."""

    def __init__(self, catalog, arrays, first_mood=None):
        """first_mood: song id -> mood name. None leaves the mood columns at 0
        (fine when only NO_AUDIO_MOOD_COLS are used)."""
        code = {}
        self.artist = np.array([code.setdefault(catalog.meta[s].get("artist") or "?", len(code))
                                for s in catalog.ids])
        self.energy, self.valence = impute(arrays.energy), impute(arrays.valence)
        self.mood = None
        self.n_mood = 0
        if first_mood:
            m = {}
            self.mood = np.array([m.setdefault(first_mood.get(s) or "?", len(m)) for s in catalog.ids])
            self.n_mood = len(m)

    def build(self, X, us, kept, ts, hour, month):
        """X: FeatureBuilder output; us: UserState; kept: session's non-skipped indices."""
        N = X.shape[0]
        hb = blend(X, not kept)
        col = {"hb": hb, "is_cold": us.raw == 0,
               "msin": np.full(N, np.sin(2 * np.pi * month / 12)),
               "mcos": np.full(N, np.cos(2 * np.pi * month / 12))}
        if kept:
            col["same_artist_last"] = self.artist == self.artist[kept[-1]]
        hk = us.hour.at(ts) @ circular_kernel(hour)          # plays near this hour, per song
        if hk.sum() > 0:
            w = hk / hk.sum()
            col["energy_hour_gap"] = np.abs(self.energy - w @ self.energy)
            col["valence_hour_gap"] = np.abs(self.valence - w @ self.valence)
            if self.mood is not None:
                col["mood_hour"] = np.bincount(self.mood, weights=w, minlength=self.n_mood)[self.mood]
        if kept:
            r = list(kept[-5:])
            col["energy_session_gap"] = np.abs(self.energy - self.energy[r].mean())
            col["valence_session_gap"] = np.abs(self.valence - self.valence[r].mean())
            if self.mood is not None:
                col["same_mood_last"] = self.mood == self.mood[kept[-1]]
                share = np.bincount(self.mood[r], minlength=self.n_mood) / len(r)
                col["mood_session"] = share[self.mood]
        zero = np.zeros(N)
        ex = np.column_stack([np.asarray(col.get(c, zero), np.float32) for c in EXTRA])
        M = np.hstack([np.nan_to_num(X, nan=-1.0), ex]).astype(np.float32)
        return hb, M


class Reranker:
    def __init__(self, model, cols):
        self.model, self.cols = model, list(cols)
        self._ix = [ALL_COLS.index(c) for c in self.cols]

    @classmethod
    def fit(cls, groups, cols=NO_AUDIO_MOOD_COLS):
        """groups: time-ordered list of (candidate rows over ALL_COLS, one-hot label)."""
        ix = [ALL_COLS.index(c) for c in cols]
        X = np.vstack([g[0][:, ix] for g in groups])
        y = np.concatenate([g[1] for g in groups])
        size = np.array([len(g[1]) for g in groups])
        nv = max(1, int(VAL_FRAC * len(size)))
        rc = int(size[:-nv].sum())
        dtr = lgb.Dataset(X[:rc], y[:rc], group=size[:-nv])
        dva = lgb.Dataset(X[rc:], y[rc:], group=size[-nv:], reference=dtr)
        b = lgb.train(LGB_PARAMS, dtr, 400, valid_sets=[dva],
                      callbacks=[lgb.early_stopping(EARLY_STOP, verbose=False)])
        model = lgb.train(LGB_PARAMS, lgb.Dataset(X, y, group=size, feature_name=list(cols)),
                          max(b.best_iteration, MIN_ROUNDS))
        return cls(model, cols)

    def scores(self, M, hb, allowed):
        """Whole-catalog score: re-ranked candidates first, then blend order."""
        cand = candidates(hb, allowed)
        out = np.array(hb, np.float64)
        if len(cand):
            out[cand] = 1000.0 + zscore(self.model.predict(M[cand][:, self._ix], num_threads=1))
        return out


def training_group(M, hb, pos, allowed):
    """(rows, labels) when the played song is among the candidates, else None.
    Never force the positive in: the model then learns 'low stage-1 rank = positive'."""
    cand = candidates(hb, allowed)
    if pos not in cand:
        return None
    return M[cand], (cand == pos).astype(np.float32)
