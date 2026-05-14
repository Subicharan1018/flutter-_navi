import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Empty state card shown when no lyrics are found in Subsonic or LRCLIB.
class NoLyricsCard extends StatefulWidget {
  const NoLyricsCard({super.key});

  @override
  State<NoLyricsCard> createState() => _NoLyricsCardState();
}

class _NoLyricsCardState extends State<NoLyricsCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Icon(
                Icons.music_note_rounded,
                size: 72,
                color: Colors.white.withOpacity(0.25),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No lyrics available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.55),
                letterSpacing: -0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This song doesn\'t have lyrics\nin Subsonic or LRCLIB.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.white.withOpacity(0.30),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 500.ms, curve: Curves.easeOut)
        .slideY(begin: 0.08, end: 0, duration: 500.ms, curve: Curves.easeOut);
  }
}
