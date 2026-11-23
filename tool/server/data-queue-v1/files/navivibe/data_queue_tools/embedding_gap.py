"""Where in the audio-embedding space the labelled songs do NOT reach. numpy only, read-only."""
import sqlite3
import os

import numpy as np


def load_embeddings(catalog_path, model="effnet_discogs") -> dict:
    c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(catalog_path).replace("\\", "/"), uri=True, timeout=10)
    try:
        return {sid: np.frombuffer(b, dtype=np.float32) for sid, b in
                c.execute("SELECT song_id, vec FROM embeddings WHERE model=?", (model,))}
    except sqlite3.Error:
        return {}
    finally:
        c.close()


def reduce(X: np.ndarray, dims: int = 40) -> np.ndarray:
    """Standardise, then project on the top principal components (the first `dims`), unit scale per axis."""
    X = np.asarray(X, dtype=np.float64)
    mu, sd = X.mean(0), X.std(0)
    sd[sd < 1e-6] = 1.0
    Z = (X - mu) / sd
    U, S, _ = np.linalg.svd(Z, full_matrices=False)
    k = min(dims, len(S))
    return U[:, :k] * S[:k] / np.sqrt(max(1, len(Z) - 1))


def dist_to_set(P: np.ndarray, idx_set) -> np.ndarray:
    """Distance of every row of P to its nearest row among `idx_set` (0 for the members)."""
    idx_set = list(idx_set)
    if not idx_set:
        return np.full(len(P), np.inf)
    B = P[idx_set]
    best = np.full(len(P), np.inf)
    for i in range(0, len(P), 512):
        d = np.sqrt(((P[i:i + 512, None, :] - B[None, :, :]) ** 2).sum(-1))
        best[i:i + 512] = d.min(1)
    return best


def kcenter(P: np.ndarray, labelled, candidates, n: int, keys=None, penalty: float = 0.3, scale: float = None) -> list:
    """Greedy: repeatedly take the candidate farthest from the labelled + already chosen songs, with a penalty for a
    `keys[i]` (composer) already chosen. Returns candidate indices in pick order. Deterministic (ties: lowest index)."""
    cand = list(candidates)
    d = dist_to_set(P, labelled)[cand]
    if not np.isfinite(d).all():                       # nothing labelled yet: start from the farthest from the centre
        d = np.sqrt(((P[cand] - P.mean(0)) ** 2).sum(1))
    if not scale:
        scale = float(np.median(d[d > 0])) if (d > 0).any() else 1.0
    used, picked = {}, []
    alive = np.ones(len(cand), bool)
    for _ in range(min(n, len(cand))):
        score = d / scale
        if keys is not None:
            score = score - penalty * np.array([used.get(keys[c], 0) for c in cand])
        score = np.where(alive, score, -np.inf)
        j = int(np.argmax(score))
        if not np.isfinite(score[j]):
            break
        picked.append(cand[j])
        alive[j] = False
        if keys is not None:
            used[keys[cand[j]]] = used.get(keys[cand[j]], 0) + 1
        d = np.minimum(d, np.sqrt(((P[cand] - P[cand[j]]) ** 2).sum(1)))
    return picked
