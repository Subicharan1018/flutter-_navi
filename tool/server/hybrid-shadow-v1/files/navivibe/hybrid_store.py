"""hybrid-shadow-v1: the model file.

One JSON file (model text + metadata), replaced in a single rename, so a reader sees the old
model or the new one, never half of either. The previous one stays beside it as `.prev`.

A model is only used when it is *compatible* with what the server runs now:
  * the re-ranker's column list equals the harness's `NO_AUDIO_MOOD_COLS`, and the full column
    list equals `ALL_COLS` (a change of v3's FEATURES makes the model unusable until the refit)
  * it was fitted against the same v3 artifacts (same `trained_at` in `models/v3/meta.json`):
    the co-listen and name vectors are the ones the training groups were built with
Otherwise shadow stays off and says why (spec: "if the model is missing or its feature list does
not match, shadow stays off").
"""
import hashlib
import json
import os
import time

import lightgbm as lgb

from navivibe import hybrid as H

FORMAT = 2


def v3_trained_at(v3_dir=None):
    """`trained_at` of the v3 artifacts now on disk, or None."""
    try:
        from navivibe.recsys.train import ARTIFACT_DIR
        with open(os.path.join(v3_dir or ARTIFACT_DIR, "meta.json"), encoding="utf-8") as f:
            return json.load(f).get("trained_at")
    except Exception:
        return None


def save(path, reranker, metrics, v3_version, extra=None):
    text = reranker.model.model_to_string()
    meta = {"format": FORMAT, "version": hashlib.sha1(text.encode("utf-8")).hexdigest()[:12],
            "cols": list(reranker.cols), "all_cols": list(H.ALL_COLS), "v3_trained_at": v3_version,
            "trained_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "metrics": metrics,
            "params": {k: v for k, v in H.LGB_PARAMS.items() if k != "num_threads"},
            "n_cand": H.N_CAND, "train_days": H.TRAIN_DAYS}
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


def load(path):
    """(Reranker, meta), or (None, reason). Never raises."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            blob = json.load(f)
        meta = blob["meta"]
        if meta.get("format") != FORMAT:
            return None, "format %s" % meta.get("format")
        model = lgb.Booster(model_str=blob["model"])
        return H.Reranker(model, meta["cols"]), meta
    except FileNotFoundError:
        return None, "no model file"
    except Exception as e:  # noqa: BLE001
        return None, "unreadable: %s" % type(e).__name__


_LOOK_UP = object()


def incompatible(meta, current_v3=_LOOK_UP):
    """None when the model may be used, else the reason it may not.

    `current_v3` is the v3 artifacts' `trained_at` now. Left out, it is read from disk. An
    explicit None means "unknown": the co-listen and name vectors cannot be proven to match
    the ones the groups were built with, so the model is NOT compatible (shadow stays off)."""
    if list(meta.get("cols") or []) != list(H.NO_AUDIO_MOOD_COLS):
        return "feature columns differ from the harness (refit needed)"
    if list(meta.get("all_cols") or []) != list(H.ALL_COLS):
        return "v3 FEATURES changed since the fit (refit needed)"
    now = v3_trained_at() if current_v3 is _LOOK_UP else current_v3
    if now is None:
        return "v3 artifact version unknown (embeddings cannot be proven to match; refit needed)"
    if meta.get("v3_trained_at") != now:
        return "fitted against v3 artifacts %s, now %s (embeddings differ; refit needed)" % (meta.get("v3_trained_at"), now)
    return None
