"""
reshuffle-v1: a reshuffle spreads its picks over the pool; normal playback is unchanged.

  cd /opt/shuffle-server && venv/bin/python -m pytest navivibe/tests/test_reshuffle_v1.py -q

Pure numpy: no catalog, no model.
"""
from collections import Counter

import numpy as np

from navivibe.recsys import recommender as r

V3 = r.V3Engine


def _heavy_tailed(n=300, seed=1):
    # A few favourites far above the rest, like the live ranker's scores.
    rng = np.random.default_rng(seed)
    s = rng.normal(0, 1, n)
    s[:5] += 12
    return s


def _picks(temp, draws=2000, seed=7):
    scores = _heavy_tailed()
    mask = np.ones_like(scores, dtype=bool)
    rng = np.random.default_rng(seed)
    return Counter(V3._sample(scores, mask, temp, rng) for _ in range(draws))


FAVOURITES = range(5)   # the five songs _heavy_tailed puts far ahead


def _favourite_share(c):
    return sum(c[i] for i in FAVOURITES) / sum(c.values())


def test_reshuffle_spreads_over_the_pool():
    c = _picks(r.TEMPERATURE_RESHUFFLE)
    assert _favourite_share(c) < 0.5            # was ~1.0 with score sampling
    assert len(c) >= 30                         # most of the 40-song pool comes up


def test_reshuffle_stays_on_taste():
    scores = _heavy_tailed()
    pool = set(np.argsort(-scores)[: r.SAMPLE_POOL].tolist())
    assert set(_picks(r.TEMPERATURE_RESHUFFLE)) <= pool


def test_normal_playback_unchanged():
    # Below the reshuffle temperature the score-based sampler still favours the top.
    assert _favourite_share(_picks(r.TEMPERATURE)) > 0.9


def test_spread_zero_turns_it_off(monkeypatch):
    on = _favourite_share(_picks(r.TEMPERATURE_RESHUFFLE))
    monkeypatch.setattr(r, "RESHUFFLE_RANK_SPREAD", 0.0)
    off = _favourite_share(_picks(r.TEMPERATURE_RESHUFFLE))
    assert off > 0.7 and off > on + 0.3   # back to the old, favourite-heavy picks


def test_two_reshuffles_differ():
    scores = _heavy_tailed()
    mask = np.ones_like(scores, dtype=bool)
    rng = np.random.default_rng(3)

    def run():
        m, out = mask.copy(), []
        for _ in range(16):
            j = V3._sample(scores, m, r.TEMPERATURE_RESHUFFLE, rng)
            out.append(j)
            m[j] = False
        return out

    a, b = run(), run()
    assert a[:6] != b[:6]
    assert len(set(a) ^ set(b)) >= 6
