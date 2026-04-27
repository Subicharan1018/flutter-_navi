import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../core/theme.dart';
import 'add_to_playlist_dialog.dart';

class OptionsMenu extends ConsumerWidget {
  final Song song;
  final String? playlistId;

  const OptionsMenu({super.key, required this.song, this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceLevel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.textPrimary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),

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
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist,
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 13),
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
                color: AppTheme.outlineColor, indent: 24, endIndent: 24),

            // Play Next
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: const Icon(Icons.playlist_play_rounded,
                  color: AppTheme.textPrimary, size: 24),
              title: const Text('Play Next',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
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
              leading: const Icon(Icons.queue_music_rounded,
                  color: AppTheme.textPrimary, size: 24),
              title: const Text('Add to Queue',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
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

            // Remove from Playlist / Add to Playlist
            if (playlistId != null)
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent, size: 24),
                title: const Text('Remove from Playlist',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                onTap: () async {
                  Navigator.pop(context);
                  // Caller should handle the actual removal with playlistId
                },
              )
            else
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                leading: const Icon(Icons.playlist_add_rounded,
                    color: AppTheme.textPrimary, size: 24),
                title: const Text('Add to Playlist',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
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

            // Go to Album
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: const Icon(Icons.album_rounded,
                  color: AppTheme.textPrimary, size: 24),
              title: const Text('Go to Album',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                // TODO: navigate to album screen
              },
            ),

            const Divider(
                color: AppTheme.outlineColor, indent: 24, endIndent: 24),

            // ----------------------------------------------------------------
            // Smart Shuffle feedback: Suggest More / Suggest Less
            // These update the song's dynamic weight AND sync star+rating with
            // Navidrome so the YouTube Weighted algorithm picks up on it.
            // ----------------------------------------------------------------
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: const Icon(Icons.thumb_up_alt_outlined,
                  color: AppTheme.textPrimary, size: 24),
              title: const Text('Suggest More',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              subtitle: const Text(
                'Boost this song in Smart Shuffle',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
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
              leading: const Icon(Icons.thumb_down_alt_outlined,
                  color: AppTheme.textMuted, size: 24),
              title: const Text('Suggest Less',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
              subtitle: const Text(
                'Reduce this song in Smart Shuffle',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
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

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}