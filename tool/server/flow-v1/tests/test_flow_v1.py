"""flow-v1: Flow remembers what it served a listener for several days, across sessions.

Before, a song was blocked only inside one Flow session, so every new session started
fresh and the same favourites came back (sandeep: 61 % of served songs came back in a
later session). Now a song served to a listener is off limits for COOLDOWN_S whatever
the session, a small pool relaxes the cooldown instead of returning nothing, and the
familiar ranking no longer leans on play count alone.
"""

import numpy as np

from navivibe import explore, flow
from navivibe.tests.test_discover import NOW
from navivibe.tests.test_flow import FAMILIAR, FRESH, batch, history, world  # noqa: F401  (world is autouse)


def familiar_ids(out):
    return {i["navidrome_id"] for i in out["items"] if i["kind"] == "familiar"}


def test_a_song_served_in_one_session_does_not_return_in_the_next(world, tmp_path):
    store = explore.Store(str(tmp_path / "state.db"))
    seen = []
    for n in range(3):
        out = batch(world, count=8, session=f"s{n}", store=store, rng=np.random.default_rng(n))
        fam = familiar_ids(out)
        assert fam, "each session still gets familiar songs"
        assert not (fam & set().union(*seen)) if seen else True
        seen.append(fam)


def test_a_small_pool_relaxes_the_cooldown_instead_of_returning_nothing(world, tmp_path):
    store = explore.Store(str(tmp_path / "state.db"))
    store.mark_seen("me", "earlier", FAMILIAR[:20] + FRESH, NOW - 3600)   # everything eligible was served an hour ago
    out = batch(world, count=8, session="now", store=store)
    assert out["count"] == 8
    assert familiar_ids(out), "the cooldown relaxes when the pool is small"


def test_the_cooldown_ends(world, tmp_path):
    store = explore.Store(str(tmp_path / "state.db"))
    old = NOW - flow.COOLDOWN_S - 3600
    store.mark_seen("me", "long-ago", FAMILIAR[:20], old)
    assert flow.cooled(store, "me", NOW) == set()
    store.mark_seen("me", "recent", ["f1"], NOW - 60)
    assert flow.cooled(store, "me", NOW) == {"f1"}


def test_the_recent_plays_window_grows_with_the_library_but_has_a_ceiling():
    assert flow.recent_n(type("T", (), {"play": {f"s{i}": 1 for i in range(70)}})()) == 50
    assert flow.recent_n(type("T", (), {"play": {f"s{i}": 1 for i in range(400)}})()) == 133
    assert flow.recent_n(type("T", (), {"play": {f"s{i}": 1 for i in range(5000)}})()) == 150
