NaviVibe for Linux (x86_64)

Ubuntu 24.04 or newer, Debian 13 or newer, and distributions based on them:
use NaviVibe-linux-x64.deb instead of this archive. It installs everything:

    sudo apt install ./NaviVibe-linux-x64.deb

Arch Linux and distributions based on it: use NaviVibe-linux-x64.pkg.tar.zst.
Update the system first (the package is tested against current Arch):

    sudo pacman -Syu
    sudo pacman -U ./NaviVibe-linux-x64.pkg.tar.zst

Other distributions: unpack this archive anywhere and run ./navivibe.
Needs glibc 2.39 or newer and these libraries from your distribution
(Ubuntu names):

  required   libmpv2 libgtk-3-0t64 libsecret-1-0 libayatana-appindicator3-1
             libkeybinder-3.0-0 libgles2 libegl1 xdg-user-dirs ca-certificates
  optional   gnome-keyring or KWallet   keeps your sign-in key in the keyring
             zenity or kdialog          the "choose a folder / file" windows
             pulseaudio-utils, ffmpeg   "Identify a song"

Updates: NaviVibe does not update itself on Linux. Download the newer release.
