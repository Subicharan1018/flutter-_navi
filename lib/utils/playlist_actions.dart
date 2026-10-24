import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/playlist.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/ui/action_sheet.dart';

/// Confirms, deletes [playlist] on the server and refreshes the playlist
/// list. Returns true when it was deleted.
Future<bool> deletePlaylistWithConfirm(BuildContext context, WidgetRef ref, Playlist playlist) async {
  final ok = await confirmDestructive(
    context,
    title: 'Delete “${playlist.name}”?',
    message: 'The playlist is removed from your server. The songs stay in your library.',
    confirmLabel: 'Delete',
  );
  if (!ok) return false;
  try {
    await ref.read(subsonicServiceProvider).deletePlaylist(playlist.id);
    ref.invalidate(playlistsProvider);
    if (context.mounted) showToast(context, 'Deleted “${playlist.name}”');
    return true;
  } catch (_) {
    if (context.mounted) showToast(context, 'Couldn’t delete “${playlist.name}”. Try again.');
    return false;
  }
}
