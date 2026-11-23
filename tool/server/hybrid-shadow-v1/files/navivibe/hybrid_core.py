"""hybrid-shadow-v1, the maths: blend -> top-100 candidates -> LightGBM re-ranker.

Pure numpy + lightgbm. No server imports, so it is unit-tested on its own.

    stage 1  blend      recency + hour habit + usual-next-song  -> top K candidates
    stage 2  re-ranker  LightGBM LambdaRank over the v3 feature columns + the blend score

The exact blend weights belong to the research harness (`tool/shuffle_eval/bakeoff/`,
`docs/hybrid-shadow-spec.md`). They live in `DEFAULT_BLEND` as PLACEHOLDERS and are saved
inside every model file, so training and serving can never disagree about them; changing
them is one dict plus a refit, no code path changes.

Everything here is deterministic: fixed seeds, `deterministic=True`, fixed thread count,
stable tie-breaks (lowest song index wins).
"""
import hashlib
import json
import os
import threading
import time

import numpy as np

K_CANDIDATES = 100
MIN_GROUPS = 200            # below this a model is not fitted (the blend alone is recorded)
MIN_ROUNDS = 20
MAX_ROUNDS = 300
EARLY_STOP = 30
VAL_FRACTION = 0.15
FORMAT = 1

# PLACEHOLDER weights (see module doc). `blend_version` is stored in each model and in
# every shadow row, so rows made with different weights are never pooled by mistake.
BLEND_VERSION = "placeholder-1"
DEFAULT_BLEND = {"recency": 1.0, "hour": 1.0, "next": 1.0, "rot2d_opener": 1.0}

LGB_PARAMS = dict(
    objective="lambdarank", metric="ndcg", ndcg_eval_at=[10],
    lambdarank_truncation_level=20, learning_rate=0.05, num_leaves=15,
    min_data_in_leaf=40, feature_fraction=0.8, bagging_fraction=0.8, bagging_freq=1,
    lambda_l2=1.0, verbose=-1, seed=7, deterministic=True, force_row_wise=True,
    num_threads=2,
)


def zscore(v, mask=None):
    """z-score over the allowed songs only; rows outside `mask` get -inf-safe 0."""
    v = np.asarray(v, dtype=np.float64)
    ref = v if mask is None else v[mask]
    if ref.size == 0:
        return np.zeros_like(v)
    return (v - ref.mean()) / (ref.std() + 1e-9)


def blend_score(X, F, weights=None, mask=None, opener=False):
    """Stage-1 score for every song. `F` maps feature name -> column."""
    w = {**DEFAULT_BLEND, **(weights or {})}
    recency = X[:, F["cnt_7d"]] + 0.25 * X[:, F["cnt_2d"]] + 0.05 * X[:, F["cnt_180d"]]
    hour = X[:, F["hour_affinity"]]
    usual_next = X[:, F["p_next"]] + 0.5 * X[:, F["p_next2"]]
    s = w["recency"] * zscore(recency, mask) + w["hour"] * zscore(hour, mask)
    if opener:
        # an opener has no "song before it"; what was played the last two days stands in
        s = s + w["rot2d_opener"] * zscore(X[:, F["rot_share_2d"]], mask)
    else:
        s = s + w["next"] * zscore(usual_next, mask)
    return s


def top_k(scores, mask, k=K_CANDIDATES):
    """Indices of the k best allowed songs, best first; ties go to the lower index."""
    idx = np.flatnonzero(mask)
    if idx.size == 0:
        return idx
    order = np.lexsort((idx, -scores[idx]))
    return idx[order[:k]]


def rerank_matrix(X, cand, blend):
    """Rows for the re-ranker: the v3 feature columns, the blend score and its rank."""
    b = blend[cand]
    rank = np.log1p(np.arange(len(cand), dtype=np.float32))
    return np.column_stack([X[cand], b.astype(np.float32), rank]).astype(np.float32)


def feature_names(names):
    return list(names) + ["blend", "blend_rank"]


def make_group(X, F, pos, allowed, weights, opener, k=K_CANDIDATES):
    """One training group, or None when the song that was really played is not among the
    stage-1 candidates (adding it anyway taught a ranker that "low rank = positive")."""
    blend = blend_score(X, F, weights, allowed, opener)
    cand = top_k(blend, allowed, k)
    hit = np.flatnonzero(cand == pos)
    if hit.size == 0:
        return None
    y = np.zeros(len(cand), np.float32)
    y[hit[0]] = 1.0
    return rerank_matrix(X, cand, blend), y


def fit(groups, names, max_groups=None):
    """Train on a list of (Xg, yg). The newest 15 % of groups validate and set the round
    count; the model is then refitted on everything. Returns (booster, metrics) or None."""
    import lightgbm as lgb

    if max_groups and len(groups) > max_groups:
        groups = groups[-max_groups:]
    if len(groups) < MIN_GROUPS:
        return None
    t0 = time.time()
    fnames = feature_names(names)
    sizes = np.array([len(y) for _, y in groups])
    X = np.vstack([g[0] for g in groups])
    y = np.concatenate([g[1] for g in groups])
    n_val = max(1, int(len(groups) * VAL_FRACTION))
    cut = len(groups) - n_val
    rows_cut = int(sizes[:cut].sum())
    dtr = lgb.Dataset(X[:rows_cut], y[:rows_cut], group=sizes[:cut], feature_name=fnames, free_raw_data=False)
    dva = lgb.Dataset(X[rows_cut:], y[rows_cut:], group=sizes[cut:], feature_name=fnames,
                      reference=dtr, free_raw_data=False)
    probe = lgb.train(LGB_PARAMS, dtr, num_boost_round=MAX_ROUNDS, valid_sets=[dva],
                      callbacks=[lgb.early_stopping(EARLY_STOP, first_metric_only=True, verbose=False)])
    rounds = max(probe.best_iteration or MAX_ROUNDS, MIN_ROUNDS)
    val_scores = probe.predict(X[rows_cut:], num_iteration=probe.best_iteration or None)
    hit10, off = 0, 0
    for s in sizes[cut:]:
        seg = val_scores[off:off + s]
        lab = y[rows_cut + off:rows_cut + off + s]
        hit10 += int(lab[np.argsort(-seg, kind="stable")[:10]].sum() > 0)
        off += s
    blend_hit10 = sum(int(g[1][:10].sum() > 0) for g in groups[cut:])   # candidates are in blend order
    dall = lgb.Dataset(X, y, group=sizes, feature_name=fnames)
    booster = lgb.train(LGB_PARAMS, dall, num_boost_round=rounds)
    metrics = {
        "groups": len(groups), "rows": int(len(y)), "rounds": rounds,
        "val_groups": n_val, "val_hr10_hybrid": round(hit10 / n_val, 4),
        "val_hr10_blend": round(blend_hit10 / n_val, 4),
        "fit_seconds": round(time.time() - t0, 2),
    }
    return booster, metrics


class HybridModel:
    """A fitted re-ranker plus the blend weights it was trained with."""

    def __init__(self, booster, meta):
        self.booster = booster
        self.meta = meta
        self.version = meta["version"]
        self.blend = meta.get("blend", DEFAULT_BLEND)
        self.blend_version = meta.get("blend_version", BLEND_VERSION)
        self._lock = threading.Lock()   # LightGBM does not promise thread-safe predict

    def rank(self, X, F, allowed, opener, n=20, k=K_CANDIDATES):
        """(song indices, scores) best first, for the songs in `allowed`."""
        blend = blend_score(X, F, self.blend, allowed, opener)
        cand = top_k(blend, allowed, k)
        if cand.size == 0:
            return cand, np.zeros(0)
        with self._lock:
            s = self.booster.predict(rerank_matrix(X, cand, blend))
        order = np.lexsort((cand, -s))[:n]
        return cand[order], s[order]


def blend_only_rank(X, F, allowed, opener, n=20, weights=None):
    """What is recorded before the first model exists: the stage-1 order itself."""
    blend = blend_score(X, F, weights, allowed, opener)
    cand = top_k(blend, allowed, n)
    return cand, blend[cand]


def save_model(path, booster, metrics, names, extra=None):
    """One JSON file, replaced atomically: a reader sees the old model or the new one."""
    text = booster.model_to_string()
    version = hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]
    meta = {"format": FORMAT, "version": version, "blend": DEFAULT_BLEND,
            "blend_version": BLEND_VERSION, "features": feature_names(names),
            "trained_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "metrics": metrics,
            "params": {k: v for k, v in LGB_PARAMS.items() if k != "num_threads"}}
    meta.update(extra or {})
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"meta": meta, "model": text}, f)
        f.flush()
        os.fsync(f.fileno())
    if os.path.exists(path):
        try:
            os.replace(path, path + ".prev")
        except OSError:
            pass
    os.replace(tmp, path)
    return meta


def load_model(path):
    """HybridModel, or None when the file is missing or unreadable (never raises)."""
    try:
        import lightgbm as lgb
        with open(path, "r", encoding="utf-8") as f:
            blob = json.load(f)
        meta = blob["meta"]
        if meta.get("format") != FORMAT:
            return None
        return HybridModel(lgb.Booster(model_str=blob["model"]), meta)
    except Exception:
        return None
