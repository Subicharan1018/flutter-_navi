#!/usr/bin/env python3
"""Merge several Exportify CSVs into one file for ONE import in the app (the importer takes one CSV at a time).

The `Added By` and `Added At` columns are dropped (the importer never reads them either). Rows with the same ISRC (or, without
one, the same track URI) are kept once. Only rows with a title are written. Empty files are skipped.

    python tool/exportify/merge_exportify.py Navivibe_sample_0*.csv --out merged.csv
"""
import argparse
import csv
import sys

DROP = {"added by", "added at"}


def merge(paths):
    header, seen, rows, per_file = None, set(), [], []
    for p in paths:
        with open(p, encoding="utf-8-sig", newline="") as f:
            rd = csv.DictReader(f)
            cols = [c for c in (rd.fieldnames or []) if c.strip().lower() not in DROP]
            if not cols:
                per_file.append((p, 0, 0))
                continue
            header = header or cols
            kept = total = 0
            for r in rd:
                total += 1
                if not (r.get("Track Name") or "").strip():
                    continue
                key = (r.get("ISRC") or "").strip().upper() or (r.get("Track URI") or "").strip() or None
                if key and key in seen:
                    continue
                seen.add(key)
                rows.append({c: r.get(c, "") for c in header})
                kept += 1
            per_file.append((p, total, kept))
    return header, rows, per_file


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    header, rows, per_file = merge(a.files)
    if not header:
        print("no rows in any file", file=sys.stderr)
        return 2
    with open(a.out, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=header)
        w.writeheader()
        w.writerows(rows)
    for p, total, kept in per_file:
        print("%s: %d rows, %d new" % (p, total, kept))
    print("wrote %d rows to %s" % (len(rows), a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
