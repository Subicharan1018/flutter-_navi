#!/usr/bin/env bash
# Builds NaviVibe-linux-x64.pkg.tar.zst from the release tar.gz. Run as root in
# an archlinux:base-devel container:  package_arch.sh <dir with the tar.gz> <version> <build>
# The package is written beside the tar.gz.
set -euo pipefail

dist=$(realpath "$1")
version=$2
build=$3
repo=$(cd "$(dirname "$0")/../.." && pwd)

useradd -m builder # makepkg refuses to run as root
work=/home/builder/pkg
mkdir -p "$work"
cp "$dist/NaviVibe-linux-x64.tar.gz" "$repo/LICENSE" "$work/"
sed "s/@VERSION@/$version+$build/" "$repo/linux/packaging/arch/PKGBUILD" > "$work/PKGBUILD"
chown -R builder "$work"

# --nodeps: nothing is compiled, so building needs none of the run-time packages.
# The smoke test installs the result with them in a clean container.
su builder -c "cd '$work' && PKGEXT=.pkg.tar.zst makepkg --nodeps --noconfirm"
built=("$work"/navivibe-bin-*.pkg.tar.zst)
cp "${built[0]}" "$dist/NaviVibe-linux-x64.pkg.tar.zst"
pacman -Qip "$dist/NaviVibe-linux-x64.pkg.tar.zst"
