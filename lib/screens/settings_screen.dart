import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator, Colors, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/motion.dart' show MotionLevel;
import '../core/theme.dart';
import '../core/focus/navi_focus.dart';
import '../utils/platform_utils.dart';
import '../features/flow/ui/flow_settings.dart';
import '../features/local_library/ui/download_location_section.dart';
import '../features/local_library/ui/local_music_section.dart';
import '../features/social/ui/social_settings_section.dart';
import '../features/updates/logic/update_providers.dart' show updateCheckProvider, updatesSupported;
import '../features/updates/ui/updates_screen.dart';
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
import '../widgets/mascot/microduck_mesh.dart' show MicroduckSkin;
import '../widgets/mascot/microduck_pose.dart' show defaultMicroduckName;
import '../services/playback_tuning.dart';
import '../services/transcoding_service.dart';
import '../widgets/art/navi_icons.dart';
import '../widgets/ui/action_sheet.dart';
import '../widgets/ui/grouped_list.dart';
import '../widgets/ui/large_title_page.dart';

final _appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// iOS Settings layout: inset groups, coloured icon squares, choices in
/// sheets. Switches apply at once; account and sync fields apply on Save.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Windows: the category showing on the right.
  String _category = 'Account';

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
    if (PlatformUtils.isDesktop) {
      _user.addListener(_scheduleAutoSave);
      _pass.addListener(_scheduleAutoSave);
    }
  }

  Future<void> _loadServicePrefs() async {
    final cache = ref.read(cacheSettingsProvider);
    await cache.initialize();
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
    for (final c in [_user, _pass, _duckName]) {
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
    await ref.read(settingsProvider.notifier).saveSettings(settings.serverUrl, _user.text.trim(), _pass.text);
    ref.read(playerProvider.notifier).refreshShuffleUrl();
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

    // The sections in order; the markers name the categories the desktop's left
    // list picks between (a phone just scrolls past them).
    final items = <Widget>[
          const SizedBox(height: Space.sm),
          const SettingsCategory('Account'),
          GroupedSection(
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
            ],
          ),
          const SettingsCategory('Mascot'),
          GroupedSection(
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
          const SettingsCategory('Playback'),
          GroupedSection(
            header: 'Playback',
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
          const SettingsCategory('Audio quality'),
          GroupedSection(
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
          const SettingsCategory('Downloads & storage'),
          GroupedSection(
            header: 'Downloads & Storage',
            children: [
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
          const DownloadLocationSection(),
          const LocalMusicSection(),
          if (downloads > 0)
            GroupedSection(children: [
              GroupedRow(
                title: 'Delete All Downloads',
                destructive: true,
                trailing: _spinner('downloads'),
                onTap: _busy == null ? () => _deleteAllDownloads(downloads, size) : null,
              ),
            ]),
          const SettingsCategory('Social'),
          const SocialSettingsSection(),
          const SettingsCategory('Smart Shuffle'),
          GroupedSection(
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
          const FlowSettingsSection(),
          GroupedSection(
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
          GroupedSection(children: [
            GroupedRow(
              title: 'Clear Recommendation Data',
              destructive: true,
              trailing: _spinner('recs'),
              onTap: _busy == null ? _clearRecommendations : null,
            ),
          ]),
          const SettingsCategory('Your data'),
          GroupedSection(
            header: 'Your Listening Data',
            children: [
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
          const NotificationSettingsSection(),
          const WindowsSettingsSection(),
          const SettingsCategory('About'),
          GroupedSection(
            header: 'About',
            children: [
              GroupedRow(title: 'Version', value: version),
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
    ];

    if (PlatformUtils.isDesktop) return _desktopLayout(context, items);
    return LargeTitlePage(
      title: 'Settings',
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _save,
        child: Text('Save', style: t.headline.copyWith(color: t.accent)),
      ),
      slivers: [SliverList.list(children: items)],
    );
  }

  /// Windows: categories down the left, the chosen one's settings on the right.
  Widget _desktopLayout(BuildContext context, List<Widget> items) {
    final t = ThemeTokens.of(context);
    final groups = <String, List<Widget>>{};
    String? current;
    for (final w in items) {
      if (w is SettingsCategory) {
        current = w.name;
        groups[current] = [];
      } else if (current != null) {
        groups[current]!.add(w);
      }
    }
    final names = groups.keys.toList();
    final selected = names.contains(_category) ? _category : names.first;
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
                for (final n in names)
                  _SettingsNavRow(label: n, selected: n == selected, onTap: () => setState(() => _category = n)),
              ],
            ),
          ),
          Container(width: 0.5, color: t.separatorOpaque),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final sections = groups[selected]!;
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
                      child: SizedBox(height: _titleBox, child: Align(alignment: Alignment.bottomLeft, child: Text(selected, style: t.title1))),
                    ),
                    SectionHeaderScope(
                      pageTitle: selected,
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

/// Marks where a category of settings begins in the list. Draws nothing: a
/// phone scrolls past it, the desktop uses it to split the page into the
/// categories listed on the left.
class SettingsCategory extends StatelessWidget {
  final String name;
  const SettingsCategory(this.name, {super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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
