import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/theme.dart';
import '../widgets/last_error_row.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../services/playback_tuning.dart';
import '../services/transcoding_service.dart';
import '../widgets/ui/action_sheet.dart';
import '../widgets/ui/grouped_list.dart';
import '../widgets/ui/ion.dart';
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
  late final SettingsState _initial = ref.read(settingsProvider);
  late final _user = TextEditingController(text: _initial.username);
  late final _pass = TextEditingController(text: _initial.password);

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
    _loadServicePrefs();
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
    for (final c in [_user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

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

  Widget? _spinner(String key) => _busy == key ? const CupertinoActivityIndicator() : null;

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

    return LargeTitlePage(
      title: 'Settings',
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _save,
        child: Text('Save', style: t.headline.copyWith(color: t.accent)),
      ),
      slivers: [
        SliverList.list(children: [
          const SizedBox(height: Space.sm),
          GroupedSection(
            header: 'Account',
            footer: 'Changes to your account apply when you tap Save.',
            children: [
              GroupedRow(
                title: 'Server',
                icon: CupertinoIcons.cloud,
                ion: Ion.globe,
                value: host.isEmpty ? 'Not connected' : host,
              ),
              GroupedTextFieldRow(
                title: 'Username',
                controller: _user,
                placeholder: 'Required',
                icon: CupertinoIcons.person_fill,
                ion: Ion.person,
              ),
              GroupedTextFieldRow(
                title: 'Password',
                controller: _pass,
                placeholder: 'Required',
                obscure: true,
                icon: CupertinoIcons.lock_fill,
                ion: Ion.lock,
              ),
              GroupedSwitchRow(
                title: 'Allow HTTP',
                subtitle: 'Connects without encryption. Use only on your home network.',
                icon: CupertinoIcons.lock_open,
                ion: Ion.unlock,
                value: s.allowHttp,
                onChanged: notifier.setAllowHttp,
              ),
            ],
          ),
          GroupedSection(
            header: 'Playback',
            children: [
              GroupedSwitchRow(
                title: 'Living Artwork',
                subtitle: 'The Now Playing background moves with the music. Turn off to save battery.',
                icon: CupertinoIcons.sparkles,
                ion: Ion.palette,
                value: s.fluidBgEnabled,
                onChanged: notifier.setFluidBgEnabled,
              ),
              GroupedRow(
                title: 'Volume Normalisation',
                icon: CupertinoIcons.speaker_2,
                ion: Ion.volumeHigh,
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
                icon: CupertinoIcons.waveform,
                ion: Ion.infinite,
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
                icon: CupertinoIcons.shuffle,
                ion: Ion.shuffle,
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
                  icon: CupertinoIcons.square_grid_2x2,
                  ion: Ion.options,
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
          GroupedSection(
            header: 'Audio Quality',
            footer: _transcoding
                ? 'Lower bitrates use less data. Original streams the file exactly as stored.'
                : 'Songs stream exactly as stored on your server, including lossless files.',
            children: [
              GroupedSwitchRow(
                title: 'Convert While Streaming',
                icon: CupertinoIcons.waveform,
                ion: Ion.convert,
                value: _transcoding,
                onChanged: (v) {
                  setState(() => _transcoding = v);
                  ref.read(transcodingProvider).setEnabled(v);
                },
              ),
              if (_transcoding) ...[
                _bitrateRow('Wi-Fi Quality', CupertinoIcons.wifi, Ion.wifi, _wifiBitrate, (v) {
                  setState(() => _wifiBitrate = v);
                  ref.read(transcodingProvider).setWifiBitrate(v);
                }),
                _bitrateRow('Cellular Quality', CupertinoIcons.antenna_radiowaves_left_right, Ion.cellular, _mobileBitrate, (v) {
                  setState(() => _mobileBitrate = v);
                  ref.read(transcodingProvider).setMobileBitrate(v);
                }),
                GroupedRow(
                  title: 'Format',
                  icon: CupertinoIcons.doc_text,
                  ion: Ion.document,
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
                  icon: CupertinoIcons.arrow_2_squarepath,
                  ion: Ion.sync,
                  value: _smartSwitch,
                  onChanged: (v) {
                    setState(() => _smartSwitch = v);
                    ref.read(transcodingProvider).setSmartEnabled(v);
                  },
                ),
              ],
            ],
          ),
          GroupedSection(
            header: 'Downloads & Storage',
            children: [
              GroupedRow(
                title: 'Downloaded Songs',
                icon: CupertinoIcons.arrow_down_circle,
                ion: Ion.download,
                value: downloads == 0 ? 'None' : '$downloads · $size',
              ),
              GroupedSwitchRow(
                title: 'Cache Artwork',
                icon: CupertinoIcons.photo,
                ion: Ion.image,
                value: _imageCache,
                onChanged: (v) {
                  setState(() => _imageCache = v);
                  ref.read(cacheSettingsNotifierProvider.notifier).setImageCacheEnabled(v);
                },
              ),
              GroupedSwitchRow(
                title: 'Cache Music',
                subtitle: 'Keeps recently played songs for instant replay.',
                icon: CupertinoIcons.music_note_2,
                ion: Ion.music,
                value: _musicCache,
                onChanged: (v) {
                  setState(() => _musicCache = v);
                  ref.read(cacheSettingsNotifierProvider.notifier).setMusicCacheEnabled(v);
                },
              ),
              GroupedSwitchRow(
                title: 'Cache Tempo',
                subtitle: 'Measures song tempo ahead of time so Smart Shuffle starts faster.',
                icon: CupertinoIcons.metronome,
                ion: Ion.timer,
                value: _bpmCache,
                onChanged: (v) {
                  setState(() => _bpmCache = v);
                  ref.read(cacheSettingsNotifierProvider.notifier).setBpmCacheEnabled(v);
                },
              ),
            ],
          ),
          if (downloads > 0)
            GroupedSection(children: [
              GroupedRow(
                title: 'Delete All Downloads',
                destructive: true,
                trailing: _spinner('downloads'),
                onTap: _busy == null ? () => _deleteAllDownloads(downloads, size) : null,
              ),
            ]),
          GroupedSection(
            header: 'Smart Shuffle',
            footer: learned == 0
                ? 'Recommendations improve as you listen.'
                : 'Learned from $learned songs you’ve played.',
            children: [
              GroupedSwitchRow(
                title: 'Recommendations',
                icon: CupertinoIcons.wand_stars,
                ion: Ion.sparkles,
                value: _recommendations,
                onChanged: (v) {
                  setState(() => _recommendations = v);
                  ref.read(recommendationProvider).setEnabled(v);
                },
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
          GroupedSection(
            header: 'Your Listening Data',
            children: [
              GroupedRow(
                title: 'Export as CSV',
                subtitle: 'Saves your play history and song data to Downloads.',
                icon: CupertinoIcons.square_arrow_down,
                ion: Ion.share,
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
                icon: CupertinoIcons.trash,
                ion: Ion.trash,
                onTap: () => _run('purge', () async {
                  final n = await ref.read(listenerCollectorProvider).purgeNoiseEvents();
                  return n == 0 ? 'Nothing to remove' : 'Removed $n skipped plays';
                }, 'Couldn’t clean up. Try again.'),
              ),
            ],
          ),
          GroupedSection(
            header: 'About',
            children: [
              GroupedRow(title: 'Version', value: version),
              if (lastError != null)
                LastErrorRow(
                  text: lastError,
                  onCleared: () => ref.invalidate(lastErrorProvider),
                ),
            ],
          ),
        ]),
      ],
    );
  }

  Widget _bitrateRow(String title, IconData icon, Ion ion, int current, ValueChanged<int> onPick) =>
      GroupedRow(
        title: title,
        icon: icon,
        ion: ion,
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
