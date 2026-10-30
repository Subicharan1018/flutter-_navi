import 'package:flutter/gestures.dart' show kBackMouseButton, kForwardMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../providers/player_provider.dart';
import '../utils/platform_utils.dart';
import '../widgets/ui/voice_search_button.dart';

// =============================================================================
// keyboard_shortcuts.dart — global keys for Windows / Linux / macOS and for
// Android TV remotes.
//
//   Everywhere (desktop + TV)
//     Play/Pause, Play, Pause, Next, Previous  media keys
//     Rewind / Fast-forward                    media keys, ∓/± 10 s
//     Voice / Search key on a TV remote        starts dictation in Search
//
//   Desktop only (arrows are the D-pad's job on a TV)
//     Space            play / pause
//     ← →              seek ∓/± 5 s        Ctrl+← →   previous / next
//     ↑ ↓              volume ± 5 %        M          mute
//     S R L            shuffle, repeat, like the current song
//     Ctrl+F or /      type in Search      Ctrl+1…6   switch tab
//     Ctrl+,           Settings            Esc / Alt+←  back
//     mouse back / forward buttons         back
//
// Letter and arrow keys never fire while a text field has the keyboard.
// =============================================================================

/// What the shell lets the keys do to navigation.
class ShellCommands {
  /// Shows Search (the remote's voice key, which then dictates).
  final VoidCallback openSearch;

  /// Shows Search with the caret in its field.
  final VoidCallback focusSearch;
  final VoidCallback openSettings;
  final void Function(int index) selectTab;

  /// Pops one level; returns false when there is nothing to go back to.
  final bool Function() goBack;

  const ShellCommands({
    required this.openSearch,
    required this.focusSearch,
    required this.openSettings,
    required this.selectTab,
    required this.goBack,
  });
}

class NaviKeyboardShortcuts extends ConsumerWidget {
  final Widget child;
  final ShellCommands? commands;

  const NaviKeyboardShortcuts({super.key, required this.child, this.commands});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!PlatformUtils.isDesktop && !PlatformUtils.isTv) return child;

    return FocusScope(
      autofocus: true,
      child: Listener(
        onPointerDown: (e) {
          if (commands == null) return;
          if (e.buttons == kBackMouseButton) commands!.goBack();
          if (e.buttons == kForwardMouseButton) return; // no forward stack
        },
        child: CallbackShortcuts(
          bindings: buildNaviBindings(ref, commands, desktop: PlatformUtils.isDesktop),
          child: child,
        ),
      ),
    );
  }
}

bool _isEditingText() {
  final widget = FocusManager.instance.primaryFocus?.context?.widget;
  return widget is EditableText;
}

/// The key map, split out so tests can drive it without a window.
Map<ShortcutActivator, VoidCallback> buildNaviBindings(
  WidgetRef ref,
  ShellCommands? commands, {
  required bool desktop,
}) {
  PlayerNotifier notifier() => ref.read(playerProvider.notifier);
  AudioPlayer player() => notifier().player;

  void playPause() => ref.read(playerProvider).isPlaying ? player().pause() : player().play();

  void seekBy(Duration delta) {
    final p = player();
    final target = p.position + delta;
    final end = p.duration;
    final clamped = target < Duration.zero ? Duration.zero : (end != null && target > end ? end : target);
    p.seek(clamped);
  }

  void volumeBy(double delta) => player().setVolume((player().volume + delta).clamp(0.0, 1.0));

  // Keys that type or move a caret are left alone while a field is focused.
  VoidCallback unlessTyping(VoidCallback action) => () {
        if (!_isEditingText()) action();
      };

  final bindings = <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause): playPause,
    const SingleActivator(LogicalKeyboardKey.mediaPlay): () => player().play(),
    const SingleActivator(LogicalKeyboardKey.mediaPause): () => player().pause(),
    const SingleActivator(LogicalKeyboardKey.mediaTrackNext): () => notifier().playNext(),
    const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious): () => notifier().playPrev(),
    const SingleActivator(LogicalKeyboardKey.mediaFastForward): () => seekBy(const Duration(seconds: 10)),
    const SingleActivator(LogicalKeyboardKey.mediaRewind): () => seekBy(const Duration(seconds: -10)),
  };

  // The remote's microphone: open Search and start dictating.
  void voiceKey() {
    commands?.openSearch();
    voiceKeyPresses.value++;
  }

  bindings[const SingleActivator(LogicalKeyboardKey.speechInputToggle)] = voiceKey;
  bindings[const SingleActivator(LogicalKeyboardKey.browserSearch)] = voiceKey;

  if (!desktop) return bindings;

  bindings.addAll({
    const SingleActivator(LogicalKeyboardKey.space): unlessTyping(playPause),
    const SingleActivator(LogicalKeyboardKey.arrowRight): unlessTyping(() => seekBy(const Duration(seconds: 5))),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): unlessTyping(() => seekBy(const Duration(seconds: -5))),
    const SingleActivator(LogicalKeyboardKey.arrowUp): unlessTyping(() => volumeBy(0.05)),
    const SingleActivator(LogicalKeyboardKey.arrowDown): unlessTyping(() => volumeBy(-0.05)),
    const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () => notifier().playNext(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () => notifier().playPrev(),
    const SingleActivator(LogicalKeyboardKey.keyS): unlessTyping(() => notifier().toggleShuffle()),
    const SingleActivator(LogicalKeyboardKey.keyR): unlessTyping(() => notifier().cycleRepeat()),
    const SingleActivator(LogicalKeyboardKey.keyL): unlessTyping(() {
      final s = ref.read(playerProvider);
      if (s.queue.isNotEmpty) notifier().toggleStar(s.queue[s.currentIndex].id);
    }),
    const SingleActivator(LogicalKeyboardKey.keyM): unlessTyping(() => player().setVolume(player().volume > 0 ? 0 : 1)),
  });

  if (commands != null) {
    bindings.addAll({
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): commands.focusSearch,
      const SingleActivator(LogicalKeyboardKey.slash): unlessTyping(commands.focusSearch),
      const SingleActivator(LogicalKeyboardKey.comma, control: true): commands.openSettings,
      const SingleActivator(LogicalKeyboardKey.escape): () => commands.goBack(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => commands.goBack(),
      for (var i = 0; i < 6; i++)
        SingleActivator(<LogicalKeyboardKey>[
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit2,
          LogicalKeyboardKey.digit3,
          LogicalKeyboardKey.digit4,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit6,
        ][i], control: true): () => commands.selectTab(i),
    });
  }
  return bindings;
}
