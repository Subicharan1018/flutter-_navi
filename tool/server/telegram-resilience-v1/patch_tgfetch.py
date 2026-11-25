"""telegram-resilience-v1: anchored patches to tg-fetcher (main.py, channel_fallback.py, channels_first.py).

The watchdog is the new file tgfetch/watchdog.py; these patches start it and make channel lookups survive a fresh
login. Every anchor must be found exactly once, or nothing is written. Needs channel-ids-v1.
usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not the expected file.
"""
import sys
from pathlib import Path

MN = "tgfetch/main.py"
CF = "tgfetch/channel_fallback.py"
CH = "tgfetch/channels_first.py"

P = [
    (MN,
     "    status = {\"telegram\": client.is_connected, \"worker\": lambda: not worker_task.done()}\n",
     "    from tgfetch import watchdog          # telegram-resilience-v1: stop (and be restarted) when Telegram is gone\n"
     "    watchdog_task = asyncio.create_task(watchdog.watch(client, worker), name=\"watchdog\")\n"
     "    status = {\"telegram\": client.is_connected, \"worker\": lambda: not worker_task.done()}\n"),
    (MN,
     "asyncio.wait({worker_task, api_task}, return_when",
     "asyncio.wait({worker_task, api_task, watchdog_task}, return_when"),
    (MN,
     "        doctor_task.cancel()\n        await client.disconnect()\n",
     "        doctor_task.cancel()\n        watchdog_task.cancel()\n        await client.disconnect()\n"),
    (CF,
     "def enabled() -> bool:\n",
     "async def resolve(client, name):\n"
     "    \"\"\"get_entity for a channel setting. A numeric id of a private channel is unknown to a session that has just\n"
     "    logged in, so load the dialogs once and ask again.   telegram-resilience-v1\"\"\"\n"
     "    from tgfetch.sources.base import SourceError\n"
     "    key = ref(name)\n"
     "    try:\n"
     "        try:\n"
     "            return await client.get_entity(key)\n"
     "        except ValueError:\n"
     "            if not isinstance(key, int):\n"
     "                raise\n"
     "            await client.get_dialogs()\n"
     "            return await client.get_entity(key)\n"
     "    except ValueError as e:      # a name or id that does not exist: skip this channel, not the whole song\n"
     "        raise SourceError(f\"channel {name} cannot be opened ({e})\"[:200], retryable=False) from e\n\n\n"
     "def enabled() -> bool:\n"),
    (CF,
     "            self._ents[name] = await self.client.get_entity(ref(name))\n",
     "            self._ents[name] = await resolve(self.client, name)\n"),
    (CH,
     "                _ents[channel] = await client.get_entity(cf.ref(channel))\n",
     "                _ents[channel] = await cf.resolve(client, channel)\n"),
    (CH,
     "    ent = _ents.get(channel) or await worker.source.client.get_entity(cf.ref(channel))\n",
     "    ent = _ents.get(channel) or await cf.resolve(worker.source.client, channel)\n"),
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
            print(f"!! {rel}: expected anchor not found exactly once:\n{old[:120]!r}")
            return 2
        texts[rel] = text.replace(old, new)
    for rel, text in texts.items():
        (base / rel).write_text(text, encoding="utf-8")
    print("telegram-resilience-v1: main.py, channel_fallback.py, channels_first.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
