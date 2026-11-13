import 'package:web/web.dart' as web;

import 'web_env.dart';

/// Reads the browser's device hints. Never throws: an odd browser just looks
/// like a desktop with a mouse.
BrowserInfo? readBrowserInfo() {
  try {
    final nav = web.window.navigator;
    return BrowserInfo(
      userAgent: nav.userAgent,
      maxTouchPoints: nav.maxTouchPoints,
      finePointer: web.window.matchMedia('(pointer: fine)').matches,
    );
  } catch (_) {
    return const BrowserInfo();
  }
}

/// Reloads the page: the cleanest reset after signing out (every provider,
/// poll and socket of the old session goes with it).
void reloadPage() => web.window.location.reload();
