import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/player_provider.dart';
import '../utils/platform_utils.dart';

/// Saves the queue and position the moment the app is left: Android sends the
/// app to the background, Windows closes (or hides) the window. The debounced
/// save in the player covers everything else; this covers the exit.
///
/// Read it once at start-up. It holds no state of its own.
final queuePersistenceBootstrapProvider = Provider<void>((ref) {
  ref.read(playerProvider.notifier); // built now, so last session's queue is back before the first screen
  final guard = _FlushOnExit(() => ref.read(playerProvider.notifier).flushPersist());
  WidgetsBinding.instance.addObserver(guard);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(guard));
  if (!kIsWeb && PlatformUtils.isDesktop) {
    windowManager.addListener(guard);
    ref.onDispose(() => windowManager.removeListener(guard));
  }
});

class _FlushOnExit with WidgetsBindingObserver, WindowListener {
  _FlushOnExit(this._flush);
  final VoidCallback _flush;

  void _safe() {
    try {
      _flush();
    } catch (_) {} // bookkeeping never breaks the app
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _safe();
    }
  }

  @override
  void onWindowClose() => _safe();
}
