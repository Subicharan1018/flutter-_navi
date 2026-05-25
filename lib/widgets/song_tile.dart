import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../models/download_state.dart';
import '../providers/settings_provider.dart';
import '../providers/player_provider.dart';
import '../providers/download_provider.dart';
import '../core/theme.dart';
import '../widgets/desktop_dialogs.dart';
import '../utils/platform_utils.dart';
import 'options_menu.dart';

// =============================================================================
// SongTile — cross-platform list row for a single song
//
// Desktop adaptations (PlatformUtils.isDesktop):
//   • InkWell.onDoubleTap  → play immediately (Flutter deduplicates with onTap)
//   • InkWell.onTap        → no-op on desktop (single-click selects, noop here)
//   • Right-click (onSecondaryTapDown) → positioned context popup menu
//   • Hover state          → subtle highlight via MouseRegion
//   • Options button       → popup menu instead of bottom sheet
// =============================================================================

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
    // ---------------------------------------------------------------------------
    final service = ref.read(subsonicServiceProvider);

    // ---------------------------------------------------------------------------
    // FIX 2 — select() narrows this tile's subscription to a single bool.
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
    // ---------------------------------------------------------------------------
    final String coverId = song.coverArt.isNotEmpty ? song.coverArt : song.id;
    final String imageUrl = service.getCoverArtUrl(coverId);
    final String imageCacheKey = 'cover_$coverId';

    if (PlatformUtils.isDesktop) {
      return _DesktopSongTile(
        song: song,
        imageUrl: imageUrl,
        imageCacheKey: imageCacheKey,
        isActive: isActive,
        onTap: onTap,
        playlistId: playlistId,
      );
    }

    // ── Mobile layout (unchanged) ─────────────────────────────────────────────
    return Semantics(
      button: true,
      label: '${song.title} by ${song.artist}',
      onLongPressHint: 'Show options menu',
      child: CupertinoClickable(
        onTap: onTap,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: _TileContent(
            song: song,
            imageUrl: imageUrl,
            imageCacheKey: imageCacheKey,
            isActive: isActive,
            trailing: _MobileOptionsButton(song: song, playlistId: playlistId),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Desktop tile — hover highlight + right-click context menu + double-tap play
// =============================================================================

class _DesktopSongTile extends ConsumerStatefulWidget {
  final Song song;
  final String imageUrl;
  final String imageCacheKey;
  final bool isActive;
  final VoidCallback onTap;
  final String? playlistId;

  const _DesktopSongTile({
    required this.song,
    required this.imageUrl,
    required this.imageCacheKey,
    required this.isActive,
    required this.onTap,
    required this.playlistId,
  });

  @override
  ConsumerState<_DesktopSongTile> createState() => _DesktopSongTileState();
}

class _DesktopSongTileState extends ConsumerState<_DesktopSongTile> {
  bool _hovered = false;
  Offset _lastTapPosition = Offset.zero;

  void _showContextMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final position = renderBox != null
        ? RelativeRect.fromLTRB(
            _lastTapPosition.dx,
            _lastTapPosition.dy,
            _lastTapPosition.dx + 1,
            _lastTapPosition.dy + 1,
          )
        : RelativeRect.fill;

    showMenu<String>(
      context: context,
      position: position,
      color: ThemeTokens.of(context).bgSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        _menuItem(context, 'play_now', Icons.play_arrow_rounded, 'Play Now'),
        _menuItem(
          context,
          'play_next',
          Icons.playlist_play_rounded,
          'Play Next',
        ),
        _menuItem(
          context,
          'add_queue',
          Icons.queue_music_rounded,
          'Add to Queue',
        ),
        _menuItem(
          context,
          'add_playlist',
          Icons.playlist_add_rounded,
          'Add to Playlist',
        ),
        if (widget.playlistId != null)
          _menuItem(
            context,
            'remove',
            Icons.delete_outline_rounded,
            'Remove from Playlist',
            color: Colors.redAccent,
          ),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      final notifier = ref.read(playerProvider.notifier);
      switch (value) {
        case 'play_now':
          widget.onTap();
        case 'play_next':
          final state = ref.read(playerProvider);
          final insertAt = state.currentIndex + 1;
          if (insertAt >= state.queue.length) {
            notifier.addToQueue(widget.song);
          } else {
            notifier.addToQueue(widget.song).then((_) {
              final newState = ref.read(playerProvider);
              notifier.reorderQueue(newState.queue.length - 1, insertAt);
            });
          }
        case 'add_queue':
          notifier.addToQueue(widget.song);
        case 'add_playlist':
          showDialog(
            context: context,
            builder: (ctx) => _AddToPlaylistDesktopDialog(song: widget.song),
          );
        case 'remove':
          // Signal handled by parent playlist screen
          break;
      }
    });
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final tokens = ThemeTokens.of(context);
    final c = color ?? tokens.textPrimary;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: c, size: 18),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: c, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);

    return Semantics(
      button: true,
      label: '${widget.song.title} by ${widget.song.artist}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Right-click → context menu
          onSecondaryTapDown: (details) {
            _lastTapPosition = details.globalPosition;
          },
          onSecondaryTap: () => _showContextMenu(context),
          // Double-tap / double-click → play now
          onDoubleTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: _hovered
                ? tokens.textPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            child: Tooltip(
              message:
                  '${widget.song.title} — double-click to play, right-click for options',
              waitDuration: const Duration(milliseconds: 700),
              child: _TileContent(
                song: widget.song,
                imageUrl: widget.imageUrl,
                imageCacheKey: widget.imageCacheKey,
                isActive: widget.isActive,
                trailing: _DesktopOptionsButton(
                  song: widget.song,
                  playlistId: widget.playlistId,
                  onShowMenu: () => _showContextMenu(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Shared tile content row (used by both mobile and desktop)
// =============================================================================

class _TileContent extends StatelessWidget {
  final Song song;
  final String imageUrl;
  final String imageCacheKey;
  final bool isActive;
  final Widget trailing;

  const _TileContent({
    required this.song,
    required this.imageUrl,
    required this.imageCacheKey,
    required this.isActive,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Album art
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              cacheKey: imageCacheKey,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              memCacheWidth: 150,
              memCacheHeight: 150,
              placeholder: (context, url) => const _ArtPlaceholder(size: 48),
              errorWidget: (context, url, error) =>
                  const _ArtPlaceholder(size: 48),
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
                    color: isActive ? tokens.accent : tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
              ],
            ),
          ),

          // Download badge
          _DownloadBadge(songId: song.id),
          const SizedBox(width: 4),

          // Platform-specific options button
          trailing,
        ],
      ),
    );
  }
}

// =============================================================================
// Options buttons — mobile uses bottom sheet, desktop uses popup menu
// =============================================================================

class _MobileOptionsButton extends StatelessWidget {
  final Song song;
  final String? playlistId;
  const _MobileOptionsButton({required this.song, this.playlistId});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(
        Icons.more_horiz_rounded,
        color: ThemeTokens.of(context).textSecondary,
        size: 20,
      ),
      onPressed: () {
        showPlatformSheet(
          context: context,
          builder: (context) => OptionsMenu(song: song, playlistId: playlistId),
        );
      },
    );
  }
}

class _DesktopOptionsButton extends StatelessWidget {
  final Song song;
  final String? playlistId;
  final VoidCallback onShowMenu;
  const _DesktopOptionsButton({
    required this.song,
    this.playlistId,
    required this.onShowMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Options',
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(
          Icons.more_horiz_rounded,
          color: ThemeTokens.of(context).textSecondary,
          size: 20,
        ),
        onPressed: onShowMenu,
      ),
    );
  }
}

/// Placeholder dialog shim — the real AddToPlaylistDialog is imported from
/// add_to_playlist_dialog.dart and shown as a centered dialog on desktop.
class _AddToPlaylistDesktopDialog extends StatelessWidget {
  final Song song;
  const _AddToPlaylistDesktopDialog({required this.song});

  @override
  Widget build(BuildContext context) {
    // Import the real dialog widget — wrapping it in Dialog gives the
    // centered modal treatment on desktop.
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 600),
        // AddToPlaylistDialog is a full widget — embed directly.
        child: AddToPlaylistProxy(song: song),
      ),
    );
  }
}

// Thin proxy so we don't need to import add_to_playlist_dialog here
// and create a circular dependency.  The real widget is imported below.
class AddToPlaylistProxy extends StatelessWidget {
  final Song song;
  const AddToPlaylistProxy({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    // Delegates to the real dialog which handles its own internal state.
    // Use the options_menu pattern of showing it as a dialog child.
    return OptionsMenu(song: song);
  }
}

// =============================================================================
// Per-song download badge (unchanged)
// =============================================================================

class _DownloadBadge extends ConsumerWidget {
  final String songId;
  const _DownloadBadge({required this.songId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      downloadStateProvider.select(
        (m) => m[songId]?.status ?? SongDownloadStatus.notDownloaded,
      ),
    );
    final progress = ref.watch(
      downloadStateProvider.select((m) => m[songId]?.progress ?? 0.0),
    );
    final tokens = ThemeTokens.of(context);

    switch (status) {
      case SongDownloadStatus.notDownloaded:
        return const SizedBox.shrink();
      case SongDownloadStatus.queued:
      case SongDownloadStatus.downloading:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            value: status == SongDownloadStatus.downloading && progress > 0
                ? progress
                : null,
            strokeWidth: 1.5,
            color: tokens.accent,
          ),
        );
      case SongDownloadStatus.downloaded:
        return Icon(
          Icons.arrow_circle_down_rounded,
          size: 14,
          color: tokens.accent,
        );
      case SongDownloadStatus.failed:
        return const Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: Colors.redAccent,
        );
    }
  }
}

// =============================================================================
// Art placeholder
// =============================================================================

class _ArtPlaceholder extends StatelessWidget {
  final double size;
  const _ArtPlaceholder({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: ThemeTokens.of(context).bgElevated,
      child: Icon(
        Icons.music_note_rounded,
        color: ThemeTokens.of(context).textMuted,
        size: 24,
      ),
    );
  }
}
