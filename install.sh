#!/bin/bash
set -e

# Ensure we are in the project root directory
cd "$(dirname "$0")"

echo "=== Building NaviVibe for Linux (Release) ==="
flutter build linux --release

echo "=== Creating Installation Directories ==="
mkdir -p "$HOME/.local/share/navivibe"
mkdir -p "$HOME/.local/share/icons"
mkdir -p "$HOME/.local/share/applications"
mkdir -p "$HOME/.local/bin"

echo "=== Copying Application Files ==="
# Clean old files first if any
rm -rf "$HOME/.local/share/navivibe/*"
cp -r build/linux/x64/release/bundle/* "$HOME/.local/share/navivibe/"

echo "=== Installing Icon ==="
cp assets/images/logo.png "$HOME/.local/share/icons/navivibe.png"

echo "=== Creating Executable Launcher ==="
cat << 'EOF' > "$HOME/.local/bin/navivibe"
#!/bin/bash
exec "$HOME/.local/share/navivibe/navivibe" "$@"
EOF
chmod +x "$HOME/.local/bin/navivibe"

echo "=== Creating Desktop Launcher Entry ==="
cat << EOF > "$HOME/.local/share/applications/navivibe.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=NaviVibe
Comment=High-performance music player for Subsonic-compatible servers
Exec=$HOME/.local/share/navivibe/navivibe
Icon=$HOME/.local/share/icons/navivibe.png
Terminal=false
Categories=AudioVideo;Audio;Music;Player;
StartupWMClass=navivibe
EOF

# Update desktop database if tool is available
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database "$HOME/.local/share/applications"
fi

echo "=============================================="
echo "Installation complete!"
echo "You can now launch NaviVibe from your applications menu"
echo "or by running: navivibe"
echo ""
echo "Note: Please ensure '$HOME/.local/bin' is in your PATH."
echo "=============================================="
