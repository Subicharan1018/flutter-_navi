import '../widgets/table/song_table.dart' show SongTableSliver;
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

  /// Re-opens the page Back left (Alt+→, the mouse's forward button).
  final VoidCallback? goForward;

  const ShellCommands({
    required this.openSearch,
    required this.focusSearch,
    required this.openSettings,
    required this.selectTab,
    required this.goBack,
    this.goForward,
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
          if (e.buttons == kForwardMouseButton) commands!.goForward?.call();
        },
        child: NaviKeyBindings(
          bindings: buildNaviBindings(ref, commands, desktop: PlatformUtils.isDesktop),
          child: child,
        ),
      ),
    );
  }
}

/// Runs the key map. Unlike [CallbackShortcuts] it can pass a key on: a key
/// that types or moves a caret must reach the focused field, and a shortcut
/// that merely did nothing would still have swallowed it.
class NaviKeyBindings extends StatelessWidget {
  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;

  const NaviKeyBindings({super.key, required this.bindings, required this.child});

  static final _typingKeys = {
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyR,
    LogicalKeyboardKey.keyL,
    LogicalKeyboardKey.keyM,
    LogicalKeyboardKey.slash,
  };

  static bool _isEditingText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText || context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static bool _belongsToField(ShortcutActivator activator) =>
      activator is SingleActivator && !activator.control && !activator.alt && _typingKeys.contains(activator.trigger);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    for (final entry in bindings.entries) {
      if (!entry.key.accepts(event, HardwareKeyboard.instance)) continue;
      if (_belongsToField(entry.key) && _isEditingText()) return KeyEventResult.ignored;
      entry.value();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: child);
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
    const SingleActivator(LogicalKeyboardKey.space): playPause,
    const SingleActivator(LogicalKeyboardKey.arrowRight): () => seekBy(const Duration(seconds: 5)),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => seekBy(const Duration(seconds: -5)),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => volumeBy(0.05),
    const SingleActivator(LogicalKeyboardKey.arrowDown): () => volumeBy(-0.05),
    const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () => notifier().playNext(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () => notifier().playPrev(),
    const SingleActivator(LogicalKeyboardKey.keyS): () => notifier().toggleShuffle(),
    const SingleActivator(LogicalKeyboardKey.keyR): () => notifier().cycleRepeat(),
    const SingleActivator(LogicalKeyboardKey.keyL): () {
      final s = ref.read(playerProvider);
      if (s.queue.isNotEmpty) notifier().toggleStar(s.queue[s.currentIndex].id);
    },
    const SingleActivator(LogicalKeyboardKey.keyM): () => player().setVolume(player().volume > 0 ? 0 : 1),
  });

  if (commands != null) {
    bindings.addAll({
      // Ctrl+F finds in the list on screen; with none, it goes to Search.
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
        if (!SongTableSliver.tryFind()) commands.focusSearch();
      },
      const SingleActivator(LogicalKeyboardKey.slash): commands.focusSearch,
      const SingleActivator(LogicalKeyboardKey.comma, control: true): commands.openSettings,
      const SingleActivator(LogicalKeyboardKey.escape): () => commands.goBack(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => commands.goBack(),
      if (commands.goForward != null) const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): commands.goForward!,
      // Ctrl+K: the top bar's search field.
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): commands.focusSearch,
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
