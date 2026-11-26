#!/usr/bin/env bash
# Turns a `flutter build linux --release` bundle into the release files:
#   NaviVibe-linux-x64.deb     Ubuntu 24.04+ / Debian 13+, apt installs the dependencies
#   NaviVibe-linux-x64.tar.gz  other distributions
# Usage: package_linux.sh <bundle-dir> <version> <build> <out-dir>
set -euo pipefail

bundle=$(realpath "$1")
version=$2
build=$3
mkdir -p "$4"
out=$(realpath "$4")
repo=$(cd "$(dirname "$0")/../.." && pwd)
id=com.navivibe.navivibe

test -x "$bundle/navivibe"
test -f "$bundle/lib/libapp.so"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

app="$work/NaviVibe"
cp -a "$bundle" "$app"
# The `jni` package (Android only) builds this when the machine has a JDK. It
# needs libjvm.so, and nothing on Linux loads it.
rm -f "$app/lib/libdartjni.so"

# ── tar.gz ───────────────────────────────────────────────────────────────────
cp "$repo/linux/packaging/README-linux.txt" "$app/"
cp "$repo/linux/packaging/$id.desktop" "$app/"
cp "$repo/assets/images/logo.png" "$app/$id.png"
tar -C "$work" --owner=0 --group=0 -czf "$out/NaviVibe-linux-x64.tar.gz" NaviVibe

# ── deb ──────────────────────────────────────────────────────────────────────
root="$work/deb"
mkdir -p "$root/DEBIAN" "$root/opt" "$root/usr/bin" "$root/usr/share/applications" \
  "$root/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle" "$root/opt/navivibe"
rm -f "$root/opt/navivibe/lib/libdartjni.so"
ln -s /opt/navivibe/navivibe "$root/usr/bin/navivibe"
cp "$repo/linux/packaging/$id.desktop" "$root/usr/share/applications/"
cp "$repo/assets/images/logo.png" "$root/usr/share/icons/hicolor/512x512/apps/$id.png"

# Library dependencies are read from the binaries, so a new plugin cannot be forgotten.
mkdir -p "$work/shlibs/debian"
printf 'Source: navivibe\n\nPackage: navivibe\nArchitecture: amd64\n' > "$work/shlibs/debian/control"
mapfile -t binaries < <(find "$root/opt/navivibe" -type f \( -name navivibe -o -name '*.so' \))
shlibs=$(cd "$work/shlibs" && dpkg-shlibdeps -O --ignore-missing-info \
  -l"$root/opt/navivibe/lib" "${binaries[@]}" | sed -n 's/^shlibs:Depends=//p')
test -n "$shlibs" || { echo "dpkg-shlibdeps found no dependencies" >&2; exit 1; }

# Loaded at run time, so no binary links to them:
#   libmpv2        audio playback (media_kit opens libmpv.so.2)
#   xdg-user-dirs  path_provider runs xdg-user-dir; without it the app cannot start
#   ca-certificates HTTPS
depends="$shlibs, libmpv2, xdg-user-dirs, ca-certificates"
recommends="gnome-keyring | kwalletmanager, zenity | kdialog, pulseaudio-utils, ffmpeg"
size=$(du -sk "$root/opt" | cut -f1)

cat > "$root/DEBIAN/control" <<EOF
Package: navivibe
Version: $version+$build
Section: sound
Priority: optional
Architecture: amd64
Installed-Size: $size
Depends: $depends
Recommends: $recommends
Maintainer: NaviVibe <noreply@github.com>
Homepage: https://github.com/Subicharan1018/flutter-_navi
Description: Music player for Navidrome and Subsonic servers
 NaviVibe streams and downloads music from your own Navidrome or Subsonic
 server.
EOF

chmod -R u=rwX,go=rX "$root"
dpkg-deb --root-owner-group --build "$root" "$out/NaviVibe-linux-x64.deb"

dpkg-deb --info "$out/NaviVibe-linux-x64.deb"
ls -l "$out"
