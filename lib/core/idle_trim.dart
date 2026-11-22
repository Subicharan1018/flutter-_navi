import 'dart:async';

import 'package:flutter/widgets.dart';

/// Gives memory back while the app is out of sight.
///
/// A minimised or tray-hidden window keeps the decoded covers of the last
/// screen (up to 160 MB on desktop) for nothing. After [after] without being
/// visible the image cache is emptied; coming back decodes only what the screen
/// shows. The window being visible again cancels it.
class IdleTrim with WidgetsBindingObserver {
  IdleTrim({this.after = const Duration(seconds: 60), VoidCallback? trim})
      : _trim = trim ?? _trimImages;

  final Duration after;
  final VoidCallback _trim;
  Timer? _timer;

  static void _trimImages() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }

  /// Starts listening; returns the observer so a test or a shutdown can [dispose] it.
  IdleTrim install() {
    WidgetsBinding.instance.addObserver(this);
    return this;
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.inactive) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer(after, () {
        _timer = null;
        _trim();
      });
    }
  }
}
