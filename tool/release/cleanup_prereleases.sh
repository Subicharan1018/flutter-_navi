#!/usr/bin/env bash
# Deletes old pre-releases (and their tags): keeps the newest 10 younger than 30
# days. Never touches normal releases. Needs GH_TOKEN (contents: write) and GH_REPO.
set -euo pipefail
cd "$(dirname "$0")/../.."
gh release list --limit 200 --json tagName,isPrerelease,createdAt \
  | python3 tool/release/prune_prereleases.py --keep 10 --days 30 > prune.txt
while IFS= read -r tag; do
  [ -n "$tag" ] || continue
  echo "deleting pre-release $tag"
  # A parallel clean-up may have removed it already.
  gh release delete "$tag" --cleanup-tag --yes || true
done < prune.txt
