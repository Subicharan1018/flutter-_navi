# NaviVibe as a music player on the desktop

What makes Windows and Linux treat NaviVibe as a music player, and how to check each part.

## Windows

| Item | Where | Status |
|---|---|---|
| Media session (SMTC): volume flyout, media keys, touchpad tap, lock screen | `lib/services/windows_smtc*.dart`, `smtc_windows`, `flutter_rust_bridge` pinned to 2.11.1 (`test/services/smtc_frb_pin_test.dart`) | existing |
| Stable AppUserModelID `NaviVibe` on the process | `windows/runner/main.cpp` (`SetCurrentProcessExplicitAppUserModelID`) | existing |
| Name + icon for that ID (so the flyout does not say "Unknown app") | `AppNotifier.registerWindowsIdentity` writes `HKCU\Software\Classes\AppUserModelId\NaviVibe` | existing |
| Same ID on the shortcuts | `install.ps1` stamps `System.AppUserModel.ID` on the Desktop and Start Menu `.lnk` | new |
| Title, artist, album, thumbnail, timeline, previous / play / pause / next / stop | `SmtcController` | existing |
| File types `.mp3 .flac .m4a .ogg .opus .wav`, "Open with", Default apps entry | `lib/services/desktop_registration.dart`: one `reg import` per release launch, HKCU only (ProgId `NaviVibe.Audio`, `Applications\navivibe.exe`, `Software\NaviVibe\Capabilities`, `RegisteredApplications`) | new |
| A file passed on the command line plays | `audioFilesFromArgs` in `main.dart` | new |
| A file opened while NaviVibe already runs | runner forwards it with `WM_COPYDATA` to the running window, channel `navivibe/open_files` | new |

Not possible with the current plugin: seek from the flyout. `smtc_windows` 1.1.0 exposes buttons, shuffle and repeat requests but no position-change request. The timeline is shown; dragging it in the flyout does nothing.

Windows 10/11 do not let an app make itself the default for a file type. Registration makes NaviVibe appear in Settings > Apps > Default apps and in "Open with"; the user picks it once.

### Verify

1. **SMTC started.** Run a build (`flutter run -d windows`, or the installed exe from a terminal). The output must not contain `[SMTC] unavailable`. Play a song, then list sessions:
   ```powershell
   Add-Type -AssemblyName System.Runtime.WindowsRuntime
   [void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
   $m = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync().GetAwaiter().GetResult()
   $m.GetSessions() | % { $_.SourceAppUserModelId; ($_.TryGetMediaPropertiesAsync().GetAwaiter().GetResult() | select Title,Artist,AlbumTitle) }
   ```
   (Windows PowerShell 5.1.) Expect a session with `SourceAppUserModelId` = `NaviVibe` and the song's title, artist and album.
2. **Name and icon.** Press a media key or change volume: the flyout shows "NaviVibe" with its icon and the cover.
3. **Media keys / touchpad tap** with the window minimised and unfocused: play/pause, next, previous work.
4. **Identity keys:** `reg query HKCU\Software\Classes\AppUserModelId\NaviVibe`.
5. **File types (installed/release build only; debug runs skip it):** launch once, then
   ```powershell
   reg query HKCU\Software\RegisteredApplications /v NaviVibe
   reg query HKCU\Software\Classes\.flac\OpenWithProgids
   ```
   Settings > Apps > Default apps > NaviVibe lists the six types. Right-click a `.flac` > Open with > NaviVibe.
6. **Command line:** `navivibe.exe "C:\Music\a.flac" "C:\Music\b.mp3"` plays both as a queue. With NaviVibe already running (also hidden in the tray) run it again with a file: the window comes forward and the file plays.
7. **Shortcut ID** (after `install.ps1`): the property `System.AppUserModel.ID` on `NaviVibe.lnk` is `NaviVibe` (shell property viewer or `(New-Object -ComObject Shell.Application).NameSpace(<folder>).ParseName('NaviVibe.lnk')`).

### Notes

- Velopack installs run the exe only for its `--veloapp-*` hooks, which exit before anything is registered; registration happens at the first normal launch and is repeated on each launch (idempotent), so the entries follow the `current\navivibe.exe` path across updates. A Velopack uninstall leaves the HKCU keys behind (harmless, nothing resolves); `install.ps1`'s uninstaller removes them.
- Velopack's `vpk pack` creates its own shortcuts; if the volume flyout still shows a different name for a Velopack install, check the shortcut's `System.AppUserModel.ID` (item 7) first.

## Linux

| Item | Where |
|---|---|
| MPRIS on the session bus, identity `NaviVibe`, bus name `org.mpris.MediaPlayer2.com.navivibe.audio.instance<pid>` | `AudioServiceMpris.registerWith()` in `main.dart`; identity and name come from `AudioServiceConfig` (`androidNotificationChannelName` / `androidNotificationChannelId`) |
| `.desktop` entry: `Categories=AudioVideo;Audio;Player;Music;`, `MimeType=audio/…;`, `Icon=navivibe`, `StartupWMClass=navivibe` | `packaging/linux/navivibe.desktop` |
| Install the entry and icon for the user | `packaging/linux/install-desktop.sh <path to the navivibe binary>` (icon from `music.png`) |
| Files on the command line play | same `audioFilesFromArgs` path as Windows (`%F` in `Exec`) |

Limits: the repo has no `linux/` runner yet, so there is no Linux build to test here. `audio_service_mpris` 0.2.1 reports an empty `DesktopEntry` property and no supported MIME types, so shells match the player by name/bus name instead of `navivibe.desktop`. A second launch on Linux starts a second instance (no forwarding).

### Verify (on a Linux machine with a Linux build)

```sh
packaging/linux/install-desktop.sh build/linux/x64/release/bundle/navivibe
desktop-file-validate ~/.local/share/applications/navivibe.desktop
gio mime audio/flac            # NaviVibe listed as registered application
playerctl -l                   # com.navivibe.audio.instance<pid>
playerctl -p com.navivibe.audio.instance<pid> metadata
navivibe ~/Music/a.flac        # plays
```

## Tests

`test/services/desktop_registration_test.dart`: argument filtering, the generated `.reg` (escaping, every extension, HKCU only, Capabilities), the UTF-16 import file, forwarded-path decoding.
