import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/song.dart';
import '../models/lyric_line.dart';

/// Teleprompter view for Case B — plain text with no timestamps.
///
/// All lines are shown at 0.70 opacity. A [Timer.periodic] advances the
/// scroll position at a rate derived from `song.duration / lines.length`,
/// giving a rough sense of pacing without inventing fake timestamps.
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

  /// Estimated height for each lyric line including padding.
  static const double _lineHeight = 52.0;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _startTeleprompter();
  }

  void _startTeleprompter() {
    final lines = widget.lyrics.lines;
    if (lines.isEmpty || widget.song.duration <= 0) return;

    // Interval between advancing one line.
    final intervalMs =
        ((widget.song.duration * 1000) / lines.length).round();

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted) return;
      if (!_scroll.hasClients) return;
      final next = _scroll.offset + _lineHeight;
      _scroll.animateTo(
        next.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 600),
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
        ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 120),
          itemCount: lines.length,
          itemBuilder: (_, i) => SizedBox(
            height: _lineHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                lines[i].text,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                  color: Color(0xB3FFFFFF), // 0.70 opacity
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
        // "Plain Text" badge
        Positioned(
          top: 12,
          right: 16,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Plain Text',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
