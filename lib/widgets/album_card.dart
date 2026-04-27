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
    // ---------------------------------------------------------------------------
    // FIX 1 — ref.read instead of ref.watch for the stable service singleton.
    // AlbumCard has no state that depends on service mutations, so watching it
    // just adds unnecessary listener overhead in every card.
    // ---------------------------------------------------------------------------
    final service = ref.read(subsonicServiceProvider);

    // ---------------------------------------------------------------------------
    // FIX 2 — Static cacheKey so the Subsonic salt/token rotation in the URL
    // doesn't bust the image cache on every rebuild/scroll.
    // ---------------------------------------------------------------------------
    final String imageUrl = service.getCoverArtUrl(album.coverArt);
    final String imageCacheKey = 'cover_${album.coverArt ?? album.id}';

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
                imageUrl: imageUrl,
                cacheKey: imageCacheKey, // ← stable cache key
                width: 160,
                height: 160,
                fit: BoxFit.cover,
                placeholder: (context, url) => const _AlbumPlaceholder(),
                errorWidget: (context, url, error) => const _AlbumPlaceholder(),
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

// Extracted so Flutter can reuse the const element across all cards.
class _AlbumPlaceholder extends StatelessWidget {
  const _AlbumPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 160,
      color: AppTheme.topLevel,
      child: const Center(
        child: Icon(Icons.album_rounded, size: 48, color: AppTheme.textMuted),
      ),
    );
  }
}