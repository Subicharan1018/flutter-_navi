"""playlist-cap-v1: the 300-song cut is gone."""
from tgfetch import links, youtube_list
from tgfetch.sources import deezload


def test_a_350_song_playlist_fits_everywhere():
    for mod in (links, youtube_list, deezload):
        assert mod.MAX_TRACKS >= 1000, mod.__name__


def test_the_cap_is_still_finite():
    for mod in (links, youtube_list, deezload):
        assert mod.MAX_TRACKS <= 100_000
