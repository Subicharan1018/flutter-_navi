"""home-dc-download-v1: files stored on the account's own data center download in parallel, not one connection.

Telethon cannot export an authorization to the data center it is already connected to, so every download from the home
DC (DC5 for this account: 32 of 32 in an hour on 25 Nov 2026) logged "borrow failed" and fell back to one connection at
about 1 MB/s, where other data centers ran 4-5 MB/s. For the home DC the parallel requests now share the main
connection (Telethon pipelines requests on one sender); other DCs are unchanged.

Anchored patch to tgfetch/parallel_download.py; each anchor must be found exactly once, or nothing is written.
usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not the expected file.
"""
import sys
from pathlib import Path

PD = "tgfetch/parallel_download.py"

P = [
    (PD,
     "    senders = []\n    try:\n        for _ in range(connections):\n",
     "    senders = []\n    own_dc = False        # home-dc-download-v1: True when the senders are the main connection\n"
     "    try:\n        for _ in range(connections):\n"),
    (PD,
     "    except Exception as exc:\n"
     "        log.warning(\"fast_download: borrow failed (%s); falling back\", exc)\n"
     "        for s in senders:\n"
     "            try:\n"
     "                await client._return_exported_sender(s)\n"
     "            except Exception:\n"
     "                pass\n"
     "        return await _fallback(client, message, dest, progress_callback)\n",
     "    except Exception as exc:\n"
     "        for s in senders:\n"
     "            try:\n"
     "                await client._return_exported_sender(s)\n"
     "            except Exception:\n"
     "                pass\n"
     "        main_sender = getattr(client, \"_sender\", None)\n"
     "        if dc_id == getattr(getattr(client, \"session\", None), \"dc_id\", None) and main_sender is not None:\n"
     "            # home-dc-download-v1: no authorization can be exported to the DC we are on; share the main connection\n"
     "            log.info(\"fast_download: home DC%d: %d parallel requests on the main connection\", dc_id, connections)\n"
     "            senders, own_dc = [main_sender] * connections, True\n"
     "        else:\n"
     "            log.warning(\"fast_download: borrow failed (%s); falling back\", exc)\n"
     "            return await _fallback(client, message, dest, progress_callback)\n"),
    (PD,
     "    finally:\n        for s in senders:\n",
     "    finally:\n        for s in ([] if own_dc else senders):\n"),
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
    print("home-dc-download-v1: parallel_download.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
