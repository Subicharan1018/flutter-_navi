#!/bin/bash
set -e

# Ensure we are in the project root directory
cd "$(dirname "$0")/.."

echo "=== Pre-release Verification ==="

# Check git status
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: Working directory is not clean. Commit or stash changes first."
  exit 1
fi

# Get current version from pubspec.yaml
VERSION_LINE=$(grep "^version:" pubspec.yaml)
if [ -z "$VERSION_LINE" ]; then
  echo "Error: Could not find version line in pubspec.yaml."
  exit 1
fi

VERSION_STR=$(echo "$VERSION_LINE" | cut -d' ' -f2)
BASE_VERSION=$(echo "$VERSION_STR" | cut -d'+' -f1)
BUILD_NUMBER=$(echo "$VERSION_STR" | cut -d'+' -f2)

if [ -z "$BUILD_NUMBER" ]; then
  echo "Warning: No build number found. Defaulting build number to 1."
  BUILD_NUMBER=1
fi

# Increment build number
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION="$BASE_VERSION+$NEW_BUILD_NUMBER"
TAG_NAME="v$NEW_VERSION"

echo "Current Version: $VERSION_STR"
echo "Target Release Version: $NEW_VERSION"
echo "Target Git Tag: $TAG_NAME"
echo ""

# Step 1: Update pubspec.yaml
echo "=== Bumping Version ==="
sed -i "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
echo "pubspec.yaml updated to version: $NEW_VERSION"

# Step 2: Run analysis and tests
echo "=== Running Analysis and Tests ==="
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test

# Step 3: Build release binaries
echo "=== Building Android Release APK ==="
flutter build apk --release

echo "=== Building Linux Release Bundle ==="
flutter build linux --release

# Step 4: Commit and tag in Git
echo "=== Committing and Tagging ==="
git add pubspec.yaml
git commit -m "chore(release): bump version to $NEW_VERSION"
git tag -a "$TAG_NAME" -m "Release $TAG_NAME"

# Step 5: Push to Github
echo "=== Pushing to Github ==="
git push origin main --tags

echo "=============================================="
echo "Release $TAG_NAME successfully created and pushed!"
echo "=============================================="
