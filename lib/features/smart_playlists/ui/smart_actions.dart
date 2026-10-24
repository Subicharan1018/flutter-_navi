import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/collection_actions.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../data/smart_rules.dart';
import '../logic/smart_playlist_providers.dart';
import 'rule_editor_screen.dart';
import 'smart_widgets.dart';

/// Writes the songs [playlist] matches now to Navidrome as a normal playlist
/// (overwriting the one saved before, if it still exists) and says so.
Future<void> saveSmartToServer(BuildContext page, ProviderContainer container, SmartPlaylist playlist) async {
  try {
    final songs = await smartSongsOnce(container, playlist);
    if (songs.isEmpty) {
      if (page.mounted) showToast(page, 'No songs match “${playlist.name}” yet');
      return;
    }
    await container.read(smartPlaylistSaverProvider).save(playlist, songs);
    if (page.mounted) showToast(page, 'Saved “${playlist.name}” to your server');
  } catch (_) {
    if (page.mounted) showToast(page, 'Couldn’t save “${playlist.name}”. Check your connection.');
  }
}

/// Confirms, then removes a smart playlist from this device. Playlists it
/// saved to the server are left alone. Returns true when deleted.
Future<bool> deleteSmartWithConfirm(BuildContext context, ProviderContainer container, SmartPlaylist playlist) async {
  final ok = await confirmDestructive(
    context,
    title: 'Delete “${playlist.name}”?',
    message: 'The rules are removed from this device. A playlist saved to your server stays there.',
    confirmLabel: 'Delete',
  );
  if (!ok) return false;
  container.read(smartPlaylistsProvider.notifier).remove(playlist.id);
  if (context.mounted) showToast(context, 'Deleted “${playlist.name}”');
  return true;
}

/// Long-press / More menu for a smart playlist.
Future<void> showSmartPlaylistActions(
  BuildContext context,
  SmartPlaylist playlist, {
  VoidCallback? onDeleted,
}) {
  final container = ProviderScope.containerOf(context);
  final t = ThemeTokens.of(context);
  return showCollectionActions(
    context,
    title: playlist.name,
    subtitle: 'Smart Playlist',
    loadSongs: () => smartSongsOnce(container, playlist),
    onEdit: () => showSmartPlaylistEditor(context, playlist: playlist),
    onDelete: () async {
      if (await deleteSmartWithConfirm(context, container, playlist)) onDeleted?.call();
    },
    extraActions: [
      SheetAction(
        label: 'Save as Playlist',
        detail: 'Writes the current matches to your server',
        trailing: NaviIcon(NaviGlyph.addToPlaylist, size: 21, color: t.textPrimary),
        onTap: () => saveSmartToServer(context, container, playlist),
      ),
      FolderMoveAction(playlistId: playlist.id, page: context),
    ],
  );
}
