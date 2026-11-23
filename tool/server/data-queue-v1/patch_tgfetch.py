"""data-queue-v1: one small anchored patch to tg-fetcher's db.py.

  db.py   update_job: when a job becomes `ready` (the song is in the library and has its Navidrome id) the song is
          handed to tgfetch/data_queue_hook.py, which puts it in the hidden weekly data queue unless real Spotify
          features exist. Every arrival path (requests, pasted links, YouTube lists, Exportify wishlist batches,
          import retries and the reconcile promotion) ends in this one call, so this is the only hook needed.
          The call is wrapped: nothing the queue does can fail an import.

usage: python patch_tgfetch.py <tg-fetcher root>
exit 0: patched or already patched; exit 2: a file is not the expected one (nothing is written).
"""
import sys
from pathlib import Path

P = [   # (relative file, old (exactly once), new)
    ("tgfetch/db.py",
     '    conn.execute(f"UPDATE jobs SET {cols} WHERE id=?", (*fields.values(), job_id))\n',
     '    conn.execute(f"UPDATE jobs SET {cols} WHERE id=?", (*fields.values(), job_id))\n'
     '    if fields.get("status") == "ready" and fields.get("nd_song_id"):      # data-queue-v1: a song arrived\n'
     '        try:\n'
     '            from tgfetch import data_queue_hook\n'
     '            data_queue_hook.on_ready(conn, job_id, fields["nd_song_id"])\n'
     '        except Exception:                                               # a queue problem never fails an import\n'
     '            pass\n'),
]


def main(root: str) -> int:
    base = Path(root)
    texts, todo = {}, []
    for rel, old, new in P:
        path = base / rel
        if rel not in texts:
            if not path.exists():
                print(f"!! {path} not found")
                return 2
            texts[rel] = path.read_text(encoding="utf-8")
        text = texts[rel]
        if new in text:
            continue                                   # already patched
        n = text.count(old)
        if n != 1:
            print(f"!! {rel}: expected text found {n} times (not the version this package was built on)")
            print("   first line: " + old.strip().splitlines()[0][:100])
            return 2
        texts[rel] = text.replace(old, new)
        todo.append(rel)
    for rel in dict.fromkeys(todo):
        (base / rel).write_text(texts[rel], encoding="utf-8")
    print(f"patched: {', '.join(dict.fromkeys(todo)) or 'nothing (already patched)'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
