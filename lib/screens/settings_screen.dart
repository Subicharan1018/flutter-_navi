import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/theme.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../services/replay_upload_service.dart';
import '../services/subsonic_service.dart';
import '../services/transcoding_service.dart';
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
  late final SettingsState _initial = ref.read(settingsProvider);
  late final _user = TextEditingController(text: _initial.username);
  late final _pass = TextEditingController(text: _initial.password);
  late final _uploadDir = TextEditingController(text: _initial.uploadDirectory);
  late final _davUrl = TextEditingController(text: _initial.webdavUrl);
  late final _davUser = TextEditingController(text: _initial.webdavUsername);
  late final _davPass = TextEditingController(text: _initial.webdavPassword);

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
    for (final c in [_user, _pass, _uploadDir, _davUrl, _davUser, _davPass]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final settings = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).saveSettings(
          settings.serverUrl,
          _user.text.trim(),
          _pass.text,
          webdavUrl: _davUrl.text.trim(),
          uploadDir: _uploadDir.text.trim(),
          webdavUser: _davUser.text.trim(),
          webdavPass: _davPass.text,
        );
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

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = picked?.files.single.path;
    if (path == null) return;
    await _run('upload', () async {
      final s = ref.read(settingsProvider);
      final uploadUrl = s.uploadApiUrl;
      await SubsonicService(
        serverUrl: s.serverUrl,
        username: _user.text.trim(),
        password: _pass.text,
        cache: ref.read(playlistCacheServiceProvider),
        customUploadUrl: uploadUrl.isEmpty ? null : uploadUrl,
        customUploadDir: _uploadDir.text.trim().isEmpty ? null : _uploadDir.text.trim(),
        webdavUsername: _davUser.text.trim(),
        webdavPassword: _davPass.text,
      ).uploadSong(File(path));
      return 'Uploaded ${picked!.files.single.name}';
    }, 'Upload failed. Check your connection and the upload folder, then try again.');
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
                value: host.isEmpty ? 'Not connected' : host,
              ),
              GroupedTextFieldRow(
                title: 'Username',
                controller: _user,
                placeholder: 'Required',
                icon: CupertinoIcons.person_fill,
              ),
              GroupedTextFieldRow(
                title: 'Password',
                controller: _pass,
                placeholder: 'Required',
                obscure: true,
                icon: CupertinoIcons.lock_fill,
              ),
              GroupedSwitchRow(
                title: 'Allow HTTP',
                subtitle: 'Connects without encryption. Use only on your home network.',
                icon: CupertinoIcons.lock_open,
                iconColor: t.warning,
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
                value: s.fluidBgEnabled,
                onChanged: notifier.setFluidBgEnabled,
              ),
              GroupedRow(
                title: 'Shuffle Style',
                icon: CupertinoIcons.shuffle,
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
                value: _transcoding,
                onChanged: (v) {
                  setState(() => _transcoding = v);
                  ref.read(transcodingProvider).setEnabled(v);
                },
              ),
              if (_transcoding) ...[
                _bitrateRow('Wi-Fi Quality', CupertinoIcons.wifi, _wifiBitrate, (v) {
                  setState(() => _wifiBitrate = v);
                  ref.read(transcodingProvider).setWifiBitrate(v);
                }),
                _bitrateRow('Cellular Quality', CupertinoIcons.antenna_radiowaves_left_right, _mobileBitrate, (v) {
                  setState(() => _mobileBitrate = v);
                  ref.read(transcodingProvider).setMobileBitrate(v);
                }),
                GroupedRow(
                  title: 'Format',
                  icon: CupertinoIcons.doc_text,
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
                value: downloads == 0 ? 'None' : '$downloads · $size',
              ),
              GroupedSwitchRow(
                title: 'Cache Artwork',
                icon: CupertinoIcons.photo,
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
                trailing: _spinner('export'),
                onTap: _busy == null
                    ? () => _run('export', () async {
                          final paths = await ref.read(listenerCollectorProvider).exportCsvToDownloads();
                          return 'Exported ${paths.length} files to Downloads';
                        }, 'Export failed. Check free storage and try again.')
                    : null,
              ),
              GroupedRow(
                title: 'Sync to Server',
                subtitle: 'Uploads your listening history for Replay and Smart Shuffle.',
                icon: CupertinoIcons.arrow_2_circlepath,
                trailing: _spinner('sync'),
                onTap: _busy == null
                    ? () => _run('sync', () async {
                          await ref.read(replayUploadServiceProvider).uploadData('manual');
                          return 'Listening data synced';
                        }, 'Sync failed. Check your sync account below, then try again.')
                    : null,
              ),
              GroupedRow(
                title: 'Sync Automatically',
                icon: CupertinoIcons.calendar,
                value: _scheduleLabel(s.analyticsUploadSchedule),
                onTap: () async {
                  final v = await showChoiceSheet<String>(
                    context,
                    title: 'Sync Automatically',
                    options: const ['none', 'weekly', 'monthly'],
                    selected: s.analyticsUploadSchedule,
                    label: _scheduleLabel,
                  );
                  if (v != null) notifier.setAnalyticsUploadSchedule(v);
                },
              ),
              GroupedRow(
                title: 'Remove Skipped Plays',
                subtitle: 'Deletes plays that lasted under a second.',
                icon: CupertinoIcons.trash,
                iconColor: t.bgOverlay,
                onTap: () => _run('purge', () async {
                  final n = await ref.read(listenerCollectorProvider).purgeNoiseEvents();
                  return n == 0 ? 'Nothing to remove' : 'Removed $n skipped plays';
                }, 'Couldn’t clean up. Try again.'),
              ),
            ],
          ),
          GroupedSection(
            header: 'Uploads & Sync Account',
            footer: 'Needed only for uploading songs and syncing listening data. '
                'Stored encrypted on this device.',
            children: [
              GroupedRow(
                title: 'Upload a Song',
                icon: CupertinoIcons.cloud_upload,
                trailing: _spinner('upload'),
                onTap: _busy == null ? _upload : null,
              ),
              GroupedTextFieldRow(
                title: 'Folder',
                controller: _uploadDir,
                placeholder: '/music',
                icon: CupertinoIcons.folder_fill,
              ),
              GroupedTextFieldRow(
                title: 'WebDAV URL',
                controller: _davUrl,
                placeholder: 'https://',
                keyboardType: TextInputType.url,
                icon: CupertinoIcons.link,
              ),
              GroupedTextFieldRow(
                title: 'Username',
                controller: _davUser,
                placeholder: 'Optional',
                icon: CupertinoIcons.person_fill,
              ),
              GroupedTextFieldRow(
                title: 'Password',
                controller: _davPass,
                placeholder: 'Optional',
                obscure: true,
                icon: CupertinoIcons.lock_fill,
              ),
            ],
          ),
          GroupedSection(
            header: 'About',
            children: [GroupedRow(title: 'Version', value: version)],
          ),
        ]),
      ],
    );
  }

  Widget _bitrateRow(String title, IconData icon, int current, ValueChanged<int> onPick) => GroupedRow(
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

  static String _scheduleLabel(String v) => switch (v) {
        'weekly' => 'Weekly',
        'monthly' => 'Monthly',
        _ => 'Off',
      };
}
