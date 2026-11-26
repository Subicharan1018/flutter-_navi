"""playlist-cap-v1: a playlist is no longer cut at 300 songs (MAX_PLAYLIST_TRACKS, default 3000).

Anchored patches to links.py, sources/deezload.py and youtube_list.py; each anchor must be found exactly once, or
nothing is written. usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not expected.
NOTE: a Spotify playlist link is read from Spotify's public embed page, which lists only its first 100 songs; this patch
cannot lift that (use an Exportify CSV for a bigger Spotify playlist). Deezer and YouTube playlists now read in full.
"""
import sys
from pathlib import Path

NEW = ("import os as _os                      # playlist-cap-v1\n"
       "MAX_TRACKS = int(_os.getenv(\"MAX_PLAYLIST_TRACKS\", \"3000\"))")

P = [
    ("tgfetch/links.py", "MAX_TRACKS = 300\n", NEW + "\n"),
    ("tgfetch/youtube_list.py", "MAX_TRACKS = 300\n", NEW + "\n"),
    ("tgfetch/sources/deezload.py",
     "MAX_TRACKS = 300           # one batch; a 245-track playlist fits, a 2 000-track one is cut\n",
     NEW + "   # one batch; MAX_PLAYLIST_TRACKS to change\n"),
    # the old cap test: a list bigger than the cap is still cut (now at 3000, not 300)
    ("tests/test_sfv1_youtube.py", "for i in range(450)]}", "for i in range(3200)]}"),
    ("tests/test_sfv1_youtube.py", "        assert len(songs) == 300\n",
     "        assert len(songs) == youtube_list.MAX_TRACKS == 3000      # playlist-cap-v1\n"),
]


def main(root: str) -> int:
    base = Path(root)
    texts: dict[str, str] = {}
    for rel, old, new in P:
        text = texts.get(rel)
        if text is None:
            text = (base / rel).read_text(encoding="utf-8")
        if new in text:
            texts[rel] = text
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected anchor not found exactly once:\n{old[:140]!r}")
            return 2
        texts[rel] = text.replace(old, new)
    for rel, text in texts.items():
        (base / rel).write_text(text, encoding="utf-8")
    print("playlist-cap-v1: links.py, youtube_list.py, deezload.py and the old cap test patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
