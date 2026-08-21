import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../models/lyric_line.dart';

/// Teleprompter view for Case B — plain text with no timestamps.
///
/// Formatted with Apple Music glowing typography and graceful pacing.
class PlainTextView extends StatefulWidget {
  final SyncedLyrics lyrics;
  final Song song;

  const PlainTextView({super.key, required this.lyrics, required this.song});

  @override
  State<PlainTextView> createState() => _PlainTextViewState();
}

class _PlainTextViewState extends State<PlainTextView> {
  late final ScrollController _scroll;
  Timer? _timer;

  /// Line height for Apple Music large typography.
  static const double _lineHeight = 64.0;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _startTeleprompter();
  }

  void _startTeleprompter() {
    final lines = widget.lyrics.lines;
    if (lines.isEmpty || widget.song.duration <= 0) return;

    // Interval between advancing one line smoothly.
    final intervalMs = ((widget.song.duration * 1000) / lines.length).round();

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted) return;
      if (!_scroll.hasClients) return;
      final next = _scroll.offset + _lineHeight;
      _scroll.animateTo(
        next.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;

    return Stack(
      children: [
        // Top & Bottom Shader Fade Mask for smooth Apple Music text fade
        ShaderMask(
          shaderCallback: (Rect bounds) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.08, 0.92, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(36, 48, 36, 160),
            itemCount: lines.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                lines[i].text,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.35,
                  letterSpacing: -0.6,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.50),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // "Unsynced Lyrics" Badge
        Positioned(
          top: 12,
          right: 24,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.text_fields_rounded,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.70),
                ),
                const SizedBox(width: 5),
                Text(
                  'Lyrics',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.80),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
