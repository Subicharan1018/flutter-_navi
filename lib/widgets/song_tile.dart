import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/settings_provider.dart';
import '../providers/player_provider.dart';
import '../core/theme.dart';
import 'options_menu.dart';

class SongTile extends ConsumerWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? playlistId;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onLongPress,
    this.playlistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(subsonicServiceProvider);
    final playerState = ref.watch(playerProvider);
    
    final bool isActive = playerState.queue.isNotEmpty && 
        playerState.currentIndex < playerState.queue.length &&
        playerState.queue[playerState.currentIndex].id == song.id;

    return CupertinoClickable(
      onTap: onTap,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: service.getCoverArtUrl(song.coverArt),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 48,
                    height: 48,
                    color: AppTheme.topLevel,
                    child: const Icon(Icons.music_note_rounded, color: AppTheme.textMuted, size: 24),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 48,
                    height: 48,
                    color: AppTheme.topLevel,
                    child: const Icon(Icons.music_note_rounded, color: AppTheme.textMuted, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isActive ? AppTheme.spotifyGreen : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.more_horiz_rounded, color: AppTheme.textSecondary, size: 20),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => OptionsMenu(song: song, playlistId: playlistId),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
