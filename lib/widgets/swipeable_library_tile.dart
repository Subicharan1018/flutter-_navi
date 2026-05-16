import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../core/theme.dart';
import 'swipe_action_background.dart';

// =============================================================================
// SwipeableLibraryTile
//
// Generic Dismissible wrapper for library list tiles.
// Right swipe  (startToEnd) — always enabled: add songs to queue.
// Left  swipe  (endToStart) — songs only (pass onSwipeLeft: null to disable):
//   toggles star/favorite with undo snackbar.
//
// confirmDismiss always returns false — tiles are never removed from the list.
// =============================================================================

class SwipeableLibraryTile extends ConsumerWidget {
  const SwipeableLibraryTile({
    super.key,
    required this.dismissKey,
    required this.child,
    /// Called when user swipes right. Should add the relevant song(s) to queue.
    required this.onSwipeRight,
    /// Null = right-swipe only (albums, playlists). Non-null = also enable
    /// left-swipe for favorite toggle on song tiles.
    this.onSwipeLeft,
    /// Whether the item is already starred — drives the left icon.
    this.isStarred = false,
    /// Label shown below the right-swipe icon (e.g. "Queue").
    this.rightLabel = 'Queue',
    /// Label shown below the left-swipe icon.
    this.leftLabel,
  });

  final String dismissKey;
  final Widget child;
  final Future<void> Function() onSwipeRight;
  final Future<void> Function()? onSwipeLeft;
  final bool isStarred;
  final String rightLabel;
  final String? leftLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    final hasLeft = onSwipeLeft != null;

    return Dismissible(
      key: ValueKey(dismissKey),
      direction: hasLeft
          ? DismissDirection.horizontal
          : DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        HapticFeedback.mediumImpact();
        if (direction == DismissDirection.startToEnd) {
          await onSwipeRight();
        } else if (hasLeft) {
          await onSwipeLeft!();
          // ignore: use_build_context_synchronously — guarded by mounted below
          if (context.mounted) _showFavoriteSnackbar(context, ref);
        }
        return false; // never actually remove the tile
      },
      // ── Right background (add to queue) ──────────────────────────────────
      background: SwipeActionBackground(
        side: SwipeActionSide.left,
        icon: Icons.add_rounded,
        label: rightLabel,
        color: tokens.accent,
      ),
      // ── Left background (favorite toggle) — only shown when enabled ───────
      secondaryBackground: hasLeft
          ? SwipeActionBackground(
              side: SwipeActionSide.right,
              icon: isStarred
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: leftLabel ?? (isStarred ? 'Unfave' : 'Favorite'),
              color: Colors.pinkAccent,
            )
          : null,
      child: child,
    );
  }

  void _showFavoriteSnackbar(BuildContext context, WidgetRef ref) {
    if (!context.mounted) return;
    final wasStarred = isStarred;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(wasStarred ? 'Removed from favorites' : 'Added to favorites'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            // Undo: toggle back by calling onSwipeLeft again
            await onSwipeLeft?.call();
          },
        ),
      ),
    );
  }
}

// =============================================================================
// Helper — add a list of songs to the queue.
// If the queue is currently empty, starts playback instead of just appending.
// =============================================================================

Future<void> addSongsToQueue({
  required List<Song> songs,
  required PlayerNotifier notifier,
  required PlayerState playerState,
  required BuildContext context,
  String? label, // e.g. album/playlist name for the snackbar
}) async {
  if (songs.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No songs to add'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  // If nothing is playing, use setQueue to start playback immediately.
  if (playerState.queue.isEmpty) {
    await notifier.setQueue(songs, 0);
  } else {
    for (final song in songs) {
      await notifier.addToQueue(song);
    }
  }

  if (context.mounted) {
    final count = songs.length;
    final name = label != null ? '"$label"' : null;
    final msg = name != null
        ? '$name added to queue ($count song${count == 1 ? '' : 's'})'
        : 'Added $count song${count == 1 ? '' : 's'} to queue';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
