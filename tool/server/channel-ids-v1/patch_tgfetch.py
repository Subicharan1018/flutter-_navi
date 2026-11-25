"""channel-ids-v1: a channel in CHANNEL_FALLBACK_CHANNELS may be a numeric id (private channels have no @name).

Anchored patches to channel_fallback.py and channels_first.py; each anchor must be found exactly once, or nothing is
written. usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not the expected file.
"""
import sys
from pathlib import Path

CF = "tgfetch/channel_fallback.py"
CH = "tgfetch/channels_first.py"

P = [
    (CF,
     "def enabled() -> bool:\n",
     "def ref(name):\n"
     "    \"\"\"What Telethon's get_entity wants for a channel setting: an int for a numeric id (private channels\n"
     "    have no @name, e.g. -1001197115414), the name otherwise.   channel-ids-v1\"\"\"\n"
     "    s = str(name).strip()\n"
     "    return int(s) if re.fullmatch(r\"-?\\d+\", s) else s\n\n\n"
     "def enabled() -> bool:\n"),
    (CF,
     "            self._ents[name] = await self.client.get_entity(name)\n",
     "            self._ents[name] = await self.client.get_entity(ref(name))\n"),
    (CH,
     "                _ents[channel] = await client.get_entity(channel)\n",
     "                _ents[channel] = await client.get_entity(cf.ref(channel))\n"),
    (CH,
     "    ent = _ents.get(channel) or await worker.source.client.get_entity(channel)\n",
     "    ent = _ents.get(channel) or await worker.source.client.get_entity(cf.ref(channel))\n"),
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
    print("channel-ids-v1: channel_fallback.py, channels_first.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
