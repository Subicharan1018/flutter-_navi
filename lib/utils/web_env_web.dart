import 'dart:js_interop';

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

/// `window.navivibeUpdate`, set up by web/flutter_bootstrap.js.
@JS('navivibeUpdate')
external _WebUpdate? get _update;

extension type _WebUpdate(JSObject _) implements JSObject {
  external bool get ready;
  external JSFunction get apply;
}

/// Calls [onReady] once flutter_bootstrap.js finds a newer build live (on
/// load, on focus, every 30 minutes). At once if it already has.
void onWebUpdateReady(void Function() onReady) {
  try {
    if (_update?.ready ?? false) {
      onReady();
      return;
    }
    web.window.addEventListener('navivibe-update', ((web.Event _) => onReady()).toJS);
  } catch (_) {}
}

/// Switches to the newer build (a reload: app code is fetched past the caches).
void applyWebUpdate() {
  try {
    final u = _update;
    if (u != null) {
      u.apply.callAsFunction();
      return;
    }
  } catch (_) {}
  web.window.location.reload();
}
