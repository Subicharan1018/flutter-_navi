import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/album.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';

class AlbumCard extends ConsumerWidget {
  final Album album;
  final VoidCallback onTap;
  
  const AlbumCard({super.key, required this.album, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(subsonicServiceProvider);
    
    return CupertinoClickable(
      onTap: onTap,
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: service.getCoverArtUrl(album.coverArt),
                width: 160,
                height: 160,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 160,
                  height: 160,
                  color: AppTheme.topLevel,
                  child: const Center(
                    child: Icon(Icons.album_rounded, size: 48, color: AppTheme.textMuted),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 160,
                  height: 160,
                  color: AppTheme.topLevel,
                  child: const Center(
                    child: Icon(Icons.album_rounded, size: 48, color: AppTheme.textMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              album.artist,
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
    );
  }
}
