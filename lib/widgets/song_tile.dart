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
    // ---------------------------------------------------------------------------
    // FIX 1 — Use ref.read for the service, not ref.watch.
    //
    // subsonicServiceProvider holds a stable singleton (the HTTP client).
    // Watching it means this tile re-subscribes on every rebuild and participates
    // in any notification the service emits.  Reading it once per build is safe
    // and avoids the extra listener overhead across 5 000 tiles.
    // ---------------------------------------------------------------------------
    final service = ref.read(subsonicServiceProvider);

    // ---------------------------------------------------------------------------
    // FIX 2 — select() narrows this tile's subscription to a single bool.
    //
    // PlayerState ticks on EVERY position update (≈1 Hz).  Without select(),
    // the whole 5 000-tile list rebuilds every second.  With select(), Riverpod
    // only notifies this tile when `isActive` actually flips (true↔false) — i.e.
    // when the track changes.  All other state mutations (position, buffering,
    // volume) are silently ignored by this widget.
    // ---------------------------------------------------------------------------
    final bool isActive = ref.watch(
      playerProvider.select(
        (s) =>
            s.queue.isNotEmpty &&
            s.currentIndex < s.queue.length &&
            s.queue[s.currentIndex].id == song.id,
      ),
    );

    // ---------------------------------------------------------------------------
    // FIX 3 — Static cacheKey isolates the disk/memory cache from the URL.
    //
    // Subsonic authentication appends a salt+token to every URL.  If the service
    // regenerates salt on each call, the URL string differs on every rebuild, so
    // CachedNetworkImage treats it as a brand-new image and re-downloads it.
    // Pinning cacheKey to the song ID means the cache lookup uses a stable string
    // regardless of what the authentication parameters look like.
    // ---------------------------------------------------------------------------
    final String coverId = song.coverArt.isNotEmpty ? song.coverArt : song.id;
    final String imageUrl = service.getCoverArtUrl(coverId);
    final String imageCacheKey = 'cover_$coverId';

    return CupertinoClickable(
      onTap: onTap,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Album art
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  cacheKey: imageCacheKey, // ← stable cache key
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  memCacheWidth: 150,
                  memCacheHeight: 150,
                  placeholder: (context, url) => const _ArtPlaceholder(size: 48),
                  errorWidget: (context, url, error) => const _ArtPlaceholder(size: 48),
                ),
              ),
              const SizedBox(width: 12),

              // Title + artist
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
                        // AnimatedDefaultTextStyle would also work here but
                        // a plain conditional is cheaper for a list this large.
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

              // Options
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) =>
                        OptionsMenu(song: song, playlistId: playlistId),
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

// ---------------------------------------------------------------------------
// Extracted placeholder — const-constructable so Flutter reuses the element
// instead of recreating it on every scroll-in.
// ---------------------------------------------------------------------------
class _ArtPlaceholder extends StatelessWidget {
  final double size;
  const _ArtPlaceholder({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: AppTheme.topLevel,
      child: const Icon(
        Icons.music_note_rounded,
        color: AppTheme.textMuted,
        size: 24,
      ),
    );
  }
}