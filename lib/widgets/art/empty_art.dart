import 'package:flutter/material.dart';

import '../../core/theme.dart';

// =============================================================================
// Original empty-state illustrations, drawn in code with the theme's own
// text tones (so they follow the album-tinted ground). Each is a quiet
// monochrome line drawing on a 160 x 120 canvas.
// =============================================================================

enum EmptyArtKind {
  /// A vinyl with nothing on it yet — empty library or playlist.
  record,

  /// A heart outline made of a sound wave — no favourites.
  heart,

  /// A flat signal with one tick — no stats / replay data yet.
  signal,

  /// A broken-off cable — nothing configured or connected.
  cable,
}

class EmptyArt extends StatelessWidget {
  final EmptyArtKind kind;
  final double width;

  const EmptyArt(this.kind, {super.key, this.width = 160});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(width, width * 0.75),
        painter: EmptyArtPainter(kind, t.textMuted, t.textSecondary),
      ),
    );
  }
}

/// Illustration plus a title and an invitation, centred. The replacement for
/// the old icon + grey line empty states.
class ArtEmptyState extends StatelessWidget {
  final EmptyArtKind art;
  final String title;
  final String? message;
  final Widget? action;

  const ArtEmptyState({
    super.key,
    required this.art,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(child: EmptyArt(art)),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: naviText(20, FontWeight.w700, t.textPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: naviText(14, FontWeight.w400, t.textSecondary, height: 1.4),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class EmptyArtPainter extends CustomPainter {
  final EmptyArtKind kind;
  final Color dim;
  final Color bright;
  const EmptyArtPainter(this.kind, this.dim, this.bright);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 160, size.height / 120);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2
      ..color = dim.withValues(alpha: 0.55);
    final strong = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3
      ..color = bright;

    switch (kind) {
      case EmptyArtKind.record:
        const c = Offset(70, 60);
        for (var i = 0; i < 4; i++) {
          canvas.drawCircle(c, 50 - i * 10.0, i == 0 ? strong : faint);
        }
        canvas.drawCircle(c, 5, Paint()..color = bright);
        // Tonearm resting off the record.
        canvas.drawPath(
          Path()
            ..moveTo(138, 18)
            ..lineTo(138, 70)
            ..lineTo(122, 94),
          strong,
        );
        canvas.drawCircle(const Offset(138, 18), 4, Paint()..color = bright);
      case EmptyArtKind.heart:
        final heart = Path()
          ..moveTo(80, 100)
          ..cubicTo(28, 66, 34, 22, 62, 22)
          ..cubicTo(72, 22, 78, 28, 80, 34)
          ..cubicTo(82, 28, 88, 22, 98, 22)
          ..cubicTo(126, 22, 132, 66, 80, 100)
          ..close();
        canvas.drawPath(heart, faint);
        // A pulse crossing the heart.
        canvas.drawPath(
          Path()
            ..moveTo(16, 64)
            ..lineTo(58, 64)
            ..lineTo(68, 44)
            ..lineTo(82, 84)
            ..lineTo(92, 64)
            ..lineTo(144, 64),
          strong,
        );
      case EmptyArtKind.signal:
        canvas.drawLine(const Offset(14, 84), const Offset(146, 84), faint);
        const heights = [10.0, 22.0, 14.0, 40.0, 18.0, 28.0, 8.0];
        for (var i = 0; i < heights.length; i++) {
          final x = 28.0 + i * 17;
          final top = i == 3;
          canvas.drawLine(
            Offset(x, 84),
            Offset(x, 84 - heights[i]),
            top ? strong : faint,
          );
        }
        canvas.drawCircle(const Offset(79, 40), 4, Paint()..color = bright);
      case EmptyArtKind.cable:
        canvas.drawPath(
          Path()
            ..moveTo(12, 84)
            ..cubicTo(40, 84, 40, 50, 66, 50),
          strong,
        );
        canvas.drawPath(
          Path()
            ..moveTo(148, 36)
            ..cubicTo(122, 36, 122, 70, 98, 70),
          strong,
        );
        // The gap between the two plugs.
        canvas.drawLine(const Offset(66, 42), const Offset(66, 58), strong);
        canvas.drawLine(const Offset(98, 62), const Offset(98, 78), strong);
        // Dashes where the signal used to pass.
        canvas.drawLine(const Offset(74, 56), const Offset(80, 56), faint);
        canvas.drawLine(const Offset(80, 64), const Offset(86, 64), faint);
    }
  }

  @override
  bool shouldRepaint(EmptyArtPainter old) =>
      old.kind != kind || old.dim != dim || old.bright != bright;
}
