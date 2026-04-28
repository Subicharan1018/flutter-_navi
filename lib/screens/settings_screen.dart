import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/settings_provider.dart';
import '../services/subsonic_service.dart';
import '../services/listening_event_collector.dart';
import '../core/theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _userController;
  late TextEditingController _passController;
  late TextEditingController _uploadUrlController;
  late TextEditingController _uploadDirController;
  bool _obscurePass = true;
  bool _isUploading = false;
  bool _isExporting = false;
  AnalyticsStats? _analyticsStats;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _urlController = TextEditingController(text: settings.serverUrl);
    _userController = TextEditingController(text: settings.username);
    _passController = TextEditingController(text: settings.password);
    _uploadUrlController = TextEditingController(text: settings.uploadApiUrl);
    _uploadDirController = TextEditingController(text: settings.uploadDirectory);
    // Load analytics row counts for the settings summary.
    _loadStats();
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
    _uploadUrlController.dispose();
    _uploadDirController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).saveSettings(
          _urlController.text.trim(),
          _userController.text.trim(),
          _passController.text,
          uploadUrl: _uploadUrlController.text.trim(),
          uploadDir: _uploadDirController.text.trim(),
        );
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
            backgroundColor: AppTheme.electricBlue,
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

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() => _isUploading = true);
      try {
      debugPrint('Upload UI: file=${result.files.single.path!} server=${_urlController.text.trim()} customApi=${_uploadUrlController.text.trim().isNotEmpty}');
      final cache = ref.read(playlistCacheServiceProvider);
      final service = SubsonicService(
        serverUrl: _urlController.text.trim(),
        username: _userController.text.trim(),
        password: _passController.text,
        cache: cache,
        customUploadUrl: _uploadUrlController.text.trim().isEmpty
          ? null
          : _uploadUrlController.text.trim(),
        customUploadDir: _uploadDirController.text.trim().isEmpty
          ? null
          : _uploadDirController.text.trim(),
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.coreBackground,
        appBar: AppBar(
          backgroundColor: AppTheme.coreBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: AppTheme.textPrimary, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          title: const Text(
            'Settings',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _save,
                child: const Text('Save',
                    style: TextStyle(
                        color: AppTheme.electricBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
              ],
            ),
            const SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Cloud actions
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'CLOUD ACTIONS',
              children: [
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.cloud_upload_outlined,
                      color: AppTheme.textMuted, size: 24),
                  title: const Text('Upload Song',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 15)),
                  trailing: _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.electricBlue))
                      : const Icon(Icons.chevron_right_rounded,
                          color: AppTheme.textMuted, size: 20),
                  onTap: _isUploading ? null : _upload,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Advanced Upload
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'ADVANCED UPLOAD',
              children: [
                _SettingsInputRow(
                  label: 'Custom API',
                  controller: _uploadUrlController,
                  hint: 'http://server/api/upload',
                ),
                _SettingsDivider(),
                _SettingsInputRow(
                  label: 'Remote Dir',
                  controller: _uploadDirController,
                  hint: '/DATA/Media/Music',
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Preferences (includes Smart Shuffle algorithm picker)
            // ----------------------------------------------------------------
            _SettingsGroup(
              title: 'PREFERENCES',
              children: [
                _SettingsToggleRow(
                  label: 'High Quality Audio',
                  value: true,
                  onChanged: (v) {}, // TODO: wire up when implemented
                ),
                _SettingsDivider(),

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

                if (settings.shuffleAlgorithm == ShuffleAlgorithm.spotify) ...[
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
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

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
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
                _SettingsDivider(),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.download_rounded,
                      color: AppTheme.textMuted, size: 24),
                  title: const Text('Export data as CSV',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 15)),
                  subtitle: const Text(
                    'Saves play_events, song_metadata, song_pairs, user_feedback to Downloads',
                    style: TextStyle(
                        color: AppTheme.textMuted, fontSize: 12),
                  ),
                  trailing: _isExporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.electricBlue))
                      : const Icon(Icons.chevron_right_rounded,
                          color: AppTheme.textMuted, size: 20),
                  onTap: _isExporting ? null : _exportData,
                ),
              ],
            ),
            const SizedBox(height: 32),

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
            const SizedBox(height: 120),
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
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceLevel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.outlineColor),
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

  const _SettingsInputRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 15)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 15),
              cursorColor: AppTheme.electricBlue,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                    color: AppTheme.textMuted.withOpacity(0.3)),
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
                    color: AppTheme.textMuted),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 15)),
          CupertinoSwitch(
            value: value,
            activeColor: AppTheme.electricBlue,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 15)),
          DropdownButton<T>(
            value: value,
            dropdownColor: AppTheme.surfaceLevel,
            underline: const SizedBox(),
            onChanged: onChanged,
            items: items.map((item) {
              final String name;
              if (item is ShuffleAlgorithm) {
                name = switch (item) {
                  ShuffleAlgorithm.standard => 'Standard',
                  ShuffleAlgorithm.spotify => 'Balanced',
                  ShuffleAlgorithm.youtube => 'Weighted',
                };
              } else if (item is ShufflePreference) {
                name = switch (item) {
                  ShufflePreference.composer => 'By Composer',
                  ShufflePreference.genre => 'By Genre',
                };
              } else {
                name = item.toString();
              }
              return DropdownMenuItem(
                value: item,
                child: Text(name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14)),
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

  const _SettingsNavRow({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 15)),
            Row(
              children: [
                if (value != null)
                  Text(value!,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 15)),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 20),
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
    return const Divider(height: 1, indent: 16, color: AppTheme.outlineColor);
  }
}