import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/settings_provider.dart';
import '../providers/player_provider.dart';
import '../services/subsonic_service.dart';
import '../services/listening_event_collector.dart';
import '../services/replay_gain_service.dart';
import '../services/transcoding_service.dart';
import '../services/replay_upload_service.dart';
import '../core/theme.dart';
import '../widgets/theme_selector.dart';
import 'listening_stats_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  late TextEditingController _apiBaseUrlController;
  late TextEditingController _loggingPortController;
  late TextEditingController _uploadPortController;
  late TextEditingController _shufflePortController;
  late TextEditingController _uploadDirController;
  late TextEditingController _webdavUserController;
  late TextEditingController _webdavPassController;
  bool _obscurePass = true;
  bool _obscureWebdavPass = true;
  bool _isUploading = false;
  bool _isExporting = false;
  bool _isSyncing = false;
  AnalyticsStats? _analyticsStats;

  // ── New feature states ──
  bool _imageCacheEnabled = true;
  bool _musicCacheEnabled = true;
  bool _bpmCacheEnabled = true;
  bool _transcodingEnabled = false;
  bool _smartSwitchEnabled = false;
  int _wifiBitrate = TranscodeBitrate.original;
  int _mobileBitrate = TranscodeBitrate.kbps192;
  String _transcodeFormat = TranscodeFormat.mp3;
  ReplayGainMode _replayGainMode = ReplayGainMode.off;
  double _preampGain = 0.0;
  bool _preventClipping = true;
  double _fallbackGain = -6.0;
  bool _recommendationsEnabled = true;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _urlController        = TextEditingController(text: settings.serverUrl);
    _userController       = TextEditingController(text: settings.username);
    _passController       = TextEditingController(text: settings.password);
    _apiBaseUrlController = TextEditingController(text: settings.apiBaseUrl);
    _loggingPortController = TextEditingController(text: settings.loggingPort.toString());
    _uploadPortController = TextEditingController(text: settings.uploadPort.toString());
    _shufflePortController = TextEditingController(text: settings.localShufflePort.toString());
    _uploadDirController  = TextEditingController(text: settings.uploadDirectory);
    _webdavUserController = TextEditingController(text: settings.webdavUsername);
    _webdavPassController = TextEditingController(text: settings.webdavPassword);
    // Load analytics row counts for the settings summary.
    _loadStats();
    _loadNewFeatureSettings();
  }

  Future<void> _loadNewFeatureSettings() async {
    final cache = ref.read(cacheSettingsProvider);
    await cache.initialize();
    final replay = ref.read(replayGainProvider);
    await replay.initialize();
    final transcoding = ref.read(transcodingProvider);
    final rec = ref.read(recommendationProvider);

    if (mounted) {
      setState(() {
        _imageCacheEnabled = cache.getImageCacheEnabled();
        _musicCacheEnabled = cache.getMusicCacheEnabled();
        _bpmCacheEnabled = cache.getBpmCacheEnabled();
        _transcodingEnabled = transcoding.enabled;
        _smartSwitchEnabled = transcoding.smartEnabled;
        _wifiBitrate = transcoding.wifiBitrate;
        _mobileBitrate = transcoding.mobileBitrate;
        _transcodeFormat = transcoding.format;
        _replayGainMode = replay.getMode();
        _preampGain = replay.getPreampGain();
        _preventClipping = replay.getPreventClipping();
        _fallbackGain = replay.getFallbackGain();
        _recommendationsEnabled = rec.enabled;
      });
    }
  }

  Future<void> _loadStats() async {
    final stats =
        await ref.read(listenerCollectorProvider).getStats();
    if (mounted) setState(() => _analyticsStats = stats);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _apiBaseUrlController.dispose();
    _loggingPortController.dispose();
    _uploadPortController.dispose();
    _shufflePortController.dispose();
    _uploadDirController.dispose();
    _webdavUserController.dispose();
    _webdavPassController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).saveSettings(
          _urlController.text.trim(),
          _userController.text.trim(),
          _passController.text,
          apiBaseUrl: _apiBaseUrlController.text.trim(),
          loggingPort: int.tryParse(_loggingPortController.text.trim()) ?? 5006,
          uploadPort: int.tryParse(_uploadPortController.text.trim()) ?? 5005,
          localShufflePort: int.tryParse(_shufflePortController.text.trim()) ?? 5000,
          uploadDir: _uploadDirController.text.trim(),
          webdavUser: _webdavUserController.text.trim(),
          webdavPass: _webdavPassController.text,
        );
    // Push new shuffle URL into the running AudioHandler immediately
    ref.read(playerProvider.notifier).refreshShuffleUrl();
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
  }

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    try {
      final paths =
          await ref.read(listenerCollectorProvider).exportCsvToDownloads();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${paths.length} CSV file(s) to Downloads'),
            backgroundColor: ThemeTokens.of(context).accent,
          ),
        );
        _loadStats(); // refresh counts
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _syncDataToServer() async {
    final apiBase = _apiBaseUrlController.text.trim();
    if (apiBase.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set an API Base URL before syncing analytics to the server'),
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);
    try {
      final uploadService = ref.read(replayUploadServiceProvider);
      await uploadService.uploadData('manual');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synced analytics and recommendations to server'),
            backgroundColor: ThemeTokens.of(context).accent,
          ),
        );
        _loadStats();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() => _isUploading = true);
      try {
      debugPrint('Upload UI: file=${result.files.single.path!} server=${_urlController.text.trim()}');
        final cache = ref.read(playlistCacheServiceProvider);
        final uploadUrl = ref.read(settingsProvider).uploadApiUrl; // computed
        final service = SubsonicService(
          serverUrl: _urlController.text.trim(),
          username: _userController.text.trim(),
          password: _passController.text,
          cache: cache,
          customUploadUrl: uploadUrl.isEmpty ? null : uploadUrl,
          customUploadDir: _uploadDirController.text.trim().isEmpty
            ? null
            : _uploadDirController.text.trim(),
          webdavUsername: _webdavUserController.text.trim(),
          webdavPassword: _webdavPassController.text,
        );
        await service.uploadSong(File(result.files.single.path!));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload successful')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final tokens = ThemeTokens.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tokens.isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        appBar: AppBar(
          backgroundColor: tokens.bgBase,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: Icon(Icons.close_rounded,
                  color: tokens.textPrimary, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          title: Text(
            'Settings',
            style: TextStyle(
                color: tokens.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _save,
                child: Text('Save',
                    style: TextStyle(
                        color: tokens.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            ThemeSelector(),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Server connection
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'SERVER CONNECTION',
              children: [
                _SettingsInputRow(
                  label: 'Server URL',
                  controller: _urlController,
                  hint: 'https://...',
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'Username',
                  controller: _userController,
                  hint: 'User',
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'Password',
                  controller: _passController,
                  hint: '••••••••',
                  obscure: _obscurePass,
                  onToggleObscure: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
                _SettingsDivider(),
                _SettingsToggleRow(
                  label: 'Allow HTTP connection (Insecure)',
                  value: settings.allowHttp,
                  onChanged: (v) {
                    ref.read(settingsProvider.notifier).setAllowHttp(v);
                  },
                ),
              ],
            ),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Cloud actions
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'CLOUD ACTIONS',
              children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(Icons.cloud_upload_outlined,
                      color: ThemeTokens.of(context).textMuted, size: 24),
                  title: Text('Upload Song',
                      style: TextStyle(
                          color: ThemeTokens.of(context).textPrimary, fontSize: 15)),
                  trailing: _isUploading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ThemeTokens.of(context).accent))
                      : Icon(Icons.chevron_right_rounded,
                          color: ThemeTokens.of(context).textMuted, size: 20),
                  onTap: _isUploading ? null : _upload,
                ),
              ],
            ),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Advanced Upload
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'API SERVER',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text(
                    'Base URL (no port) for the AI shuffle, telemetry and upload services.',
                    style: TextStyle(
                        color: ThemeTokens.of(context).textMuted, fontSize: 12),
                  ),
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'API Base URL',
                  controller: _apiBaseUrlController,
                  hint: 'http://192.168.1.10',
                  keyboardType: TextInputType.url,
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'Logging Port',
                  controller: _loggingPortController,
                  hint: '5006',
                  keyboardType: TextInputType.number,
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'Upload Port',
                  controller: _uploadPortController,
                  hint: '5005',
                  keyboardType: TextInputType.number,
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'Shuffle Port',
                  controller: _shufflePortController,
                  hint: '5000',
                  keyboardType: TextInputType.number,
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'Remote Dir',
                  controller: _uploadDirController,
                  hint: '/DATA/Media/Music',
                ),
                _SettingsDivider(),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(Icons.bar_chart_rounded,
                      color: ThemeTokens.of(context).textMuted, size: 24),
                  title: Text('Listening Stats',
                      style: TextStyle(
                          color: ThemeTokens.of(context).textPrimary,
                          fontSize: 15)),
                  subtitle: Text(
                    'View your top artists, tracks and recent plays',
                    style: TextStyle(
                        color: ThemeTokens.of(context).textMuted,
                        fontSize: 12),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      color: ThemeTokens.of(context).textMuted, size: 20),
                  onTap: () {
                    final base = _apiBaseUrlController.text.trim();
                    if (base.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Set an API Base URL first to use Listening Stats'),
                        ),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ListeningStatsScreen()),
                    );
                  },
                ),
              ],
            ),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // WebDAV Credentials
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'WEBDAV CREDENTIALS',
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Text(
                    'Required only if using the WebDAV sync/upload features. '
                    'Stored in encrypted local storage.',
                    style: TextStyle(
                        color: ThemeTokens.of(context).textMuted, fontSize: 12),
                  ),
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'WD Username',
                  controller: _webdavUserController,
                  hint: 'webdav-user',
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'WD Password',
                  controller: _webdavPassController,
                  hint: '••••••••',
                  obscure: _obscureWebdavPass,
                  onToggleObscure: () =>
                      setState(() => _obscureWebdavPass = !_obscureWebdavPass),
                ),
              ],
            ),
            SizedBox(height: 32),

            _SettingsGroup(
              title: 'PREFERENCES',
              children: [
                // Smart Shuffle Algorithm
                _SettingsDropdownRow<ShuffleAlgorithm>(
                  label: 'Shuffle Algorithm',
                  value: settings.shuffleAlgorithm,
                  items: ShuffleAlgorithm.values,
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(settingsProvider.notifier)
                          .setShuffleAlgorithm(v);
                    }
                  },
                ),
                _SettingsDivider(),

                if (settings.shuffleAlgorithm == ShuffleAlgorithm.spotify ||
                    settings.shuffleAlgorithm == ShuffleAlgorithm.mergeShuffle) ...[
                  _SettingsDropdownRow<ShufflePreference>(
                    label: 'Balanced Grouping',
                    value: settings.shufflePreference,
                    items: ShufflePreference.values,
                    onChanged: (v) {
                      if (v != null) {
                        ref
                            .read(settingsProvider.notifier)
                            .setShufflePreference(v);
                      }
                    },
                  ),
                  _SettingsDivider(),
                ],

                // Info tile so users know what each algorithm does
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Text(
                    _shuffleAlgorithmDescription(settings.shuffleAlgorithm),
                    style: TextStyle(
                        color: ThemeTokens.of(context).textMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Listening Intelligence
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'LISTENING INTELLIGENCE',
              children: [
                _SettingsToggleRow(
                  label: 'Collect listening data',
                  value: settings.dataCollectionEnabled,
                  onChanged: (v) {
                    ref
                        .read(settingsProvider.notifier)
                        .setDataCollectionEnabled(v);
                  },
                ),
                _SettingsDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Text(
                    _analyticsStats == null
                        ? 'Loading stats…'
                        : '${_analyticsStats!.playEvents} plays • '
                            '${_analyticsStats!.uniqueSongs} songs • '
                            '${_analyticsStats!.songPairs} pairs • '
                            '${_analyticsStats!.feedbackActions} feedback signals',
                    style: TextStyle(
                        color: ThemeTokens.of(context).textMuted, fontSize: 12),
                  ),
                ),
                _SettingsDivider(),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(Icons.download_rounded,
                      color: ThemeTokens.of(context).textMuted, size: 24),
                  title: Text('Export data as CSV',
                      style: TextStyle(
                          color: ThemeTokens.of(context).textPrimary, fontSize: 15)),
                  subtitle: Text(
                    'Saves play_events, song_metadata, song_pairs, user_feedback to Downloads',
                    style: TextStyle(
                        color: ThemeTokens.of(context).textMuted, fontSize: 12),
                  ),
                  trailing: _isExporting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ThemeTokens.of(context).accent))
                      : Icon(Icons.chevron_right_rounded,
                          color: ThemeTokens.of(context).textMuted, size: 20),
                  onTap: _isExporting ? null : _exportData,
                ),
                _SettingsDivider(),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(Icons.cloud_sync_outlined,
                      color: ThemeTokens.of(context).textMuted, size: 24),
                  title: Text('Sync data to server',
                      style: TextStyle(
                          color: ThemeTokens.of(context).textPrimary, fontSize: 15)),
                  subtitle: Text(
                    'Streams play_events, song_metadata, song_pairs, user_feedback to your WebDAV target',
                    style: TextStyle(
                        color: ThemeTokens.of(context).textMuted, fontSize: 12),
                  ),
                  trailing: _isSyncing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ThemeTokens.of(context).accent))
                      : Icon(Icons.chevron_right_rounded,
                          color: ThemeTokens.of(context).textMuted, size: 20),
                  onTap: _isSyncing ? null : _syncDataToServer,
                ),
                _SettingsDivider(),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(Icons.cleaning_services_rounded,
                      color: ThemeTokens.of(context).textMuted, size: 24),
                  title: Text('Clean up junk data',
                      style: TextStyle(
                          color: ThemeTokens.of(context).textPrimary, fontSize: 15)),
                  subtitle: Text(
                    'Purges redundant 0-second play events from the local database',
                    style: TextStyle(
                        color: ThemeTokens.of(context).textMuted, fontSize: 12),
                  ),
                  onTap: () async {
                    final purgedCount = await ref
                        .read(listenerCollectorProvider)
                        .purgeNoiseEvents();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Purged $purgedCount junk events'),
                          backgroundColor: ThemeTokens.of(context).accent,
                        ),
                      );
                      _loadStats(); // refresh counts
                    }
                  },
                ),
                _SettingsDivider(),
                _SettingsDropdownRow<String>(
                  label: 'Auto-Upload Schedule',
                  value: settings.analyticsUploadSchedule,
                  items: const ['none', 'weekly', 'monthly'],
                  onChanged: (v) {
                    if (v != null) {
                      ref.read(settingsProvider.notifier).setAnalyticsUploadSchedule(v);
                    }
                  },
                ),
              ],
            ),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Cache Management
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'CACHE MANAGEMENT',
              children: [
                _SettingsToggleRow(
                  label: 'Image Cache',
                  value: _imageCacheEnabled,
                  onChanged: (v) {
                    setState(() => _imageCacheEnabled = v);
                    ref.read(cacheSettingsProvider).setImageCacheEnabled(v);
                  },
                ),
                _SettingsDivider(),
                _SettingsToggleRow(
                  label: 'Music Cache',
                  value: _musicCacheEnabled,
                  onChanged: (v) {
                    setState(() => _musicCacheEnabled = v);
                    ref.read(cacheSettingsProvider).setMusicCacheEnabled(v);
                  },
                ),
                _SettingsDivider(),
                _SettingsToggleRow(
                  label: 'BPM Cache',
                  value: _bpmCacheEnabled,
                  onChanged: (v) {
                    setState(() => _bpmCacheEnabled = v);
                    ref.read(cacheSettingsProvider).setBpmCacheEnabled(v);
                  },
                ),
              ],
            ),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Audio Quality (Transcoding)
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'AUDIO QUALITY',
              children: [
                _SettingsToggleRow(
                  label: 'Transcoding',
                  value: _transcodingEnabled,
                  onChanged: (v) {
                    setState(() => _transcodingEnabled = v);
                    ref.read(transcodingProvider).setEnabled(v);
                  },
                ),
                if (_transcodingEnabled) ...[
                  _SettingsDivider(),
                  _SettingsNavRow(
                    label: 'Wi-Fi Bitrate',
                    value: TranscodeBitrate.getLabel(_wifiBitrate),
                    onTap: () => _showBitrateSelector(
                      title: 'Wi-Fi Bitrate',
                      current: _wifiBitrate,
                      onSelect: (v) {
                        setState(() => _wifiBitrate = v);
                        ref.read(transcodingProvider).setWifiBitrate(v);
                      },
                    ),
                  ),
                  _SettingsDivider(),
                  _SettingsNavRow(
                    label: 'Mobile Bitrate',
                    value: TranscodeBitrate.getLabel(_mobileBitrate),
                    onTap: () => _showBitrateSelector(
                      title: 'Mobile Bitrate',
                      current: _mobileBitrate,
                      onSelect: (v) {
                        setState(() => _mobileBitrate = v);
                        ref.read(transcodingProvider).setMobileBitrate(v);
                      },
                    ),
                  ),
                  _SettingsDivider(),
                  _SettingsNavRow(
                    label: 'Format',
                    value: TranscodeFormat.getLabel(_transcodeFormat),
                    onTap: () => _showFormatSelector(),
                  ),
                  _SettingsDivider(),
                  _SettingsToggleRow(
                    label: 'Smart Switch',
                    value: _smartSwitchEnabled,
                    onChanged: (v) {
                      setState(() => _smartSwitchEnabled = v);
                      ref.read(transcodingProvider).setSmartEnabled(v);
                    },
                  ),
                ],
              ],
            ),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Replay Gain
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'REPLAY GAIN',
              children: [
                _SettingsNavRow(
                  label: 'Mode',
                  value: _replayGainMode.name.toUpperCase(),
                  onTap: () => _showReplayGainModeSelector(),
                ),
                if (_replayGainMode != ReplayGainMode.off) ...[
                  _SettingsDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Pre-amp',
                            style: TextStyle(color: ThemeTokens.of(context).textPrimary, fontSize: 15)),
                        Text('${_preampGain.toStringAsFixed(1)} dB',
                            style: TextStyle(color: ThemeTokens.of(context).textMuted, fontSize: 15)),
                      ],
                    ),
                  ),
                  Slider(
                    value: _preampGain,
                    min: -15.0,
                    max: 15.0,
                    divisions: 60,
                    activeColor: ThemeTokens.of(context).accent,
                    onChanged: (v) {
                      setState(() => _preampGain = v);
                      ref.read(replayGainProvider).setPreampGain(v);
                    },
                  ),
                  _SettingsDivider(),
                  _SettingsToggleRow(
                    label: 'Prevent Clipping',
                    value: _preventClipping,
                    onChanged: (v) {
                      setState(() => _preventClipping = v);
                      ref.read(replayGainProvider).setPreventClipping(v);
                    },
                  ),
                  _SettingsDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Fallback Gain',
                            style: TextStyle(color: ThemeTokens.of(context).textPrimary, fontSize: 15)),
                        Text('${_fallbackGain.toStringAsFixed(1)} dB',
                            style: TextStyle(color: ThemeTokens.of(context).textMuted, fontSize: 15)),
                      ],
                    ),
                  ),
                  Slider(
                    value: _fallbackGain,
                    min: -15.0,
                    max: 0.0,
                    divisions: 30,
                    activeColor: ThemeTokens.of(context).accent,
                    onChanged: (v) {
                      setState(() => _fallbackGain = v);
                      ref.read(replayGainProvider).setFallbackGain(v);
                    },
                  ),
                ],
              ],
            ),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Recommendations
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'RECOMMENDATIONS',
              children: [
                _SettingsToggleRow(
                  label: 'Enabled',
                  value: _recommendationsEnabled,
                  onChanged: (v) {
                    setState(() => _recommendationsEnabled = v);
                    ref.read(recommendationProvider).setEnabled(v);
                  },
                ),
                _SettingsDivider(),
                _SettingsNavRow(
                  label: 'Listening Stats',
                  value: '${ref.read(recommendationProvider).profiles.length} songs',
                ),
                _SettingsDivider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onPressed: () async {
                        final confirm = await showCupertinoDialog<bool>(
                          context: context,
                          builder: (ctx) => CupertinoAlertDialog(
                            title: Text('Clear Recommendation Data'),
                            content: Text(
                                'This will delete all listening patterns and '  
                                'personalisation data. This cannot be undone.'),
                            actions: [
                              CupertinoDialogAction(
                                child: Text('Cancel'),
                                onPressed: () => Navigator.pop(ctx, false),
                              ),
                              CupertinoDialogAction(
                                isDestructiveAction: true,
                                child: Text('Clear'),
                                onPressed: () => Navigator.pop(ctx, true),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(recommendationProvider).clearData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Recommendation data cleared'),
                                backgroundColor: ThemeTokens.of(context).accent,
                              ),
                            );
                            setState(() {});
                          }
                        }
                      },
                      child: Text('Clear Data',
                          style: TextStyle(
                              color: Colors.redAccent, fontSize: 14)),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 32),

            // ----------------------------------------------------------------
            // About
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'ABOUT',
              children: [
                _SettingsNavRow(label: 'Version', value: '1.0.0'),
                _SettingsDivider(),
                _SettingsNavRow(label: 'Terms of Service'),
              ],
            ),
            SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  String _shuffleAlgorithmDescription(ShuffleAlgorithm algo) {
    switch (algo) {
      case ShuffleAlgorithm.standard:
        return 'Standard random shuffle — every song is equally likely to play next.';
      case ShuffleAlgorithm.spotify:
        return 'Balanced Dithering — tracks are spaced evenly based on your preference (Composer or Genre) so the same category never plays back-to-back.';
      case ShuffleAlgorithm.youtube:
        return 'Weighted Mix — songs you love (stars, high ratings, "Suggest More") appear more often. Use "Suggest More / Less" on any track to tune it.';
      case ShuffleAlgorithm.albumAware:
        return 'Album-Aware — shuffles albums as atomic units. Keeps the track order within each album intact.';
      case ShuffleAlgorithm.mergeShuffle:
        return 'Mathematical Optimum — interleaves categories (Composer/Genre) perfectly using the Merge-Shuffle algorithm (2023).';
      case ShuffleAlgorithm.recencyDampened:
        return 'Recency-Dampened — weighted mix that penalizes songs played recently in this session to ensure variety.';
      case ShuffleAlgorithm.smartLocal:
        return 'Smart Local AI — Uses a local machine learning model to predict the best next songs based on transitions and behavioral scores.';
    }
  }

  void _showBitrateSelector({
    required String title,
    required int current,
    required ValueChanged<int> onSelect,
  }) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: TranscodeBitrate.options.map((b) {
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              onSelect(b);
            },
            child: Text(
              TranscodeBitrate.getLabel(b),
              style: TextStyle(
                  fontWeight:
                      b == current ? FontWeight.bold : FontWeight.normal),
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel'),
        ),
      ),
    );
  }

  void _showFormatSelector() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('Audio Format'),
        actions: TranscodeFormat.options.map((f) {
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _transcodeFormat = f);
              ref.read(transcodingProvider).setFormat(f);
            },
            child: Text(
              TranscodeFormat.getLabel(f),
              style: TextStyle(
                  fontWeight:
                      f == _transcodeFormat ? FontWeight.bold : FontWeight.normal),
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel'),
        ),
      ),
    );
  }

  void _showReplayGainModeSelector() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('Replay Gain Mode'),
        actions: ReplayGainMode.values.map((m) {
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _replayGainMode = m);
              ref.read(replayGainProvider).setMode(m);
            },
            child: Text(
              m.name.toUpperCase(),
              style: TextStyle(
                  fontWeight:
                      m == _replayGainMode ? FontWeight.bold : FontWeight.normal),
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helper widgets
// ---------------------------------------------------------------------------

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
                color: tokens.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: tokens.bgSurfaceOpaque,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: tokens.outline),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsInputRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;

  const _SettingsInputRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    color: tokens.textPrimary, fontSize: 15)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: tokens.textMuted, fontSize: 15),
              cursorColor: tokens.accent,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                    color: tokens.textMuted.withOpacity(0.3)),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (onToggleObscure != null)
            SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: tokens.textMuted),
                onPressed: onToggleObscure,
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleRow(
      {required this.label,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: tokens.textPrimary, fontSize: 15)),
          CupertinoSwitch(
            value: value,
            activeTrackColor: tokens.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsDropdownRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const _SettingsDropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: tokens.textPrimary, fontSize: 15)),
          DropdownButton<T>(
            value: value,
            // bgSurfaceOpaque composites a translucent surface over bgBase,
            // ensuring the Frost theme's glass-white surface doesn't bleed
            // through the dropdown menu making text unreadable.
            dropdownColor: tokens.bgSurfaceOpaque,
            underline: SizedBox(),
            onChanged: onChanged,
            items: items.map((item) {
              final String name;
              if (item is ShuffleAlgorithm) {
                name = switch (item) {
                  ShuffleAlgorithm.standard => 'Standard',
                  ShuffleAlgorithm.spotify => 'Balanced',
                  ShuffleAlgorithm.youtube => 'Weighted',
                  ShuffleAlgorithm.albumAware => 'Album-Aware',
                  ShuffleAlgorithm.mergeShuffle => 'Optimum',
                  ShuffleAlgorithm.recencyDampened => 'Variety-Weighted',
                  ShuffleAlgorithm.smartLocal => 'Smart Local AI',
                };
              } else if (item is ShufflePreference) {
                name = switch (item) {
                  ShufflePreference.composer => 'By Composer',
                  ShufflePreference.genre => 'By Genre',
                };
              } else if (item is String) {
                if (item == 'none') {
                  name = 'Disabled';
                } else if (item == 'weekly') name = 'Weekly';
                else if (item == 'monthly') name = 'Monthly';
                else name = item;
              } else {
                name = item.toString();
              }
              return DropdownMenuItem(
                value: item,
                child: Text(name,
                    style: TextStyle(
                        color: tokens.textPrimary, fontSize: 14)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback? onTap;

  const _SettingsNavRow({required this.label, this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return InkWell(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: tokens.textPrimary, fontSize: 15)),
            Row(
              children: [
                if (value != null)
                  Text(value!,
                      style: TextStyle(
                          color: tokens.textMuted, fontSize: 15)),
                SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: tokens.textMuted, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Divider(height: 1, indent: 16, color: tokens.outline);
  }
}
