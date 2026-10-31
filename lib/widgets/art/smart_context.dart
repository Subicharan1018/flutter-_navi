import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../features/flow/logic/flow_controller.dart' show flowPlaylistName;
import 'generated_cover.dart';
import 'navi_icons.dart';

// =============================================================================
// smart_context.dart — where a queue came from, when the server built it.
//
// A Smart Shuffle / Flow / Weekly Mix / Discover queue is chosen for you, so
// Now Playing says so: a "Playing from Smart Shuffle" pill over the artwork and
// the app's own generated cover (the signal / waveform art) faintly behind it,
// crossfading as songs change. The album cover stays the big, primary image.
// =============================================================================

enum SmartKind { smartShuffle, flow, weekly, discover }

class SmartContext {
  final SmartKind kind;
  final String label;
  final NaviGlyph glyph;
  const SmartContext(this.kind, this.label, this.glyph);

  /// The context for the queue named [playlistName] (what `setQueue` /
  /// `playPlaylist` were given), or null for an ordinary queue.
  static SmartContext? of(String? playlistName) => switch (playlistName) {
        'Smart Shuffle' => const SmartContext(SmartKind.smartShuffle, 'Smart Shuffle', NaviGlyph.smartShuffle),
        flowPlaylistName => const SmartContext(SmartKind.flow, 'Flow', NaviGlyph.flow),
        'Weekly Mix' => const SmartContext(SmartKind.weekly, 'Your Weekly Mix', NaviGlyph.calendar),
        'New in Your Library' => const SmartContext(SmartKind.discover, 'New in Your Library', NaviGlyph.signal),
        _ => null,
      };
}

/// The pill: glyph, "Playing from", and the source in bold.
class SmartContextPill extends StatelessWidget {
  final SmartContext context_;
  const SmartContextPill({super.key, required SmartContext context}) : context_ = context;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      label: 'Playing from ${context_.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs + 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(Radii.capsule),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NaviIcon(context_.glyph, size: 14, color: Colors.white),
            const SizedBox(width: Space.xs + 2),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Playing from ', style: t.caption1.copyWith(color: Colors.white70)),
                  TextSpan(
                    text: context_.label,
                    style: t.caption1.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's generated cover for this context, drawn behind everything else at
/// low strength. One seed per song so it shifts as the queue advances; the
/// [AnimatedSwitcher] crossfades between them.
class SmartBackdrop extends StatelessWidget {
  final SmartContext context_;
  final String songId;
  const SmartBackdrop({super.key, required SmartContext context, required this.songId}) : context_ = context;

  @override
  Widget build(BuildContext context) {
    final seed = coverSeed(context_.label, [songId]);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
              ? Duration.zero
              : const Duration(milliseconds: 700),
          child: Opacity(
            key: ValueKey(seed),
            opacity: 0.16,
            child: SizedBox.expand(child: GeneratedCover.seeded(seed: seed)),
          ),
        ),
      ),
    );
  }
}
