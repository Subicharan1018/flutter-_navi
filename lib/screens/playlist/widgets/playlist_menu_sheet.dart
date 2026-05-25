import 'package:flutter/material.dart';
import '../../../models/playlist.dart';
import '../../../core/theme.dart';
import '../../edit_playlist_screen.dart';

class PlaylistMenuSheet extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onPlaylistEdited;
  final VoidCallback onDeleteTapped;

  const PlaylistMenuSheet({
    super.key,
    required this.playlist,
    required this.onPlaylistEdited,
    required this.onDeleteTapped,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(
              Icons.edit_rounded,
              color: ThemeTokens.of(context).textPrimary,
            ),
            title: Text(
              'Edit Playlist',
              style: TextStyle(
                color: ThemeTokens.of(context).textPrimary,
                fontSize: 15,
              ),
            ),
            onTap: () async {
              Navigator.pop(context);
              final changed = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditPlaylistScreen(playlist: playlist),
                ),
              );
              if (changed == true) onPlaylistEdited();
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
            ),
            title: const Text(
              'Delete Playlist',
              style: TextStyle(color: Colors.redAccent, fontSize: 15),
            ),
            onTap: () {
              Navigator.pop(context);
              onDeleteTapped();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
