import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/player_provider.dart';
import '../../utils/platform_utils.dart';
import '../../utils/web_env.dart' show applyWebUpdate, onWebUpdateReady;

/// Browser only: true once a newer build of the web app is live
/// (web/flutter_bootstrap.js compares build ids on load, focus and every
/// 30 minutes).
final ValueNotifier<bool> webUpdateReady = ValueNotifier(false);

/// The web app has no self-updater: the page is the app. When a new build is
/// deployed this shows a quiet "New version · Reload" pill, and reloads on its
/// own when the page is hidden and nothing is playing, so an idle tab or
/// installed PWA is current the next time it is opened. Playback is never cut
/// off by an update. Native builds return [child] untouched.
class WebUpdatePrompt extends ConsumerStatefulWidget {
  const WebUpdatePrompt({super.key, required this.child, this.apply = applyWebUpdate, this.enabled = kIsWeb});

  final Widget child;

  /// Switches to the new build (a page reload).
  @visibleForTesting
  final VoidCallback apply;

  /// Web only; tests turn it on.
  @visibleForTesting
  final bool enabled;

  @override
  ConsumerState<WebUpdatePrompt> createState() => _WebUpdatePromptState();
}

class _WebUpdatePromptState extends ConsumerState<WebUpdatePrompt> {
  AppLifecycleListener? _lifecycle;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    if (kIsWeb) onWebUpdateReady(() => webUpdateReady.value = true);
    _lifecycle = AppLifecycleListener(onHide: _applyIfIdle);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  /// Hidden tab and nothing playing: nobody sees the reload happen.
  void _applyIfIdle() {
    if (!webUpdateReady.value) return;
    if (ref.read(playerProvider.select((s) => s.isPlaying))) return;
    widget.apply();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return ValueListenableBuilder<bool>(
      valueListenable: webUpdateReady,
      child: widget.child,
      builder: (context, ready, child) => Stack(
        children: [
          child!,
          if (ready && !_dismissed)
            Positioned(
              left: 0,
              right: 0,
              // Above the phone's mini player + tab bar, or the desktop player bar.
              bottom: MediaQuery.paddingOf(context).bottom + (PlatformUtils.isDesktop ? 104 : 168),
              child: Center(
                child: _UpdatePill(onReload: widget.apply, onDismiss: () => setState(() => _dismissed = true)),
              ),
            ),
        ],
      ),
    );
  }
}

class _UpdatePill extends StatelessWidget {
  const _UpdatePill({required this.onReload, required this.onDismiss});

  final VoidCallback onReload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    // Above the Navigator, so no Material gives it a text style: set one, or
    // Flutter's debug fallback (yellow double underline) shows.
    return DefaultTextStyle(
      style: t.footnote,
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.xs, Space.xs, Space.xs),
          decoration: BoxDecoration(
            color: t.bgSurfaceOpaque,
            borderRadius: BorderRadius.circular(Radii.capsule),
            border: Border.all(color: t.outline, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('New version available', style: t.footnote.copyWith(color: t.textPrimary)),
              const SizedBox(width: Space.sm),
              CupertinoClickable(
                onTap: onReload,
                focusRadius: Radii.capsule,
                semanticLabel: 'Reload to update',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
                  decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(Radii.capsule)),
                  child: Text(
                    'Reload',
                    style: t.footnote.copyWith(color: t.onAccent, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              CupertinoClickable(
                onTap: onDismiss,
                focusRadius: Radii.capsule,
                semanticLabel: 'Not now',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
                  child: Text('Later', style: t.footnote),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
