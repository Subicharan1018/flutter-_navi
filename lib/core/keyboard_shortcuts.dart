import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../providers/player_provider.dart';
import '../utils/platform_utils.dart';

// =============================================================================
// keyboard_shortcuts.dart — Global desktop keyboard shortcuts & Hotkey Guard
// =============================================================================

final desktopSearchFocusProvider = StateProvider<bool>((ref) => false);
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

  bool _isEditingText() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null) return false;
    // Check if the current focused widget is an editable text field
    final widget = primaryFocus.context?.widget;
    return widget is EditableText;
  }

  Map<ShortcutActivator, VoidCallback> _buildBindings(
    BuildContext context,
    WidgetRef ref,
  ) {
    final notifier = ref.read(playerProvider.notifier);

    return {
      // ── Playback Shortcuts (Guarded against text field typing) ─────────────
      const SingleActivator(LogicalKeyboardKey.space): () {
        if (_isEditingText()) return;
        final state = ref.read(playerProvider);
        if (state.isPlaying) {
          notifier.player.pause();
        } else {
          notifier.player.play();
        }
      },

      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
        if (_isEditingText()) return;
        notifier.playNext();
      },

      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        if (_isEditingText()) return;
        notifier.playPrev();
      },

      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        if (_isEditingText()) return;
        final currentVol = notifier.player.volume;
        notifier.player.setVolume((currentVol + 0.05).clamp(0.0, 1.0));
      },

      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        if (_isEditingText()) return;
        final currentVol = notifier.player.volume;
        notifier.player.setVolume((currentVol - 0.05).clamp(0.0, 1.0));
      },

      const SingleActivator(LogicalKeyboardKey.keyS): () {
        if (_isEditingText()) return;
        notifier.toggleShuffle();
      },

      const SingleActivator(LogicalKeyboardKey.keyR): () {
        if (_isEditingText()) return;
        notifier.cycleRepeat();
      },

      const SingleActivator(LogicalKeyboardKey.keyL): () {
        if (_isEditingText()) return;
        final state = ref.read(playerProvider);
        if (state.queue.isNotEmpty) {
          final song = state.queue[state.currentIndex];
          notifier.toggleStar(song.id);
        }
      },

      const SingleActivator(LogicalKeyboardKey.keyM): () {
        if (_isEditingText()) return;
        final currentVol = notifier.player.volume;
        if (currentVol > 0) {
          notifier.player.setVolume(0.0);
        } else {
          notifier.player.setVolume(1.0);
        }
      },

      // Native Media Keys Support
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () {
        final state = ref.read(playerProvider);
        if (state.isPlaying) {
          notifier.player.pause();
        } else {
          notifier.player.play();
        }
      },
      const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () {
        notifier.playNext();
      },
      const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () {
        notifier.playPrev();
      },

      // ── Navigation Shortcuts ──────────────────────────────────────────────
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
        ref.read(desktopSearchFocusProvider.notifier).state = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(desktopSearchFocusProvider.notifier).state = false;
        });
      },

      const SingleActivator(LogicalKeyboardKey.keyQ, control: true): () {
        final current = ref.read(desktopQueueOpenProvider);
        ref.read(desktopQueueOpenProvider.notifier).state = !current;
      },

      const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
        Navigator.of(context).pushNamed('/settings');
      },

      const SingleActivator(LogicalKeyboardKey.escape): () {
        final nav = Navigator.of(
          context,
          rootNavigator: PlatformUtils.isDesktop,
        );
        if (nav.canPop()) nav.pop();
      },
    };
  }
}
