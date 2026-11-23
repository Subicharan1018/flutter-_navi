"""Apply (or check) the tgfetcher-tests-fix-v1 edit to the tg-fetcher's tests/conftest.py. No tg-fetcher code changes.

    python patch.py <tg-root>            apply; the edit must match exactly once
    python patch.py <tg-root> --check    only report applied / pending / mismatching

tgfetch/config.py loads <tg-root>/.env at import (`os.environ.setdefault`, so a variable that is already set wins),
and several modules read their tunables at import (exportify.BATCH_SIZE, GB_PER_HOUR) or per call (channels_first).
So a live tree with a real .env ran the suite with production values and two tests failed. conftest.py now pins
every tunable the code reads to its documented default BEFORE tgfetch is imported: .env can no longer change a test.
"""
import os
import sys

EDITS = []


def edit(rel, marker, old, new):
    EDITS.append((rel, marker, old, new))


# Documented defaults (the `os.getenv(NAME, default)` in the code). Secrets and ids are pinned to empty.
PINS = '''# tgfetcher-tests-fix-v1: the suite never depends on the live .env. tgfetch/config.py loads .env with
# os.environ.setdefault, so a variable pinned here wins over it. Every tunable the code reads is pinned to its
# documented default before tgfetch is imported (exportify.BATCH_SIZE / GB_PER_HOUR are read at import).
# A test that needs another value sets it itself (monkeypatch.setenv / setattr).
_PINNED_ENV = {
    "TG_API_ID": "", "TG_API_HASH": "", "TG_SOURCE": "@deezload2bot", "TG_SEARCH_PREFIX": ".trk",
    "TG_DOWNLOAD_CONNECTIONS": "8", "TG_DOWNLOAD_PART_KB": "512",
    "LLM_API_KEY": "", "GROQ_API_KEY": "", "INTERNAL_TOKEN": "", "NTFY_TOPIC": "", "NTFY_SERVER": "https://ntfy.sh",
    "ND_USER": "", "ND_PASS": "", "ALLOWED_USERS": "admin", "ADMIN_USERS": "admin", "ALLOWED_MIMES": "audio/x-flac,audio/flac",
    "MAX_ATTEMPTS": "3", "MAX_QUEUED_LINKS": "2", "SEARCHES_PER_DAY": "0", "JOBS_PER_DAY": "0", "GLOBAL_JOBS_PER_DAY": "0",
    "JOB_CONCURRENCY": "2", "SEARCH_MAX_ATTEMPTS": "5", "SEARCH_RETRY_BASE_S": "20", "SEARCH_VARIANTS": "6",
    "TRENDING_PARALLEL": "2", "REQUEST_RACE": "1",
    "FETCH_PRIMARY": "channels", "FETCH_BOT_FALLBACK": "1", "CHANNEL_MAX_MB": "100", "CHANNEL_MIN_FREE_GB": "25",
    "CHANNEL_SEARCH_GAP_S": "6", "CHANNEL_SKIP_EDITS": "1", "CHANNEL_FALLBACK": "1",
    "EXPORTIFY_BATCH_SIZE": "25", "EXPORTIFY_GB_PER_HOUR": "0.51",
}
os.environ.update(_PINNED_ENV)
# read per call, default "unset": cleared again after config has loaded the .env
_UNSET_AFTER_CONFIG = ("CHANNEL_FALLBACK_CHANNELS", "DATA_QUEUE_OFF", "HUMAN_CHECK_FILE")
'''

edit("tests/conftest.py", "_PINNED_ENV = {",
     '''os.environ["INTERNAL_HMAC_SECRET"] = ""
''',
     '''os.environ["INTERNAL_HMAC_SECRET"] = ""
''' + PINS)

edit("tests/conftest.py", "_UNSET_AFTER_CONFIG:",
     '''from tgfetch import db
''',
     '''from tgfetch import config as _config  # noqa: E402,F401  (loads .env: setdefault, the pins above win)

for _k in _UNSET_AFTER_CONFIG:
    os.environ.pop(_k, None)

from tgfetch import db
''')


def run_edits(root, check_only):
    texts, plan = {}, []
    for rel, marker, old, new in EDITS:
        path = os.path.join(root, rel)
        if rel not in texts:
            if not os.path.exists(path):
                print("!! missing file:", path)
                return 2
            with open(path, encoding="utf-8", newline="") as f:
                texts[rel] = f.read()
        text = texts[rel]
        if marker in text:
            plan.append((rel, marker, "applied"))
            continue
        if "\r\n" in text:                       # the live conftest.py has Windows line endings: keep them
            old, new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
        n = text.count(old)
        if n != 1:
            plan.append((rel, marker, "MISMATCH (old text found %d times)" % n))
            continue
        plan.append((rel, marker, "pending"))
        texts[rel] = text.replace(old, new)
    for rel, marker, st in plan:
        print("  %-9s %-20s %s" % (st.split(" ")[0], rel, marker.strip()[:36]))
    bad = [p for p in plan if p[2].startswith("MISMATCH")]
    for rel, marker, st in bad:
        print("!!", rel, marker.strip()[:36], st)
    if bad:
        print("!! the live tests are not what this package was built on; nothing written")
        return 1
    if check_only:
        return 0
    for rel, text in texts.items():
        path = os.path.join(root, rel)
        with open(path, encoding="utf-8", newline="") as f:
            if f.read() == text:
                continue
        tmp = path + ".tgfetcher-tests-fix-v1.tmp"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(run_edits(sys.argv[1], "--check" in sys.argv))
