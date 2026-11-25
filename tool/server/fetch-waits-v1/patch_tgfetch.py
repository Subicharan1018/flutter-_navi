"""fetch-waits-v1: anchored patches to tg-fetcher.

1. channels_first.py: a song the channels lack waits for the owner's verify (status waiting, "later") instead of
   ending `failed`; its title is searched without a version suffix ("Laali Laali - Tamil" -> "Laali Laali").
2. youtube_batch.py: a batch waiting for the verify does not give up after a day (a week, HUMAN_CHECK_GIVE_UP_S).
3. human_check.py: a flag that clears calls ON_CLEAR; main.py installs the handler that wakes the waiting batches
   and clears the flag when the bot sends a normal message (the owner tapped verify).
4. tests/test_channels_primary_v1.py: the two assertions of the old behaviour (failed) now say waiting / later.

Every anchor must be found exactly once, or nothing is written.
usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not the expected file.
"""
import sys
from pathlib import Path

CH = "tgfetch/channels_first.py"
YB = "tgfetch/youtube_batch.py"
HC = "tgfetch/human_check.py"
MN = "tgfetch/main.py"
TS = "tests/test_channels_primary_v1.py"

WAIT = ("not on the Telegram channels; the music bot is waiting for a human check — "
        "verify it in Telegram and this song starts by itself")

P = [
    (CH,
     "        return _fail(worker, jid, f\"{NOT_ON_CHANNELS} ({why})\")\n",
     "        if \"human check\" in why:                    # fetch-waits-v1: wait for the owner's verify, do not fail\n"
     f"            db.update_job(worker.conn, jid, status=\"waiting\", error=\"{WAIT}\")\n"
     "            return \"later\"\n"
     "        return _fail(worker, jid, f\"{NOT_ON_CHANNELS} ({why})\")\n"),
    (CH,
     "        # The bot has just asked for the human check: do not hold the rest of the batch for it.\n"
     "        return _fail(worker, jid, f\"{NOT_ON_CHANNELS}; the music bot is waiting for a human check\")\n",
     "        # The bot has just asked for the human check: this song waits for the owner (fetch-waits-v1); the rest of\n"
     "        # the batch goes on with the channels.\n"
     f"        db.update_job(worker.conn, jid, status=\"waiting\", error=\"{WAIT}\")\n"
     "        return \"later\"\n"),
    (CH,
     "    t = re.sub(r\"\\s+\", \" \", cf._BRACKET.sub(\" \", title or \"\")).strip()\n"
     "    words = cf.artist_words(artist)\n"
     "    out = ([f\"{t} {words[0]}\"] if t and words else []) + ([t] if t else [])\n",
     "    t = re.sub(r\"\\s+\", \" \", cf._BRACKET.sub(\" \", title or \"\")).strip()\n"
     "    # fetch-waits-v1: \"Laali Laali - Tamil\", \"... - Ao Vivo\", \"... - Soundtrack Version\": the channels post the song\n"
     "    # under its plain name, and a search needs every word, so look for the name before the dash.\n"
     "    base = re.split(r\"\\s+-\\s+|\\s*\\|\\s*\", t, maxsplit=1)[0].strip()\n"
     "    t = base if len(base) >= 2 else t\n"
     "    words = cf.artist_words(artist)\n"
     "    out = ([f\"{t} {words[0]}\"] if t and words else []) + ([t] if t else [])\n"),
    (YB,
     "async def run(worker, b: dict, waiting: list) -> None:\n",
     "def _give_up_s(worker, normal: int) -> int:\n"
     "    \"\"\"A batch waiting for the owner's human check does not give up after a day: a week (HUMAN_CHECK_GIVE_UP_S).\n"
     "    fetch-waits-v1\"\"\"\n"
     "    import os\n"
     "    human = getattr(worker.source, \"human\", None)\n"
     "    if human is not None and human.flagged:\n"
     "        return max(normal, int(os.getenv(\"HUMAN_CHECK_GIVE_UP_S\", str(7 * 86400))))\n"
     "    return normal\n\n\n"
     "async def run(worker, b: dict, waiting: list) -> None:\n"),
    (YB,
     "        if time.time() - b[\"created_at\"] < MAINT_GIVE_UP_S:\n",
     "        if time.time() - b[\"created_at\"] < _give_up_s(worker, MAINT_GIVE_UP_S):\n"),
    (HC,
     "PROBE_S = int(os.getenv(\"BOT_CHECK_PROBE_S\", \"300\"))\n",
     "PROBE_S = int(os.getenv(\"BOT_CHECK_PROBE_S\", \"300\"))\n"
     "ON_CLEAR: list = []              # fetch-waits-v1: callables run when the flag clears (wake the waiting batches)\n"),
    (HC,
     "        log.info(\"the music bot answers normally again: human-check flag cleared\")\n",
     "        log.info(\"the music bot answers normally again: human-check flag cleared\")\n"
     "        for cb in list(ON_CLEAR):\n"
     "            try:\n"
     "                cb()\n"
     "            except Exception as e:\n"
     "                log.warning(\"human-check clear hook failed: %r\", e)\n"),
    (MN,
     "    doctor_task = asyncio.create_task(doctor.Doctor(settings).run_forever(), name=\"doctor\")\n",
     "    doctor_task = asyncio.create_task(doctor.Doctor(settings).run_forever(), name=\"doctor\")\n"
     "    from tgfetch import bot_verify          # fetch-waits-v1: verifying the bot starts the waiting songs at once\n"
     "    bot_verify.install(client, worker, settings)\n"),
    (TS,
     "    assert bot.calls == [] and j[\"status\"] == \"failed\" and \"human check\" in j[\"error\"]\n",
     "    assert bot.calls == [] and j[\"status\"] == \"waiting\" and \"human check\" in j[\"error\"]      # fetch-waits-v1\n"),
    (TS,
     "    assert run(chf.fetch_one(w, b, jid, cand, bot)) == \"done\"\n    assert \"human check\" in db.get_job(conn, jid)[\"error\"]\n",
     "    assert run(chf.fetch_one(w, b, jid, cand, bot)) == \"later\"      # fetch-waits-v1\n"
     "    assert \"human check\" in db.get_job(conn, jid)[\"error\"]\n"),
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
    print("fetch-waits-v1: channels_first.py, youtube_batch.py, human_check.py, main.py, one test file patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
