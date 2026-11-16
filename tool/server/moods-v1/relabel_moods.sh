#!/usr/bin/env bash
# moods-v1: ask the mood labeller again about the songs mood_audit flags, now that it
# reads the first verse plus the chorus (and English songs get their own prompt).
#
# Run on the server as subi, AFTER install.sh and the restart:
#     bash relabel_moods.sh                       # every flagged song
#     bash relabel_moods.sh --limit 150           # at most 150 (Groq's free tier has a daily cap)
#     bash relabel_moods.sh --reasons calm_loud,energetic_quiet
# Extra arguments go to `mood_audit --relabel` (see its --help).
#
# 1 prints the audit (read-only), 2 asks the labeller and saves the answers as a dry run
# (nothing written), 3 asks you before writing; mood_audit backs up mood_tags.json first.
set -euo pipefail
SHUF=${SHUF:-/opt/shuffle-server}
PY=$SHUF/venv/bin/python
[ -x "$PY" ] || { echo "!! $PY not found"; exit 1; }
[ "$(id -un)" != root ] || { echo "!! run as subi, not root"; exit 1; }
grep -q 'moods-v1' "$SHUF/navivibe/catalog/mood_tags.py" || { echo "!! install moods-v1 first (bash install.sh)"; exit 1; }

if [ -z "${GROQ_API_KEY:-}" ] && [ -f "$SHUF/.env" ]; then   # the key the server uses; nothing else is read
  GROQ_API_KEY=$(grep -E '^[[:space:]]*(export[[:space:]]+)?GROQ_API_KEY=' "$SHUF/.env" | tail -1 \
                 | sed -E 's/^[^=]*=//; s/^["'\'']//; s/["'\'']\s*$//')
  export GROQ_API_KEY
fi
[ -n "${GROQ_API_KEY:-}" ] || { echo "!! no GROQ_API_KEY in the environment or $SHUF/.env"; exit 1; }

cd "$SHUF"
export PYTHONPATH=$SHUF
mkdir -p "$SHUF/backups"
OUT=$SHUF/backups/moods-v1-relabel-$(date +%Y%m%d-%H%M%S).json

echo "== 1/3 the audit (read-only)"
"$PY" -m navivibe.catalog.mood_audit

echo "== 2/3 ask the labeller (dry run, saved to $OUT)"
"$PY" -m navivibe.catalog.mood_audit --relabel --save "$OUT" "$@"

echo "== 3/3 write"
read -r -p "Write the new labels into mood_tags.json (backed up first)? [y/N] " answer
case "$answer" in
  [yY]*) "$PY" -m navivibe.catalog.mood_audit --apply "$OUT" --write
         echo "Done. The app sees the new labels on its next catalog refresh; no restart needed." ;;
  *)     echo "Nothing written. Apply this dry run later with:"
         echo "    cd $SHUF && PYTHONPATH=$SHUF $PY -m navivibe.catalog.mood_audit --apply $OUT --write" ;;
esac
