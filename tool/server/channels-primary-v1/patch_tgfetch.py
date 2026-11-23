"""channels-primary-v1: anchored patches to tg-fetcher (youtube_batch.py, exportify.py).

The feature is the new file tgfetch/channels_first.py; these patches only hook it in. Every anchor must
be found exactly once, or nothing is written.

usage: python patch_tgfetch.py <tg-fetcher root>
exit 0: patched or already patched; exit 2: a file is not the expected one (nothing is written).
"""
import sys
from pathlib import Path

YB = "tgfetch/youtube_batch.py"
EX = "tgfetch/exportify.py"

P = [   # (relative file, old (exactly once), new)
    (YB,
     "    from tgfetch.worker import MAINT_GIVE_UP_S, MAINT_RETRY_S, MAINT_TEXT\n    bid = b[\"id\"]\n",
     "    from tgfetch.worker import MAINT_GIVE_UP_S, MAINT_RETRY_S, MAINT_TEXT\n"
     "    from tgfetch import channels_first        # channels-primary-v1\n"
     "    bid = b[\"id\"]\n"),
    (YB,
     "        if await fetch_one(worker, jid, cand) == \"later\":\n",
     "        # channels-primary-v1: an Exportify song asks the channels first (FETCH_PRIMARY); other lists as before\n"
     "        if await channels_first.fetch_one(worker, b, jid, cand, fetch_one) == \"later\":\n"),
    (EX,
     "import logging\nimport re\nimport shutil\n",
     "import logging\nimport os\nimport re\nimport shutil\n"),
    (EX,
     "GB_PER_HOUR = 0.51               # measured on the library: FLAC, about 0.51 GB per hour of music\n",
     "GB_PER_HOUR = float(os.getenv(\"EXPORTIFY_GB_PER_HOUR\", \"0.51\"))   # measured on the library: FLAC, about 0.51 GB per hour\n"
     "                                 # (channel files run bigger: about 0.77; channels-primary-v1)\n"),
    (EX,
     "BATCH_SIZE = 25                  # songs per batch: about 8 minutes of bot time\n",
     "BATCH_SIZE = int(os.getenv(\"EXPORTIFY_BATCH_SIZE\", \"25\"))   # songs per batch: about 8 minutes of bot time\n"),
]


def main(root: str) -> int:
    base = Path(root)
    texts: dict[str, str] = {}
    for rel, old, new in P:
        text = texts.get(rel)
        if text is None:
            text = (base / rel).read_text(encoding="utf-8")
        if new in text and old not in text.replace(new, ""):
            texts[rel] = text            # already patched
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected anchor not found exactly once:\n{old[:120]!r}")
            return 2
        texts[rel] = text.replace(old, new)
    for rel, text in texts.items():
        (base / rel).write_text(text, encoding="utf-8")
    print("channels-primary-v1: youtube_batch.py, exportify.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
