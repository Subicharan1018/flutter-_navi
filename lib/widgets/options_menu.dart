import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../core/theme.dart';
import 'add_to_playlist_dialog.dart';

class OptionsMenu extends ConsumerWidget {
  final Song song;
  final String? playlistId;
  /// Called when the user confirms "Remove from Playlist".
  /// Provide this when [playlistId] is non-null (e.g. from PlaylistDetailsScreen).
  final VoidCallback? onRemoveFromPlaylist;

  const OptionsMenu({
    super.key,
    required this.song,
    this.playlistId,
    this.onRemoveFromPlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeTokens.of(context).bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            SizedBox(height: 12),
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: ThemeTokens.of(context).textPrimary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            SizedBox(height: 12),

            // Song info header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          style: TextStyle(
                              color: ThemeTokens.of(context).textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          song.artist,
                          style: TextStyle(
                              color: ThemeTokens.of(context).textMuted, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(
                color: ThemeTokens.of(context).outline, indent: 24, endIndent: 24),

            // Play Next
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: Icon(Icons.playlist_play_rounded,
                  color: ThemeTokens.of(context).textPrimary, size: 24),
              title: Text('Play Next',
                  style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                // Insert the song right after the current index
                final playerState = ref.read(playerProvider);
                final notifier = ref.read(playerProvider.notifier);
                final currentQueue = List<Song>.from(playerState.queue);
                final insertAt = playerState.currentIndex + 1;
                if (insertAt >= currentQueue.length) {
                  notifier.addToQueue(song);
                } else {
                  // Use reorderQueue trick: add to end then move
                  notifier.addToQueue(song).then((_) {
                    final newState = ref.read(playerProvider);
                    notifier.reorderQueue(
                        newState.queue.length - 1, insertAt);
                  });
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Playing next')),
                );
              },
            ),

            // Add to Queue
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: Icon(Icons.queue_music_rounded,
                  color: ThemeTokens.of(context).textPrimary, size: 24),
              title: Text('Add to Queue',
                  style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                ref.read(playerProvider.notifier).addToQueue(song);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Added to queue')),
                );
              },
            ),

            // Add to Playlist — always visible so users can add the song
            // to any other playlist regardless of context.
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: Icon(Icons.playlist_add_rounded,
                  color: ThemeTokens.of(context).textPrimary, size: 24),
              title: Text('Add to Playlist',
                  style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AddToPlaylistDialog(song: song),
                );
              },
            ),

            // Remove from Playlist — only visible when inside a playlist.
            if (playlistId != null)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                leading: Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent, size: 24),
                title: Text('Remove from Playlist',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(context);
                  onRemoveFromPlaylist?.call();
                },
              ),

            // Go to Album
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: Icon(Icons.album_rounded,
                  color: ThemeTokens.of(context).textPrimary, size: 24),
              title: Text('Go to Album',
                  style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                // TODO: navigate to album screen
              },
            ),

            const Divider(
                color: ThemeTokens.of(context).outline, indent: 24, endIndent: 24),

            // ----------------------------------------------------------------
            // Smart Shuffle feedback: Suggest More / Suggest Less
            // These update the song's dynamic weight AND sync star+rating with
            // Navidrome so the YouTube Weighted algorithm picks up on it.
            // ----------------------------------------------------------------
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: Icon(Icons.thumb_up_alt_outlined,
                  color: ThemeTokens.of(context).textPrimary, size: 24),
              title: Text('Suggest More',
                  style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              subtitle: Text(
                'Boost this song in Smart Shuffle',
                style: TextStyle(color: ThemeTokens.of(context).textMuted, fontSize: 12),
              ),
              onTap: () {
                ref
                    .read(playerProvider.notifier)
                    .handleSuggestAction(song, true);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '"${song.title}" will appear more often in Smart Shuffle'),
                  ),
                );
              },
            ),

            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: Icon(Icons.thumb_down_alt_outlined,
                  color: ThemeTokens.of(context).textMuted, size: 24),
              title: Text('Suggest Less',
                  style: TextStyle(
                      color: ThemeTokens.of(context).textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              subtitle: Text(
                'Reduce this song in Smart Shuffle',
                style: TextStyle(color: ThemeTokens.of(context).textMuted, fontSize: 12),
              ),
              onTap: () {
                ref
                    .read(playerProvider.notifier)
                    .handleSuggestAction(song, false);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '"${song.title}" will appear less often in Smart Shuffle'),
                  ),
                );
              },
            ),

            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}