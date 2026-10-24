import 'package:flutter/widgets.dart';

/// A number whose digits roll like an odometer: on first show every digit
/// spins up from zero, and when [value] changes the digits that differ roll
/// to their new place. Separators and units ("h", ",") stay still.
///
/// One controller drives all the digits. Reduced motion, and the settled
/// state, show a plain [Text] so the number is crisp and selectable.
class NumberRoll extends StatefulWidget {
  final int value;
  final String Function(int) format;
  final TextStyle style;
  final Duration duration;
  final Duration delay;

  /// Drive the roll from a parent animation (a story card's clock) instead
  /// of starting on mount.
  final Animation<double>? progress;

  /// With [progress], the part of it (0..1) the roll takes; the rest holds.
  final double window;

  const NumberRoll({
    super.key,
    required this.value,
    required this.style,
    this.format = _plain,
    this.duration = const Duration(milliseconds: 1400),
    this.delay = Duration.zero,
    this.progress,
    this.window = 1,
  });

  static String _plain(int v) => '$v';

  @override
  State<NumberRoll> createState() => _NumberRollState();
}

class _NumberRollState extends State<NumberRoll> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  int _from = 0;
  bool _started = false;

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || widget.progress != null) return;
    _started = true;
    if (_reduced) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void didUpdateWidget(NumberRoll old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value || widget.progress != null) return;
    _from = old.value;
    if (_reduced) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.format(widget.value);
    final external = widget.progress;
    if (_reduced && external == null) return Text(text, style: widget.style);
    final listenable = external ?? _c;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: listenable,
          builder: (context, _) {
            final t = external == null ? _c.value : (external.value / widget.window).clamp(0.0, 1.0);
            if (t >= 1) return Text(text, style: widget.style);
            return _Rolling(
              text: text,
              from: widget.format(external == null ? _from : 0),
              t: Curves.easeOutExpo.transform(t),
              style: widget.style,
            );
          },
        ),
      ),
    );
  }
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

class _Rolling extends StatelessWidget {
  final String text;
  final String from;
  final double t;
  final TextStyle style;
  const _Rolling({required this.text, required this.from, required this.t, required this.style});

  @override
  Widget build(BuildContext context) {
    final chars = text.characters.toList();
    final fromChars = from.characters.toList();
    final row = (style.fontSize ?? 16) * (style.height ?? 1.2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chars.length; i++)
          if (!_isDigit(chars[i]))
            Text(chars[i], style: style)
          else
            _Digit(
              to: int.parse(chars[i]),
              from: _fromDigit(fromChars, chars.length, i),
              // Lower digits spin the whole way; higher ones settle a little sooner.
              t: Interval(0, 1 - 0.06 * (chars.length - 1 - i).clamp(0, 6)).transform(t),
              style: style,
              row: row,
            ),
      ],
    );
  }

  /// The digit that was in this slot before, counting from the right.
  int _fromDigit(List<String> fromChars, int len, int i) {
    final j = fromChars.length - (len - i);
    if (j < 0) return 0;
    final c = fromChars[j];
    return _isDigit(c) ? int.parse(c) : 0;
  }
}

class _Digit extends StatelessWidget {
  final int from;
  final int to;
  final double t;
  final TextStyle style;
  final double row;
  const _Digit({required this.from, required this.to, required this.t, required this.style, required this.row});

  @override
  Widget build(BuildContext context) {
    // Always roll upward; a digit that stays the same still takes one lap.
    // Always roll upward; a digit that stays the same still takes one lap.
    final travel = ((to - from) % 10) + 10;
    final pos = (from + travel * t) % 10;
    return ClipRect(
      child: Stack(
        children: [
          // Sizes the slot; tabular figures make every digit the same width.
          Opacity(opacity: 0, child: SizedBox(height: row, child: Text('0', style: style))),
          Positioned(
            top: -pos * row,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var k = 0; k < 20; k++) SizedBox(height: row, child: Text('${k % 10}', style: style)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
