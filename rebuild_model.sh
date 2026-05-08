#!/bin/bash
set -e

# ==============================================================================
# NaviVibe Shuffle Model Rebuild Script
# ==============================================================================
# Instructions for cron:
# Run `crontab -e` and add the following line to rebuild every week (e.g. Sunday at 3 AM):
# 0 3 * * 0 /home/subi/Documents/flutter-_navi/rebuild_model.sh >> /tmp/shuffle_rebuild.log 2>&1
# ==============================================================================

WORKDIR="/home/subi/Documents/flutter-_navi"
PYTHON="/usr/bin/python3"

# Update these paths to where your CSV exports are actually located
APPLE_CSV="${WORKDIR}/Apple Music Play Activity.csv"
FLAC_CSV="${WORKDIR}/flac_metadata.csv"
LIKES_CSV="/home/subi/Downloads/Apple_Music_-_Favorites.csv"

echo "================================================================="
echo "Starting Shuffle Model rebuild at $(date)"
echo "================================================================="

cd "$WORKDIR"

# Execute the build pipeline
$PYTHON shuffle_model.py --build \
  --apple "$APPLE_CSV" \
  --flac "$FLAC_CSV" \
  --likes "$LIKES_CSV"

echo "Rebuild completed successfully."

# Optional: restart the systemd service so it picks up the new JSON file.
# Note: Unless subi has sudoers NOPASSWD for systemctl restart, this might fail in cron.
# sudo systemctl restart shuffle.service

echo "Done at $(date)"
