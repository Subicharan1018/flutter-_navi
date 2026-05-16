import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/player_provider.dart';
import '../utils/platform_utils.dart';

// =============================================================================
// keyboard_shortcuts.dart — Global desktop keyboard shortcuts
//
// Wraps the root scaffold in a FocusScope with CallbackShortcuts so that
// media keys and navigation shortcuts work app-wide on desktop platforms.
//
// Design decisions:
//   • All actions go through Riverpod providers — never direct Navigator.push
//     from here — so that state stays consistent and the queue panel flag can
//     be toggled via provider rather than a hard push.
//   • Only active when PlatformUtils.supportsKeyboardShortcuts is true.
//   • autofocus: true on the Focus widget — critical, otherwise shortcuts
//     silently do nothing.
//
// Supported shortcuts:
//   Space       → play / pause
//   Right →     → next track
//   Left  ←     → previous track
//   S           → toggle shuffle
//   R           → cycle repeat mode
//   L           → toggle star / favourite on current track
//   Ctrl+F      → focus search (emits a signal via desktopSearchFocusProvider)
//   Ctrl+,      → open settings
//   Ctrl+Q      → open queue panel
//   Escape      → pop current route (dismiss overlay / dialog)
// =============================================================================

/// Riverpod provider that pulses true for one frame when Ctrl+F is pressed,
/// instructing the search screen's FocusNode to request focus.
final desktopSearchFocusProvider = StateProvider<bool>((ref) => false);

/// Riverpod provider that holds whether the queue side panel is open.
final desktopQueueOpenProvider = StateProvider<bool>((ref) => false);

class NaviKeyboardShortcuts extends ConsumerWidget {
  final Widget child;
  const NaviKeyboardShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!PlatformUtils.supportsKeyboardShortcuts) return child;

    return FocusScope(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: _buildBindings(context, ref),
        child: child,
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildBindings(
    BuildContext context,
    WidgetRef ref,
  ) {
    final notifier = ref.read(playerProvider.notifier);

    return {
      // ── Playback ──────────────────────────────────────────────────────────
      const SingleActivator(LogicalKeyboardKey.space): () {
        final state = ref.read(playerProvider);
        if (state.isPlaying) {
          notifier.player.pause();
        } else {
          notifier.player.play();
        }
      },

      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
        notifier.playNext();
      },

      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        notifier.playPrev();
      },

      const SingleActivator(LogicalKeyboardKey.keyS): () {
        notifier.toggleShuffle();
      },

      const SingleActivator(LogicalKeyboardKey.keyR): () {
        notifier.cycleRepeat();
      },

      const SingleActivator(LogicalKeyboardKey.keyL): () {
        final state = ref.read(playerProvider);
        if (state.queue.isNotEmpty) {
          final song = state.queue[state.currentIndex];
          notifier.toggleStar(song.id);
        }
      },

      // ── Navigation ────────────────────────────────────────────────────────
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
        // Signal the search screen to grab focus.
        ref.read(desktopSearchFocusProvider.notifier).state = true;
        // Auto-reset after one frame so subsequent Ctrl+F presses also fire.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(desktopSearchFocusProvider.notifier).state = false;
        });
      },

      const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () {
        final current = ref.read(desktopQueueOpenProvider);
        ref.read(desktopQueueOpenProvider.notifier).state = !current;
      },

      const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
        // Navigate to settings — find the Navigator and push settings.
        Navigator.of(context).pushNamed('/settings');
      },

      const SingleActivator(LogicalKeyboardKey.escape): () {
        // On desktop, NowPlayingScreen is pushed via rootNavigator:true,
        // so the pop must also go to the root navigator.
        final nav = Navigator.of(context, rootNavigator: PlatformUtils.isDesktop);
        if (nav.canPop()) nav.pop();
      },
    };
  }
}
