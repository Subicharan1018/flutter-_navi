import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/song.dart';
import '../../providers/library_provider.dart' show playlistControllerProvider, songsInPlaylistProvider;
import '../../providers/settings_provider.dart' show subsonicServiceProvider;
import '../../widgets/ui/action_sheet.dart' show showToast;

/// Drops duplicate ids, keeping the first of each. A playlist made from a
/// queue or a history holds each song once.
List<Song> distinctSongs(List<Song> songs) {
  final seen = <String>{};
  return [
    for (final s in songs)
      if (seen.add(s.id)) s,
  ];
}

/// A playlist name that is not taken: [base], else "[base] 2", "[base] 3"...
/// Comparison ignores case and surrounding space, like the server's list.
String uniquePlaylistName(String base, Iterable<String> existing) {
  final taken = {for (final n in existing) n.trim().toLowerCase()};
  final clean = base.trim().isEmpty ? 'New playlist' : base.trim();
  if (!taken.contains(clean.toLowerCase())) return clean;
  for (var i = 2;; i++) {
    final candidate = '$clean $i';
    if (!taken.contains(candidate.toLowerCase())) return candidate;
  }
}

/// Asks for a name, creates the playlist on the server and fills it with
/// [songs]. Returns the playlist id, or null when cancelled or it failed
/// (a toast says so). The one path for "Save queue", "Make a playlist from
/// this evening" and restoring a removed set.
Future<String?> savePlaylistFromSongs(
  BuildContext context,
  WidgetRef ref, {
  required List<Song> songs,
  required String suggestedName,
  String title = 'Save as Playlist',
}) async {
  final list = distinctSongs(songs);
  if (list.isEmpty) {
    showToast(context, 'Nothing to save');
    return null;
  }
  final names = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: suggestedName, count: list.length),
  );
  if (names == null || names.trim().isEmpty) return null;
  try {
    final existing = (await ref.read(subsonicServiceProvider).getPlaylists()).map((p) => p.name);
    final playlist = await ref.read(playlistControllerProvider).create(uniquePlaylistName(names, existing));
    await ref.read(subsonicServiceProvider).setPlaylistSongs(playlist.id, [for (final s in list) s.id]);
    ref.invalidate(songsInPlaylistProvider(playlist.id));
    if (context.mounted) showToast(context, 'Saved “${playlist.name}”');
    return playlist.id;
  } catch (_) {
    if (context.mounted) showToast(context, 'Couldn’t save the playlist');
    return null;
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial, required this.count});
  final String title;
  final String initial;
  final int count;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return AlertDialog(
      title: Text(widget.title, textAlign: TextAlign.center),
      content: TextField(
        controller: _c,
        autofocus: true,
        maxLength: 80,
        decoration: InputDecoration(helperText: widget.count == 1 ? '1 song' : '${widget.count} songs'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: t.body.copyWith(color: t.accent)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _c.text),
          child: Text('Save', style: t.headline.copyWith(color: t.accent)),
        ),
      ],
    );
  }
}
