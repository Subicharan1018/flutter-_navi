"""not-found-honest-v1: a song is "not found on the music bot" only when EVERY question the bot was asked got an answer.

youtube_batch.fetch_one asks the bot two ways (inline queries, which leave nothing in the bot chat). It failed the song as
"not found" whenever the queries did not ALL time out: one question unanswered plus one empty answer was enough, so a
flaky bot turned popular songs ("Param Sundari", "Tere Bina") into failures (54 of the 5,657-song Tamil import on 25 Nov).
Now any unanswered question means "we do not know": the song waits and is asked again (the batch's normal 30-minute retry).
The not-found line also records how many queries were asked, how many failed and how many results each gave, so the next
failure can be read from the journal.

Anchored patch to tgfetch/youtube_batch.py; each anchor must be found exactly once, or nothing is written.
usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not the expected file.
"""
import sys
from pathlib import Path

YB = "tgfetch/youtube_batch.py"

P = [
    (YB,
     "    found, used, errors, asked = None, \"\", 0, 0\n",
     "    found, used, errors, asked = None, \"\", 0, 0\n    got = []                 # not-found-honest-v1: results per answered query\n"),
    (YB,
     "            results = await worker.source.search(q)\n",
     "            results = await worker.source.search(q)\n            got.append(len(results))\n"),
    (YB,
     "        if errors and errors == asked:\n",
     "        if errors:               # not-found-honest-v1: any unanswered query means we do not know\n"),
    (YB,
     "        db.update_job(worker.conn, jid, status=\"failed\", error=f'{NOT_FOUND} (YouTube: “{song[\"raw\"][:100]}”)')\n"
     "        return \"done\"\n    log.info(\"youtube: job",
     "        log.info(\"youtube: job %s %r not found: %d queries asked, results per query %s\", jid, song[\"raw\"], asked, got)\n"
     "        db.update_job(worker.conn, jid, status=\"failed\", error=f'{NOT_FOUND} (YouTube: “{song[\"raw\"][:100]}”)')\n"
     "        return \"done\"\n    log.info(\"youtube: job"),
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
    print("not-found-honest-v1: youtube_batch.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
