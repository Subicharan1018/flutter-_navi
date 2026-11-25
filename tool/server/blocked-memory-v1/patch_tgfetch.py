"""blocked-memory-v1: anchored patches to tg-fetcher (worker.py, youtube_batch.py).

The feature is the new file tgfetch/blocked_memory.py; these patches only hook it in. Every anchor must be found
exactly once, or nothing is written.

usage: python patch_tgfetch.py <tg-fetcher root>
exit 0: patched or already patched; exit 2: a file is not the expected one (nothing is written).
"""
import sys
from pathlib import Path

WK = "tgfetch/worker.py"
YB = "tgfetch/youtube_batch.py"

P = [   # (relative file, old (exactly once), new)
    (WK,
     "from tgfetch.blocked import BLOCKED_TEXT\n",
     "from tgfetch.blocked import BLOCKED_TEXT\nfrom tgfetch import blocked_memory      # blocked-memory-v1\n"),
    # a song withdrawn before is blocked at once, whatever its candidate id
    (WK,
     "            db.update_job(self.conn, jid, status=\"failed\", error=\"unknown candidate\")\n            return\n        try:\n",
     "            db.update_job(self.conn, jid, status=\"failed\", error=\"unknown candidate\")\n            return\n"
     "        known = blocked_memory.lookup(self.conn, cand[\"title\"], cand[\"artist\"])      # blocked-memory-v1\n"
     "        if known:\n"
     "            self._block_job(jid, known)\n"
     "            return\n"
     "        try:\n"),
    # a refusal is remembered by song, not only by job
    (WK,
     "        db.update_job(self.conn, jid, status=\"blocked\", error=reason, progress=0.0)\n",
     "        db.update_job(self.conn, jid, status=\"blocked\", error=reason, progress=0.0)\n"
     "        blocked_memory.remember_job(self.conn, jid, reason)                             # blocked-memory-v1\n"),
    # the playlist / wishlist path asks the same question before searching
    (YB,
     "    found, used, errors, asked = None, \"\", 0, 0\n",
     "    from tgfetch import blocked_memory      # blocked-memory-v1\n"
     "    known = blocked_memory.lookup(worker.conn, cand[\"title\"], cand[\"artist\"])\n"
     "    if known:\n"
     "        worker._block_job(jid, known)\n"
     "        return \"done\"\n"
     "    found, used, errors, asked = None, \"\", 0, 0\n"),
]


def main(root: str) -> int:
    base = Path(root)
    texts: dict[str, str] = {}
    for rel, old, new in P:
        text = texts.get(rel)
        if text is None:
            text = (base / rel).read_text(encoding="utf-8")
        if new in text:
            texts[rel] = text            # already patched
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected anchor not found exactly once:\n{old[:120]!r}")
            return 2
        texts[rel] = text.replace(old, new)
    for rel, text in texts.items():
        (base / rel).write_text(text, encoding="utf-8")
    print("blocked-memory-v1: worker.py, youtube_batch.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
