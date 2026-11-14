import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import '../../utils/web_form_factor.dart';

/// Browser only: re-decides phone vs desktop UI whenever the window is resized
/// or the phone rotates, and rebuilds the app when the answer changes.
///
/// The phone and desktop UIs are separate widget trees, so a switch rebuilds
/// the app below this point from scratch (open pages close; playback, queue and
/// sign-in live in providers above it and carry on). Native builds return
/// [child] untouched.
class WebFormFactorScope extends StatefulWidget {
  const WebFormFactorScope({super.key, required this.child});

  final Widget child;

  @override
  State<WebFormFactorScope> createState() => _WebFormFactorScopeState();
}

class _WebFormFactorScopeState extends State<WebFormFactorScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    WebFormFactor.current.addListener(_changed);
    _measure();
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
      WebFormFactor.current.removeListener(_changed);
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() => _measure();

  void _measure() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final view = views.first;
    WebFormFactor.refresh(view.physicalSize.width / view.devicePixelRatio);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return widget.child;
    return KeyedSubtree(key: ValueKey(WebFormFactor.current.value), child: widget.child);
  }
}
