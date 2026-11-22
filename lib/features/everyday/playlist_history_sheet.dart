import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart' show playlistsProvider, songsInPlaylistProvider;
import '../../providers/settings_provider.dart' show subsonicServiceProvider;
import '../../widgets/art/navi_icons.dart';
import '../../widgets/desktop_dialogs.dart';
import '../../widgets/ui/action_sheet.dart';
import 'history_logic.dart' show dayLabel;
import 'playlist_versions.dart';
import 'playlist_versions_providers.dart';

/// "History…" on a playlist: songs that were taken out, and earlier versions
/// to go back to (R7).
Future<void> showPlaylistHistory(
  BuildContext context, {
  required String playlistId,
  required List<Song> current,
  required bool readOnly,
  required VoidCallback onChanged,
}) =>
    showPlatformSheet(
      context: context,
      title: 'Playlist History',
      builder: (_) => PlaylistHistorySheet(
        playlistId: playlistId,
        current: current,
        readOnly: readOnly,
        onChanged: onChanged,
      ),
    );

String _when(DateTime at, DateTime now) {
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final m = at.minute.toString().padLeft(2, '0');
  return '${dayLabel(at, now)}, $h:$m ${at.hour < 12 ? 'am' : 'pm'}';
}

class PlaylistHistorySheet extends ConsumerWidget {
  const PlaylistHistorySheet({
    super.key,
    required this.playlistId,
    required this.current,
    required this.readOnly,
    required this.onChanged,
  });

  final String playlistId;
  final List<Song> current;
  final bool readOnly;
  final VoidCallback onChanged;

  Future<void> _write(BuildContext page, WidgetRef ref, List<String> ids, String done) async {
    try {
      final svc = ref.read(subsonicServiceProvider);
      await svc.setPlaylistSongs(playlistId, ids);
      await svc.invalidatePlaylist(playlistId);
      ref.invalidate(songsInPlaylistProvider(playlistId));
      ref.invalidate(playlistsProvider);
      onChanged();
      if (page.mounted) showToast(page, done);
    } catch (_) {
      if (page.mounted) showToast(page, 'Couldn’t change the playlist. Try again.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final versions = ref.watch(playlistVersionsProvider.select((m) => m[playlistId])) ?? const <PlaylistVersion>[];
    final currentIds = [for (final s in current) s.id];
    final removed = PlaylistVersions.recentlyRemoved(versions, currentIds, max: 8);
    final now = DateTime.now();
    final page = Navigator.of(context).context;

    if (versions.length < 2 && removed.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Changes to this playlist are kept from now on, so a removed song can be put back.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (removed.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xs),
              child: Align(alignment: Alignment.centerLeft, child: Text('Recently removed', style: t.footnote)),
            ),
            SheetGroup(children: [
              for (final r in removed)
                SheetAction(
                  key: ValueKey('rm_${r.song.id}'),
                  label: r.song.title,
                  detail: '${r.song.artist} · ${_when(r.removedAt, now)}',
                  icon: NaviGlyph.plusCircle,
                  onTap: readOnly
                      ? null
                      : () => _write(page, ref, PlaylistVersions.withAdded(currentIds, [r.song.id]), 'Put back “${r.song.title}”'),
                ),
            ]),
          ],
          if (versions.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.xs),
              child: Align(alignment: Alignment.centerLeft, child: Text('Earlier versions', style: t.footnote)),
            ),
            SheetGroup(children: [
              for (var i = 0; i < versions.length; i++)
                SheetAction(
                  key: ValueKey('v_${versions[i].at.millisecondsSinceEpoch}'),
                  label: _when(versions[i].at, now),
                  detail: i + 1 < versions.length
                      ? '${versions[i].songs.length} songs · ${PlaylistVersions.diff(versions[i + 1], versions[i]).summary}'
                      : '${versions[i].songs.length} songs · first seen',
                  icon: NaviGlyph.rewind,
                  onTap: readOnly || i == 0 && _sameAsCurrent(versions[i], currentIds)
                      ? null
                      : () async {
                          final ok = await confirmDestructive(
                            page,
                            title: 'Restore this version?',
                            message: 'The playlist goes back to ${versions[i].songs.length} songs as of ${_when(versions[i].at, now)}. '
                                'What it is now stays in this history.',
                            confirmLabel: 'Restore',
                          );
                          if (!ok || !page.mounted) return;
                          // The playlist as it is now is kept first, so a restore can be undone.
                          ref.read(playlistVersionsProvider.notifier).record(playlistId, current);
                          await _write(page, ref, PlaylistVersions.restoreIds(versions[i]), 'Playlist restored');
                        },
                ),
            ]),
          ],
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }

  bool _sameAsCurrent(PlaylistVersion v, List<String> ids) {
    final a = v.ids;
    if (a.length != ids.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != ids[i]) return false;
    }
    return true;
  }
}
