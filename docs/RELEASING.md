# Releasing NaviVibe

One page: how a push becomes a release, how phones update, what you must set up.
Nothing in this repo publishes anything by itself. Until you create a GitHub
repository and push, none of this runs.

## How a push becomes a release

```
git push origin <any branch>
   └─ GitHub Actions: release.yml
        ├─ version   name from pubspec (1.0.0) + build number = run number + 100  → tag v1.0.0+<n>
        ├─ android   signed APKs per ABI (arm64-v8a, armeabi-v7a, x86_64) + one universal APK
        ├─ windows   zip of the Release folder + Velopack installer (Setup.exe, full + delta nupkg)
        ├─ publish   binary patches, latest.json, SHA256SUMS.txt, release notes from commit messages → GitHub Release
        └─ cleanup   deletes old pre-releases
```

* `ci.yml` runs `flutter analyze lib` and `flutter test` (goldens excluded, they are
  recorded on Windows) on every push and pull request.
* **Every push to any branch publishes.** Channels:
  * `main` → a normal release, marked **latest** (`NaviVibe v1.0.0+130`). This is what
    the app follows by default.
  * any other branch → a **pre-release** named `NaviVibe v1.0.0+131 (branch-name)`.
    It never becomes "latest". The app only offers it when you switch on
    **Settings → About → Updates → Include pre-releases (beta)** (off by default).
* **Skip a release:** put `[skip release]` in the head commit message. CI still runs.
* Rapid pushes to one branch: the newest cancels the older runs (concurrency group per
  branch), so only the last push is published. A run cancelled while it uploads can
  leave nothing or a half-made release; delete it on GitHub and push again.
* **Clean-up:** a `cleanup` job at the end of `release.yml` runs once per release, only
  after it was published (a push-triggered run that is skipped or cancelled never
  cleans). `cleanup-prereleases.yml` is a daily safety net plus a manual button
  (Actions → Clean up pre-releases); it has no push or call trigger. Both run
  `tool/release/cleanup_prereleases.sh`: keep the newest 10 pre-releases younger than
  30 days, delete the rest with their tags, never touch normal releases.
* **Build time:** the universal APK compiles everything a second time, so only `main`
  builds it; beta (branch) releases carry the three per-ABI APKs only. Flutter, pub
  and Gradle caches are restored between runs. Actions are pinned to exact Node-24
  versions and Linux jobs to `ubuntu-24.04`, so a runner-image change never alters a
  build; bump them deliberately.
* Only Actions on your own repository run the workflow with secrets; there is no
  pull-request trigger, so forks never see the signing key. `ci.yml` uses
  `pull_request` and no secrets.
* The build number only goes up across all branches (`run_number + BUILD_NUMBER_OFFSET`,
  offset defaults to 100 so it stays above the `+2` already installed). To jump ahead,
  set the repository variable `BUILD_NUMBER_OFFSET`.
* **Patches:** each release carries patches cut against the last 3 normal releases plus
  the last 2 pre-releases, whichever branch they came from. A phone on any of those gets
  a small patch; a phone further behind gets the full APK. (Simplest rule that stays
  correct: the app only uses a patch whose source file matches the installed APK by
  SHA-256, so a patch can never be applied to the wrong base.)
* To bump the user-visible version (1.0.0 → 1.1.0), edit `version:` in `pubspec.yaml`
  (the part after `+` is ignored by CI).
* **Roll back:** delete the bad release (and its tag) on GitHub. The app reads
  "latest release", so it falls back to the previous one. Phones that already
  installed the bad build will not go backwards (Android refuses a lower
  `versionCode`); ship a fix as a new push instead.

## How updates reach people (sizes)

| Route | Download |
|---|---|
| First install, arm64 phone | one per-ABI APK (about the size in the table below) instead of the universal APK |
| Update, patch | **the changes only**, see the table: it depends on how much Dart code changed |
| Update, fallback | the full per-ABI APK (patch missing, installed APK not the one a patch was cut from, or more than 10 builds behind) |

Measured on this repo (release build, `--split-per-abi`): see
[Measured sizes](#measured-sizes). A patch is a `bsdiff` of the whole signed APK,
so it only works because native libraries are stored **uncompressed** in the APK
(`useLegacyPackaging = false`, `extractNativeLibs="false"`); `release.yml` fails
the build if a `.so` is compressed.

In the app: **Settings → About → Updates** (address of your releases, optional
token, Wi-Fi only). Home shows a dismissible "Update available, 3.2 MB" line.
Flow: read `latest.json` → pick a patch cut from *this exact installed APK*
(matched by SHA-256) → download (resumable) → rebuild the new APK in an isolate →
verify SHA-256 → hand it to the Android installer. Any failure → full APK.

Android shows the system install sheet; the first time, it asks you to allow
installs from NaviVibe.

### Windows

`vpk pack` (Velopack) produces `NaviVibe-win-Setup.exe`, full and delta `.nupkg`
files and `releases.win.json`. The release also carries a plain zip.

* First install: run `NaviVibe-win-Setup.exe` (installs per user, no admin).
* The in-app updater downloads the newest `Setup.exe` and runs it; Velopack's
  setup replaces the install in place and keeps your data. That is a **full**
  download (~tens of MB), not a delta.
* Delta updates on Windows need Velopack's own client library in the app. The
  Flutter wrapper (`velopack_flutter`) requires a **Rust toolchain on every build
  machine**, so it is not added here (it would break Android/CI builds for
  anyone without Rust). CI already publishes the delta packages and
  `releases.win.json`, so adding the client later needs no CI change.
* **Needs a real Windows machine to verify:** the `windows-latest` CI job, `vpk pack`
  output names (the copy filter in `release.yml` assumes
  `NaviVibe-<MAJOR.MINOR.BUILD>-*.nupkg` and `*Setup.exe`), Setup.exe replacing a
  running install, and the app exiting cleanly so Setup can overwrite it.
  Windows version is `MAJOR.MINOR.BUILD` (Velopack wants SemVer), e.g. `1.0.101`.

## What you must do (once)

The repository is **public** (`github.com/Subicharan1018/flutter-_navi`), so
**anyone can download every release** and read the history. The update address
and token in the app are optional; with a public repo no token is needed.

1. **Repository:** already created. Make sure no secrets or personal data are in git
   history (see "Public repository: what leaks").
2. **Signing key** (see next section) → add four secrets.
3. **Add the secrets:** repo → Settings → Secrets and variables → Actions → New repository secret.
4. Push `main`. Watch Actions → Release. The first release has no patches (nothing
   to diff against); from the second build onward patches appear.
5. **On your phone / PC:** install the first release once (`NaviVibe-arm64-v8a.apk`
   or the Windows Setup.exe), then Settings → About → Updates → address
   `github:<you>/<repo>` (+ token for a private repo).

### Signing key and secrets

Android only updates an installed app when the new APK is signed with the **same
key**. Your phones currently have builds signed with the **debug key**
(`%USERPROFILE%\.android\debug.keystore`, alias `androiddebugkey`, password
`android`). Recommended: **reuse it as the release key**, so every phone you
already installed updates in place and you never uninstall.

Trade-off: the debug keystore's password is the well-known `android`, so anyone
who gets the file can sign an APK that Android treats as an update to yours.
Fine for a personal app on your own devices; if you ever distribute widely,
create a new keystore and ask users to reinstall once (their data/settings are
lost with the uninstall). Keep the keystore out of the repo (`*.keystore` is
git-ignored) and in a password manager as a backup: if you lose it, nobody can
update without reinstalling.

Secrets (all four are needed; nothing is generated or stored for you):

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | the keystore file, base64 |
| `KEYSTORE_PASSWORD` | store password (`android` for the debug keystore) |
| `KEY_ALIAS` | alias (`androiddebugkey` for the debug keystore) |
| `KEY_PASSWORD` | key password (`android` for the debug keystore) |

Create `KEYSTORE_BASE64` (PowerShell; it copies to the clipboard instead of printing):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.android\debug.keystore")) | Set-Clipboard
```

Paste into the secret field. Optional repository variable: `BUILD_NUMBER_OFFSET`.

Local release builds (same signature): create `android/key.properties` (git-ignored)

```properties
storeFile=C:/Users/<you>/.android/debug.keystore
storePassword=android
keyAlias=androiddebugkey
keyPassword=android
```

Without that file the release build uses the debug key anyway, which is the same key
in this setup. CI uses the `NAVI_KEYSTORE_*` environment variables.

## Private repository: tokens

GitHub Release assets of a private repo are not downloadable anonymously. In
the app (Settings → About → Updates → Token) paste a **fine-grained personal access
token** limited to this one repository with **Contents: Read-only** and no other
permission. It is stored in the app's encrypted store on the device and only
sent to GitHub. Use the address `github:<you>/<repo>` (not a release asset URL).
If the token is leaked, delete it in GitHub; nothing else is exposed.

The token lets a person read the whole repository, so only put it on devices you
own. If someone else should get updates, host `latest.json` + files somewhere
else (a static host or your server) and give them that address with no token.

## Public repository: what leaks

* Everything in git history, not only the current files. Check for the Navidrome
  **server URL**, usernames/passwords, API keys and personal notes
  (`api_refernce.md`, screenshots, `graphify-out/`, `.gemini/`) before the first push.
  Rewrite or start from a clean repo; deleting a file later does not remove it from history.
* Anyone can read how the app talks to your server (API behaviour, endpoints,
  auth scheme), so assume the server URL is public and keep the server itself
  protected (strong passwords, rate limits, preferably behind a VPN/tunnel).
* Release assets and `latest.json` are public; so is every build. Workflow files
  contain no secrets (they read GitHub secrets), but the Actions logs are public.
* Fork pull requests cannot see the signing secrets. Still, never add a
  `pull_request_target` or `workflow_run` trigger that checks out fork code.
* The updater in the app has **no built-in address**; the repo name appears only in
  `latest.json` (`assetBase`) after CI writes it.

## What a published build contains

**Every published build includes the download features** (Search Online, Send a
playlist link, Recognize > Download). Who may use them is decided by your server
(login plus its download access list), not by the app build; `release.yml` sets
`public=false`, so no `PUBLIC_BUILD` define is passed. The compile-time switch still
exists for the day you want a build without the download UI: set `public=true` in the
`version` job of `release.yml` (or pass `--dart-define=PUBLIC_BUILD=true` locally /
`-Public` to `tool/make_release_local.ps1`). In that flavour (`lib/core/build_flavor.dart`,
`kPublicBuild`) every entry point reads `onlineFetchAvailableProvider`, so no button is
left dead, and the sign-in screen does not pre-fill a server address. Tests in
`test/features/online_fetch/public_build_test.dart` cover both states.

* **Manual run without releasing:** Actions → Release → Run workflow → tick
  `personal_build`. It builds everything but publishes **nothing** and leaves workflow
  artifacts that expire after 1 day. Artifacts of a *public* repository can be
  downloaded by any signed-in GitHub user while they exist, so for a private build run
  `.\tool\make_release_local.ps1` instead.
* **Backup of the full feature set:** the local branch/tag
  `backup/full-feature-set-2026-10-25` keeps the app exactly as it was before the
  public/personal split. It lives only in your local clone unless you push it; do not
  push it to the public repository.
* Still in the source regardless of flavour: the hosted shuffle and session-sync
  addresses (`shuffle.subimusic.me`, `session.subimusic.me`). They are visible to
  anyone who reads the code; decide whether that is acceptable before going public.

## Local dry run

```powershell
.\tool\make_release_local.ps1                 # APKs, latest.json, SHA256SUMS in build\release_local
.\tool\make_release_local.ps1 -PrevDir build\release_local\archive   # + patches against earlier runs
.\tool\make_release_local.ps1 -Windows        # + Windows zip (and Velopack if vpk is installed)
```

Prerequisites: Flutter, Android SDK, `python -m pip install bsdiff4`.

Update-size checks without a build: `dart run tool/update_size_report.dart` (synthetic) or
`dart run tool/update_size_report.dart old.apk new.apk` (two real builds). Patch
logic is covered by `flutter test test/features/updates`.

## Version codes (why updates never get blocked)

Android refuses an install whose `versionCode` is not higher than the installed one.
Flutter's `--split-per-abi` builds use `versionCode = abiOffset * 1000 + buildNumber`
with offsets armeabi-v7a 1, arm64-v8a 2, x86_64 4. CI's build number is
`run_number + 100` (never reused, and it rises across all branches), so within one ABI
every release has a higher versionCode than the one before (e.g. arm64 build 109 is
2109, build 110 is 2110). Consequences:

* A phone with 2109 (arm64, +109) takes any later CI release.
* Builds you made locally with `flutter build apk` use the pubspec number (`+2`), i.e.
  versionCode 2 (universal) or 2002 (arm64 split), far below CI's 2101+, so CI always
  upgrades them. The reverse is not true: **never install a local build with a high
  `--build-number` over a CI build**, and `tool/make_release_local.ps1` therefore
  defaults to build number 1 (a dry run you inspect, not install).
* Installing the **universal** APK over a per-ABI one is a downgrade (e.g. 110 < 2109)
  and Android refuses it; uninstall first or stay on per-ABI APKs. Per-ABI over
  universal is fine.
* Above build 999 the arm64 code (2000 + build) overlaps other ABIs' ranges, which is
  harmless (a phone only ever sees its own ABI). The Updates screen reads the real
  build number from the `NAVI_BUILD` define CI bakes in, not from the versionCode.
* The ceiling is 2 100 000 000, which is unreachable here.

## Measured sizes

Real release builds on this repo (builds 101 → 102, where 102 adds the whole updater
feature, so a bigger change than a typical commit), all signed with the same key:

| | arm64-v8a | armeabi-v7a | x86_64 |
|---|---|---|---|
| Full per-ABI APK | 29.4 MiB | 27.8 MiB | 31.0 MiB |
| Patch from the previous build | **1.9 MiB** | 2.1 MiB | 1.9 MiB |

* The universal APK (all ABIs in one file) was 70–77 MB before this change; a
  phone now downloads only its own ABI.
* Native libraries in the APK are stored uncompressed (`libapp.so` 11.6 MiB,
  `libflutter.so` 11.2 MiB), checked with `tool/release/verify_apk.py`.
* Applying the 1.9 MiB patch with the app's Dart code takes about 1 s on a PC and the
  result is byte-identical to the new APK (checked by SHA-256). Time on a phone
  is not measured.
* Expect larger patches when many Dart files change or Flutter itself is upgraded
  (`libflutter.so` changes); then the app falls back to a patch from the nearest
  build or the full APK.
