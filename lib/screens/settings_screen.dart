import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart' show CircularProgressIndicator, Colors, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/motion.dart' show MotionLevel;
import '../core/theme.dart';
import '../core/focus/navi_focus.dart';
import '../utils/platform_utils.dart';
import '../features/everyday/profile_picker_screen.dart';
import '../features/exportify_import/ui/exportify_import_section.dart';
import '../features/album_overnight/ui/album_overnight_settings.dart';
import '../features/weekly_exploration/ui/weekly_exploration_settings.dart';
import '../features/flow/ui/flow_settings.dart';
import '../features/listenbrainz/ui/listenbrainz_section.dart' show ListenBrainzSection, listenBrainzStatusProvider;
import '../features/local_library/ui/download_location_section.dart';
import '../features/play_cache/ui/play_cache_section.dart';
import '../features/auto_download/ui/auto_download_section.dart';
import '../features/auto_download/logic/auto_download_providers.dart' show autoDownloadSettingsProvider;
import '../lyrics/ui/lyrics_sources_section.dart';
import '../features/local_library/ui/local_music_section.dart';
import '../features/social/ui/social_settings_section.dart';
import '../features/updates/logic/update_providers.dart' show updateCheckProvider, updatesSupported;
import '../features/updates/ui/updates_screen.dart';
import '../features/status/ui/status_screen.dart';
import '../features/month/ui/month_screen.dart';
import '../features/taste/ui/taste_screen.dart';
import '../widgets/app_scaffold.dart' show navigateInApp;
import '../widgets/last_error_row.dart';
import '../widgets/notification_settings_section.dart';
import '../widgets/windows_settings_section.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../features/pairing/ui/sign_in_another_device_screen.dart';
import '../utils/web_env.dart' show reloadPage;
import '../widgets/mascot/microduck_mesh.dart' show MicroduckSkin;
import '../widgets/mascot/microduck_pose.dart' show defaultMicroduckName;
import '../services/playback_tuning.dart';
import '../services/transcoding_service.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/ui/action_sheet.dart';
import '../widgets/ui/controls.dart' show NaviSearchField;
import '../widgets/ui/grouped_list.dart';
import '../widgets/ui/large_title_page.dart';
import 'settings_folders.dart';

/// The folders that have something to show here, in order, each with its
/// sections as built by the screen. A section the platform doesn't offer is
/// absent from [items]; a folder left empty is left out.
@visibleForTesting
Map<SettingsFolder, List<Widget>> groupSettings(Map<SettingsSection, Widget> items) => {
      for (final f in SettingsFolder.values)
        if (f.sections.any(items.containsKey)) f: [for (final s in f.sections) ?items[s]],
    };

bool _hit(String text, List<String> terms) {
  final low = text.toLowerCase();
  return terms.every(low.contains);
}

String _rowText(Widget w) => switch (w) {
      GroupedRow r => '${r.title} ${r.subtitle ?? ''} ${r.value ?? ''}',
      GroupedSwitchRow r => '${r.title} ${r.subtitle ?? ''}',
      GroupedTextFieldRow r => r.title,
      _ => '',
    };

/// The sections of [groups] that match [query], every word of it, by folder
/// name, section heading, row title/subtitle, or a section's keywords. A
/// section built here shrinks to its matching rows; a folder named in the
/// query keeps all of its sections.
@visibleForTesting
Map<SettingsFolder, List<Widget>> searchSettings(Map<SettingsSection, Widget> items, String query) {
  final terms = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final out = <SettingsFolder, List<Widget>>{};
  for (final f in SettingsFolder.values) {
    final kept = <Widget>[];
    for (final id in f.sections) {
      final w = items[id];
      if (w == null) continue;
      if (_hit(f.title, terms)) {
        kept.add(w);
      } else if (w is GroupedSection) {
        final rows = w.children.where((r) => _hit(_rowText(r), terms)).toList();
        if (_hit(w.header ?? '', terms)) {
          kept.add(w);
        } else if (rows.isNotEmpty) {
          kept.add(GroupedSection(header: w.header, children: rows));
        }
      } else if (_hit(id.words, terms)) {
        kept.add(w);
      }
    }
    if (kept.isNotEmpty) out[f] = kept;
  }
  return out;
}

/// The folders whose name, or any section's words, match [query]: what the
/// phone and TV hub lists under the search box (each opens its folder).
@visibleForTesting
List<SettingsFolder> searchFolders(String query) {
  final terms = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  return [
    for (final f in SettingsFolder.values)
      if (_hit(f.title, terms) || f.sections.any((id) => _hit(id.words, terms))) f,
  ];
}

final _appVersionProvider =FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// iOS Settings layout: inset groups, coloured icon squares, choices in
/// sheets. Switches apply at once; account and sync fields apply on Save.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Phone and TV: the folder's page; null is the top level, the list of
  /// folders. Windows shows every folder in its sidebar and starts on this one.
  final SettingsFolder? folder;
  const SettingsScreen({super.key, this.folder});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Windows: the folder showing on the right.
  late SettingsFolder _folder = widget.folder ?? SettingsFolder.playback;

  /// The settings search box; empty shows every section in order.
  final _query = TextEditingController();

  late final SettingsState _initial = ref.read(settingsProvider);
  late final _user = TextEditingController(text: _initial.username);
  late final _pass = TextEditingController(text: _initial.password);
  late final _duckName = TextEditingController(text: _initial.microduckName);

  // Windows saves the account as it changes (and offers Undo); the phone has its Save button.
  Timer? _saveTimer;
  late String _savedUser = _initial.username;
  late String _savedPass = _initial.password;
  bool _undoing = false;

  // Preferences held by services rather than SettingsState.
  bool _imageCache = true;
  bool _musicCache = true;
  bool _bpmCache = true;
  bool _transcoding = false;
  bool _smartSwitch = false;
  int _wifiBitrate = TranscodeBitrate.original;
  int _mobileBitrate = TranscodeBitrate.kbps192;
  String _format = TranscodeFormat.mp3;
  bool _recommendations = true;

  /// Which long-running action is in progress, so its row shows a spinner.
  String? _busy;

  @override
  void initState() {
    super.initState();
    _duckName.addListener(
      () => ref.read(settingsProvider.notifier).setMicroduckName(_duckName.text),
    );
    _loadServicePrefs();
    if (PlatformUtils.isDesktop && !kIsWeb) {
      _user.addListener(_scheduleAutoSave);
      _pass.addListener(_scheduleAutoSave);
    }
  }

  Future<void> _loadServicePrefs() async {
    final cache = ref.read(cacheSettingsProvider);
    final tx = ref.read(transcodingProvider);
    final rec = ref.read(recommendationProvider);
    if (!mounted) return;
    setState(() {
      _imageCache = cache.getImageCacheEnabled();
      _musicCache = cache.getMusicCacheEnabled();
      _bpmCache = cache.getBpmCacheEnabled();
      _transcoding = tx.enabled;
      _smartSwitch = tx.smartEnabled;
      _wifiBitrate = tx.wifiBitrate;
      _mobileBitrate = tx.mobileBitrate;
      _format = tx.format;
      _recommendations = rec.enabled;
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    for (final c in [_user, _pass, _duckName, _query]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _scheduleAutoSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 900), _autoSave);
  }

  Future<void> _autoSave() async {
    final user = _user.text.trim(), pass = _pass.text;
    if (user == _savedUser && pass == _savedPass) return;
    final prevUser = _savedUser, prevPass = _savedPass;
    final server = ref.read(settingsProvider).serverUrl;
    await ref.read(settingsProvider.notifier).saveSettings(server, user, pass);
    ref.read(playerProvider.notifier).refreshShuffleUrl();
    _savedUser = user;
    _savedPass = pass;
    if (!mounted || _undoing) return;
    showToastWithAction(context, 'Account saved', actionLabel: 'Undo', onAction: () async {
      _undoing = true;
      _user.text = prevUser;
      _pass.text = prevPass;
      await ref.read(settingsProvider.notifier).saveSettings(server, prevUser, prevPass);
      ref.read(playerProvider.notifier).refreshShuffleUrl();
      _savedUser = prevUser;
      _savedPass = prevPass;
      _undoing = false;
    });
  }

  Future<void> _save() async {
    final settings = ref.read(settingsProvider);
    // Browser: the account isn't editable here (sign out and in instead).
    if (!kIsWeb) {
      await ref.read(settingsProvider.notifier).saveSettings(settings.serverUrl, _user.text.trim(), _pass.text);
      ref.read(playerProvider.notifier).refreshShuffleUrl();
    }
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    showToast(context, 'Settings saved');
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// Runs [action] with a spinner on the row named [key] and a toast after.
  Future<void> _run(String key, Future<String> Function() action, String failure) async {
    setState(() => _busy = key);
    try {
      final message = await action();
      if (mounted) showToast(context, message);
    } catch (_) {
      if (mounted) showToast(context, failure);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _deleteAllDownloads(int count, String size) async {
    final ok = await confirmDestructive(
      context,
      title: 'Delete all downloads?',
      message: '$count songs ($size) will be removed from this device. '
          'They stay in your library and can be downloaded again.',
      confirmLabel: 'Delete All',
    );
    if (!ok) return;
    await _run('downloads', () async {
      await ref.read(downloadStateProvider.notifier).deleteAll();
      return 'Downloads deleted';
    }, 'Couldn’t delete downloads. Try again.');
  }

  Future<void> _clearRecommendations() async {
    final ok = await confirmDestructive(
      context,
      title: 'Clear recommendation data?',
      message: 'Smart Shuffle forgets what it learned about your listening. This can’t be undone.',
      confirmLabel: 'Clear',
    );
    if (!ok) return;
    await _run('recs', () async {
      await ref.read(recommendationProvider).clearData();
      return 'Recommendation data cleared';
    }, 'Couldn’t clear the data. Try again.');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  Widget? _spinner(String key) => _busy != key
      ? null
      : PlatformUtils.isDesktop
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: 'Working'))
          : const CupertinoActivityIndicator();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final host = Uri.tryParse(s.serverUrl)?.host ?? s.serverUrl;
    final downloads = ref.watch(downloadStateProvider.select((m) => m.length));
    final bytes = ref.watch(downloadedBytesProvider).asData?.value;
    final size = bytes == null ? '…' : ref.read(offlineServiceProvider).formatSize(bytes);
    final learned = ref.read(recommendationProvider).profiles.length;
    final version = ref.watch(_appVersionProvider).asData?.value ?? '';
    final lastError = ref.watch(lastErrorProvider).asData?.value;
    final autoplay = ref.watch(playerProvider.select((p) => p.autoplayMode));

    // The sections in order; the markers name the categories the desktop's left
    // list picks between (a phone just scrolls past them).
    final items = <SettingsSection, Widget>{
          if (kIsWeb)
            SettingsSection.account:
            // Browser: no password is kept, so there is nothing to edit here;
            // signing out forgets the session token.
            GroupedSection(
              header: 'Account',
              footer: 'This browser keeps a sign-in token, never your password.',
              children: [
                GroupedRow(
                  title: 'Server',
                  icon: NaviGlyph.cloud,
                  value: host.isEmpty ? 'Not connected' : host,
                ),
                GroupedRow(title: 'Username', icon: NaviGlyph.person, value: s.username),
                GroupedRow(
                  title: 'Sign Out',
                  destructive: true,
                  onTap: () async {
                    await ref.read(playerProvider.notifier).stop();
                    notifier.signOutWeb();
                    // A fresh page: Jam polling, the session socket and every
                    // cached provider of the old account go with it.
                    reloadPage();
                  },
                ),
              ],
            )
          else
          SettingsSection.account: GroupedSection(
            header: 'Account',
            footer: PlatformUtils.isDesktop ? 'Changes are saved as you type.' : 'Changes to your account apply when you tap Save.',
            children: [
              GroupedRow(
                title: 'Server',
                icon: NaviGlyph.cloud,
                value: host.isEmpty ? 'Not connected' : host,
              ),
              GroupedTextFieldRow(
                title: 'Username',
                controller: _user,
                placeholder: 'Required',
                icon: NaviGlyph.person,
              ),
              GroupedTextFieldRow(
                title: 'Password',
                controller: _pass,
                placeholder: 'Required',
                obscure: true,
                icon: NaviGlyph.lock,
              ),
              GroupedSwitchRow(
                title: 'Allow HTTP',
                subtitle: 'Connects without encryption. Use only on your home network.',
                icon: NaviGlyph.unlock,
                value: s.allowHttp,
                onChanged: notifier.setAllowHttp,
              ),
              GroupedRow(
                title: 'Sign in another device',
                subtitle: 'Send your login to a TV with a code or QR.',
                icon: NaviGlyph.link,
                onTap: () => navigateInApp(context, const SignInAnotherDeviceScreen(), title: 'Sign in another device'),
              ),
              GroupedRow(
                title: 'Who’s listening?',
                subtitle: 'Switch between people who use this device, or stop counting a session.',
                icon: NaviGlyph.group,
                onTap: () => navigateInApp(context, const ProfilePickerScreen(), title: 'Who’s listening?'),
              ),
            ],
          ),
          SettingsSection.look: GroupedSection(
            header: 'Look & motion',
            children: [
              GroupedSwitchRow(
                title: 'Living Artwork',
                subtitle: 'The Now Playing background moves with the music. Turn off to save battery.',
                icon: NaviGlyph.signal,
                value: s.fluidBgEnabled,
                onChanged: notifier.setFluidBgEnabled,
              ),
              GroupedRow(
                title: 'Motion',
                icon: NaviGlyph.signal,
                value: s.motionLevel.label,
                onTap: () async {
                  final v = await showChoiceSheet<MotionLevel>(
                    context,
                    title: 'Motion',
                    options: MotionLevel.values,
                    selected: s.motionLevel,
                    label: (m) => m.label,
                    detail: (m) => m.summary,
                  );
                  if (v != null) notifier.setMotionLevel(v);
                },
              ),
            ],
          ),
          SettingsSection.mascot: GroupedSection(
            header: 'Mascot',
            footer: 'A little robot walks along the mini player, dances to the music on '
                'Now Playing, and naps after midnight. Tap it to make it hop.',
            children: [
              GroupedSwitchRow(
                title: 'Microduck',
                icon: NaviGlyph.note,
                value: s.microduckEnabled,
                onChanged: notifier.setMicroduckEnabled,
              ),
              if (s.microduckEnabled)
                GroupedTextFieldRow(
                  title: 'Name',
                  controller: _duckName,
                  placeholder: defaultMicroduckName,
                ),
              if (s.microduckEnabled)
                GroupedSwitchRow(
                  title: 'Microduck talks',
                  subtitle: 'Now and then it remarks on the song in a small speech bubble.',
                  icon: NaviGlyph.note,
                  value: s.microduckTalks,
                  onChanged: notifier.setMicroduckTalks,
                ),
              if (s.microduckEnabled)
                GroupedRow(
                  title: 'Microduck colour',
                  value: s.microduckSkin.label,
                  onTap: () async {
                    final v = await showChoiceSheet<MicroduckSkin>(
                      context,
                      title: 'Microduck colour',
                      options: MicroduckSkin.values,
                      selected: s.microduckSkin,
                      label: (m) => m.label,
                    );
                    if (v != null) notifier.setMicroduckSkin(v);
                  },
                ),
            ],
          ),
          SettingsSection.audioQuality: GroupedSection(
            header: 'Audio Quality',
            footer: _transcoding
                ? 'Lower bitrates use less data. Original streams the file exactly as stored.'
                : 'Songs stream exactly as stored on your server, including lossless files.',
            children: [
              GroupedSwitchRow(
                title: 'Convert While Streaming',
                icon: NaviGlyph.aiShuffle,
                value: _transcoding,
                onChanged: (v) {
                  setState(() => _transcoding = v);
                  ref.read(transcodingProvider).setEnabled(v);
                },
              ),
              if (_transcoding) ...[
                _bitrateRow('Wi-Fi Quality', NaviGlyph.wifi, _wifiBitrate, (v) {
                  setState(() => _wifiBitrate = v);
                  ref.read(transcodingProvider).setWifiBitrate(v);
                }),
                _bitrateRow('Cellular Quality', NaviGlyph.radio, _mobileBitrate, (v) {
                  setState(() => _mobileBitrate = v);
                  ref.read(transcodingProvider).setMobileBitrate(v);
                }),
                GroupedRow(
                  title: 'Format',
                  icon: NaviGlyph.doc,
                  value: TranscodeFormat.getLabel(_format),
                  onTap: () async {
                    final v = await showChoiceSheet<String>(
                      context,
                      title: 'Format',
                      options: TranscodeFormat.options,
                      selected: _format,
                      label: TranscodeFormat.getLabel,
                    );
                    if (v == null) return;
                    setState(() => _format = v);
                    ref.read(transcodingProvider).setFormat(v);
                  },
                ),
                GroupedSwitchRow(
                  title: 'Switch Automatically',
                  subtitle: 'Uses the Wi-Fi or cellular quality to match your connection.',
                  icon: NaviGlyph.swap,
                  value: _smartSwitch,
                  onChanged: (v) {
                    setState(() => _smartSwitch = v);
                    ref.read(transcodingProvider).setSmartEnabled(v);
                  },
                ),
              ],
            ],
          ),
          SettingsSection.playback: GroupedSection(
            header: 'Playback',
            children: [
              GroupedSwitchRow(
                title: 'Autoplay',
                subtitle: 'Keeps the music going with similar songs when the queue ends.',
                icon: NaviGlyph.aiShuffle,
                value: autoplay,
                onChanged: (_) => ref.read(playerProvider.notifier).toggleAutoplay(),
              ),
              GroupedRow(
                title: 'Volume Normalisation',
                icon: NaviGlyph.speaker,
                value: s.replayGainMode.label,
                onTap: () async {
                  final v = await showChoiceSheet<ReplayGainMode>(
                    context,
                    title: 'Volume Normalisation',
                    options: ReplayGainMode.values,
                    selected: s.replayGainMode,
                    label: (m) => m.label,
                    detail: (m) => m.summary,
                  );
                  if (v != null) notifier.setReplayGainMode(v);
                },
              ),
              GroupedRow(
                title: 'Crossfade',
                icon: NaviGlyph.aiShuffle,
                value: crossfadeLabel(s.crossfadeSeconds),
                onTap: () async {
                  final v = await showChoiceSheet<int>(
                    context,
                    title: 'Crossfade',
                    options: [for (var i = 0; i <= kMaxCrossfadeSeconds; i++) i],
                    selected: s.crossfadeSeconds,
                    label: crossfadeLabel,
                    detail: (n) => n == 0
                        ? 'Songs play gapless.'
                        : 'Albums that play in order stay gapless.',
                  );
                  if (v != null) notifier.setCrossfadeSeconds(v);
                },
              ),
              GroupedRow(
                title: 'Shuffle Style',
                icon: NaviGlyph.shuffle,
                value: s.shuffleAlgorithm.label,
                onTap: () async {
                  final v = await showChoiceSheet<ShuffleAlgorithm>(
                    context,
                    title: 'Shuffle Style',
                    options: ShuffleAlgorithm.values,
                    selected: s.shuffleAlgorithm,
                    label: (a) => a.label,
                    detail: (a) => a.summary,
                  );
                  if (v != null) notifier.setShuffleAlgorithm(v);
                },
              ),
              if (s.shuffleAlgorithm.usesGrouping)
                GroupedRow(
                  title: 'Spread Songs By',
                  icon: NaviGlyph.grid,
                  value: s.shufflePreference.label,
                  onTap: () async {
                    final v = await showChoiceSheet<ShufflePreference>(
                      context,
                      title: 'Spread Songs By',
                      options: ShufflePreference.values,
                      selected: s.shufflePreference,
                      label: (p) => p.label,
                    );
                    if (v != null) notifier.setShufflePreference(v);
                  },
                ),
            ],
          ),
          SettingsSection.lyrics: const LyricsSourcesSection(),
          SettingsSection.storage: GroupedSection(
            header: 'Storage',
            children: [
              if (PlatformUtils.supportsOfflineFiles)
                GroupedRow(
                  title: 'Downloaded Songs',
                  icon: NaviGlyph.downloadCircle,
                  value: downloads == 0 ? 'None' : '$downloads · $size',
                ),
              GroupedSwitchRow(
                title: 'Cache Artwork',
                icon: NaviGlyph.photo,
                value: _imageCache,
                onChanged: (v) {
                  setState(() => _imageCache = v);
                  ref.read(cacheSettingsNotifierProvider.notifier).setImageCacheEnabled(v);
                },
              ),
              if (PlatformUtils.supportsOfflineFiles) // the browser caches streams itself
                GroupedSwitchRow(
                  title: 'Cache Music',
                  subtitle: 'Keeps recently played songs for instant replay.',
                  icon: NaviGlyph.note,
                  value: _musicCache,
                  onChanged: (v) {
                    setState(() => _musicCache = v);
                    ref.read(cacheSettingsNotifierProvider.notifier).setMusicCacheEnabled(v);
                  },
                ),
              GroupedSwitchRow(
                title: 'Cache Tempo',
                subtitle: 'Measures song tempo ahead of time so Smart Shuffle starts faster.',
                icon: NaviGlyph.metronome,
                value: _bpmCache,
                onChanged: (v) {
                  setState(() => _bpmCache = v);
                  ref.read(cacheSettingsNotifierProvider.notifier).setBpmCacheEnabled(v);
                },
              ),
            ],
          ),
          if (PlatformUtils.supportsOfflineFiles) SettingsSection.playCache: const PlayCacheSection(),
          if (PlatformUtils.supportsOfflineFiles) SettingsSection.autoDownload: const AutoDownloadSection(),
          if (PlatformUtils.supportsOfflineFiles) SettingsSection.downloadLocation: const DownloadLocationSection(),
          if (PlatformUtils.supportsOfflineFiles) SettingsSection.localMusic: const LocalMusicSection(),
          if (downloads > 0 && PlatformUtils.supportsOfflineFiles)
            SettingsSection.deleteDownloads: GroupedSection(children: [
              GroupedRow(
                title: 'Delete All Downloads',
                destructive: true,
                trailing: _spinner('downloads'),
                onTap: _busy == null ? () => _deleteAllDownloads(downloads, size) : null,
              ),
            ]),
          SettingsSection.social: const SocialSettingsSection(),
          SettingsSection.smartShuffle: GroupedSection(
            header: 'Smart Shuffle',
            footer: learned == 0
                ? 'Recommendations improve as you listen.'
                : 'Learned from $learned songs you’ve played.',
            children: [
              GroupedSwitchRow(
                title: 'Recommendations',
                icon: NaviGlyph.smart,
                value: _recommendations,
                onChanged: (v) {
                  setState(() => _recommendations = v);
                  ref.read(recommendationProvider).setEnabled(v);
                },
              ),
            ],
          ),
          SettingsSection.flowLanguages: const FlowSettingsSection(),
          SettingsSection.tasteMonth: GroupedSection(
            footer: 'Songs, artists and composers you never want recommended.',
            children: [
              GroupedRow(
                title: 'Taste',
                subtitle: 'Never recommend',
                onTap: () => navigateInApp(context, const TasteScreen()),
              ),
              GroupedRow(
                title: 'Your Month',
                subtitle: 'Top songs, artists and minutes',
                onTap: () => navigateInApp(context, const MonthScreen()),
              ),
            ],
          ),
          SettingsSection.clearRecommendations: GroupedSection(children: [
            GroupedRow(
              title: 'Clear Recommendation Data',
              destructive: true,
              trailing: _spinner('recs'),
              onTap: _busy == null ? _clearRecommendations : null,
            ),
          ]),
          SettingsSection.scrobbling: const ListenBrainzSection(),
          SettingsSection.weeklyExploration: const WeeklyExplorationSettings(),
          SettingsSection.albumOvernight: const AlbumOvernightSettings(),
          SettingsSection.importData: const ExportifyImportSection(),
          SettingsSection.listeningData: GroupedSection(
            header: 'Your Listening Data',
            children: [
              if (PlatformUtils.supportsOfflineFiles) // writes files to Downloads
              GroupedRow(
                title: 'Export as CSV',
                subtitle: 'Saves your play history and song data to Downloads.',
                icon: NaviGlyph.download,
                trailing: _spinner('export'),
                onTap: _busy == null
                    ? () => _run('export', () async {
                          final paths = await ref.read(listenerCollectorProvider).exportCsvToDownloads();
                          return 'Exported ${paths.length} files to Downloads';
                        }, 'Export failed. Check free storage and try again.')
                    : null,
              ),
              GroupedRow(
                title: 'Remove Skipped Plays',
                subtitle: 'Deletes plays that lasted under a second.',
                icon: NaviGlyph.trash,
                onTap: () => _run('purge', () async {
                  final n = await ref.read(listenerCollectorProvider).purgeNoiseEvents();
                  return n == 0 ? 'Nothing to remove' : 'Removed $n skipped plays';
                }, 'Couldn’t clean up. Try again.'),
              ),
            ],
          ),
          SettingsSection.notifications: const NotificationSettingsSection(),
          SettingsSection.windows: const WindowsSettingsSection(),
          SettingsSection.about: GroupedSection(
            header: 'About',
            children: [
              GroupedRow(title: 'Version', value: version),
              GroupedRow(
                title: 'Connection & status',
                icon: NaviGlyph.signal,
                onTap: () => navigateInApp(context, const StatusScreen()),
              ),
              if (updatesSupported)
                GroupedRow(
                  title: 'Updates',
                  icon: NaviGlyph.download,
                  value: ref.watch(updateCheckProvider).asData?.value?.available == true ? 'Available' : null,
                  onTap: () => navigateInApp(context, const UpdatesScreen()),
                ),
              if (lastError != null)
                LastErrorRow(
                  text: lastError,
                  onCleared: () => ref.invalidate(lastErrorProvider),
                ),
            ],
          ),
    };

    final groups = groupSettings(items);
    final query = _query.text;
    final results = query.trim().isEmpty || !PlatformUtils.isDesktop ? null : searchSettings(items, query);
    final search = NaviSearchField(
      controller: _query,
      placeholder: 'Search settings',
      onChanged: (_) => setState(() {}),
      voice: false,
    );

    if (PlatformUtils.isDesktop) return _desktopLayout(context, groups, results, search);
    final folder = widget.folder;
    if (folder == null) return _hub(context, groups.keys.toList(), search);
    return LargeTitlePage(
      title: folder.title,
      // The account is the one folder that holds fields to save.
      trailing: folder == SettingsFolder.account
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _save,
              child: Text('Save', style: t.headline.copyWith(color: t.accent)),
            )
          : null,
      slivers: [
        SliverList.list(children: [
          const SizedBox(height: Space.sm),
          ...?groups[folder],
        ]),
      ],
    );
  }

  /// Phone and TV top level: the folders, most-used first, each with a line
  /// on where it stands now. The search box lists the folders that match.
  Widget _hub(BuildContext context, List<SettingsFolder> folders, Widget search) {
    final query = _query.text.trim();
    final shown = query.isEmpty ? folders : searchFolders(query).where(folders.contains).toList();
    final t = ThemeTokens.of(context);
    return LargeTitlePage(
      title: 'Settings',
      slivers: [
        SliverList.list(children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: Space.lg), child: search),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text('No settings match “$query”.', style: t.subheadline.copyWith(color: t.textSecondary)),
            )
          else
            GroupedSection(
              children: [
                for (final f in shown)
                  GroupedRow(
                    title: f.title,
                    subtitle: _summary(f),
                    icon: f.icon,
                    onTap: () => navigateInApp(context, SettingsScreen(folder: f), title: f.title),
                  ),
              ],
            ),
        ]),
      ],
    );
  }

  /// One line on a folder's current state, for the top level.
  String _summary(SettingsFolder f) {
    final s = ref.watch(settingsProvider);
    switch (f) {
      case SettingsFolder.playback:
        final autoplay = ref.watch(playerProvider.select((p) => p.autoplayMode));
        return '${autoplay ? 'Autoplay on' : 'Autoplay off'} · '
            '${s.crossfadeSeconds == 0 ? 'Gapless' : 'Crossfade ${crossfadeLabel(s.crossfadeSeconds)}'}';
      case SettingsFolder.downloads:
        if (!PlatformUtils.supportsOfflineFiles) return 'Artwork and tempo cache';
        final n = ref.watch(downloadStateProvider.select((m) => m.length));
        final bytes = ref.watch(downloadedBytesProvider).asData?.value;
        final auto = ref.watch(autoDownloadSettingsProvider.select((a) => a.enabled));
        final held = n == 0
            ? 'No downloads'
            : '$n ${n == 1 ? 'song' : 'songs'} · ${bytes == null ? '…' : ref.read(offlineServiceProvider).formatSize(bytes)}';
        return auto ? '$held · Auto on' : held;
      case SettingsFolder.flow:
        final rec = ref.read(recommendationProvider);
        return rec.enabled ? 'Recommendations on · ${rec.profiles.length} songs learned' : 'Recommendations off';
      case SettingsFolder.replay:
        final linked = ref.watch(listenBrainzStatusProvider).asData?.value.linked;
        return linked == true ? 'ListenBrainz linked' : 'Scrobbling and history import';
      case SettingsFolder.appearance:
        return 'Motion ${s.motionLevel.label} · Microduck ${s.microduckEnabled ? 'on' : 'off'}';
      case SettingsFolder.social:
        return 'Friends, sharing and alerts';
      case SettingsFolder.notifications:
        return PlatformUtils.isWindows ? 'Alerts, tray and startup' : 'Alerts';
      case SettingsFolder.account:
        final host = Uri.tryParse(s.serverUrl)?.host ?? s.serverUrl;
        return [if (s.username.isNotEmpty) s.username, host.isEmpty ? 'Not connected' : host].join(' · ');
      case SettingsFolder.about:
        final version = ref.watch(_appVersionProvider).asData?.value ?? '';
        return version.isEmpty ? 'Status and updates' : 'Version $version';
    }
  }

  /// The matching sections, in folder order; a note when nothing matches.
  List<Widget> _resultWidgets(Map<SettingsFolder, List<Widget>> results) {
    final all = [for (final s in results.values) ...s];
    if (all.isNotEmpty) return all;
    final t = ThemeTokens.of(context);
    return [
      Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Text('No settings match “${_query.text.trim()}”.', style: t.subheadline.copyWith(color: t.textSecondary)),
      ),
    ];
  }

  /// Windows: categories down the left, the chosen one's settings on the right.
  Widget _desktopLayout(BuildContext context, Map<SettingsFolder, List<Widget>> groups, Map<SettingsFolder, List<Widget>>? results, Widget search) {
    final t = ThemeTokens.of(context);
    final names = groups.keys.toList();
    final selected = names.contains(_folder) ? _folder : names.first;
    // One group: the categories and their form, centred in the content area so it
    // never hugs the left edge with dead space to its right.
    return Scaffold(
      backgroundColor: Colors.transparent, // the window's one ground shows through
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 232 + 0.5 + 720 + 2 * pageGutter(context)),
          child: Row(
        children: [
          SizedBox(
            width: 232,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.xxl, Space.md, Space.lg),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.sm, 0, Space.sm, Space.lg),
                  child: SizedBox(height: _titleBox, child: Align(alignment: Alignment.bottomLeft, child: Text('Settings', style: t.largeTitle))),
                ),
                Padding(padding: const EdgeInsets.only(bottom: Space.md), child: search),
                for (final n in names)
                  _SettingsNavRow(
                    label: n.title,
                    selected: results == null && n == selected,
                    onTap: () => setState(() {
                      _query.clear();
                      _folder = n;
                    }),
                  ),
              ],
            ),
          ),
          Container(width: 0.5, color: t.separatorOpaque),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final sections = results == null ? groups[selected]! : _resultWidgets(results);
                final heading = results == null ? selected.title : 'Search results';
                // A form reads best about 720 px wide; sections of two columns would
                // split a short list into halves nobody scans. So the pane stays one
                // column, 48 px after the categories (the page's 24 gutter twice), so the
                // nav and its pane read as one unit at any window width.
                return ListView(
                  // Same top as the "Settings" title beside it, so the two read as one page.
                  padding: EdgeInsets.only(top: Space.xxl, bottom: Space.xxxl, left: pageGutter(context)),
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(pageGutter(context), 0, pageGutter(context), Space.sm),
                      child: SizedBox(height: _titleBox, child: Align(alignment: Alignment.bottomLeft, child: Text(heading, style: t.title1))),
                    ),
                    SectionHeaderScope(
                      pageTitle: heading,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: sections),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  /// Both headings sit bottom-aligned in a box this tall, so their baselines match.
  static const double _titleBox = 44;

  Widget _bitrateRow(String title, NaviGlyph icon, int current, ValueChanged<int> onPick) =>
      GroupedRow(
        title: title,
        icon: icon,
        value: TranscodeBitrate.getLabel(current),
        onTap: () async {
          final v = await showChoiceSheet<int>(
            context,
            title: title,
            options: TranscodeBitrate.options,
            selected: current,
            label: TranscodeBitrate.getLabel,
          );
          if (v != null) onPick(v);
        },
      );
}

class _SettingsNavRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SettingsNavRow({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: NaviFocusable(
        radius: 6,
        hoverTint: !selected,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: Space.md),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: selected ? t.bgOverlay : Colors.transparent, borderRadius: BorderRadius.circular(6)),
          child: Text(
            label,
            style: t.subheadline.copyWith(
              color: selected ? t.textPrimary : t.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
