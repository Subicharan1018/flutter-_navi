import 'package:flutter/widgets.dart';

import '../core/theme.dart';

/// Colour contract for player panes (queue, lyrics) so the same widgets work
/// on the living artwork field (white with vibrancy) and inside app chrome
/// such as the desktop side panel (album-tinted tokens).
@immutable
class NowPlayingStyle {
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color pillIdle;
  final Color pillActive;
  final Color pillOnActive;
  final Color rowLifted;

  const NowPlayingStyle({
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.pillIdle,
    required this.pillActive,
    required this.pillOnActive,
    required this.rowLifted,
  });

  /// White-on-artwork: secondary levels stay white (vibrancy) so they read on
  /// any cover colour; active pills invert to solid white.
  static const NowPlayingStyle onArtwork = NowPlayingStyle(
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xB3FFFFFF),
    textMuted: Color(0x80FFFFFF),
    accent: Color(0xFFFFFFFF),
    pillIdle: Color(0x26FFFFFF),
    pillActive: Color(0xF2FFFFFF),
    pillOnActive: Color(0xFF111111),
    rowLifted: Color(0x33FFFFFF),
  );

  factory NowPlayingStyle.fromTokens(AppThemeTokens t) => NowPlayingStyle(
        textPrimary: t.textPrimary,
        textSecondary: t.textSecondary,
        textMuted: t.textMuted,
        accent: t.accent,
        pillIdle: t.bgOverlay,
        pillActive: t.accent,
        pillOnActive: t.onAccent,
        rowLifted: t.bgElevated,
      );

  static NowPlayingStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NowPlayingStyleScope>()?.style ??
      NowPlayingStyle.fromTokens(ThemeTokens.of(context));
}

class NowPlayingStyleScope extends InheritedWidget {
  final NowPlayingStyle style;
  const NowPlayingStyleScope({super.key, required this.style, required super.child});

  @override
  bool updateShouldNotify(NowPlayingStyleScope old) => old.style != style;
}
