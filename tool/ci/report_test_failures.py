#!/usr/bin/env python3
"""Turn a `flutter test --file-reporter json:<file>` report into GitHub annotations.

The github reporter only prints totals in the check-run annotations; this names each
failing test (with its first error line) and each skipped test, so a red run can be
diagnosed from the public annotations API without a login.
"""
import json
import sys


def main(path: str) -> int:
    names, errors, skipped = {}, {}, []
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            t = e.get("type")
            if t == "testStart":
                names[e["test"]["id"]] = e["test"]["name"]
            elif t == "error":
                errors.setdefault(e["testID"], []).append(
                    (e.get("error", "") + "\n" + e.get("stackTrace", "")).strip()
                )
            elif t == "testDone" and e.get("skipped"):
                skipped.append(e["testID"])
    for tid, errs in errors.items():
        first = errs[0].replace("%", "%25").replace("\r", "").replace("\n", "%0A")
        print(f"::error title=FAILED {names.get(tid, tid)}::{first[:1500]}")
    for tid in skipped:
        n = names.get(tid, tid)
        if n.startswith("loading "):
            continue
        print(f"::warning title=SKIPPED::{n}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
