import 'package:flutter/widgets.dart';

import '../../../core/theme.dart';
import '../../../utils/format.dart';

/// A name for when you listen, read straight from the plays-by-hour counts:
/// the busiest hour decides it. Null when there are no plays to read.
({String name, int hour})? listenerType(Map<String, int> byHour) {
  int? peak;
  var best = 0;
  for (var h = 0; h < 24; h++) {
    final n = byHour['$h'] ?? 0;
    if (n > best) {
      best = n;
      peak = h;
    }
  }
  if (peak == null) return null;
  final name = switch (peak) {
    >= 5 && < 11 => 'Early bird',
    >= 11 && < 17 => 'Daytime listener',
    >= 17 && < 22 => 'Evening regular',
    _ => 'Night owl',
  };
  return (name: name, hour: peak);
}

/// The listener type as the page's first line: the name in gold, the busiest
/// hour beside it. It is the one line that says something about you before
/// any number does.
class ListenerTypeLine extends StatelessWidget {
  final Map<String, int> byHour;
  const ListenerTypeLine({super.key, required this.byHour});

  @override
  Widget build(BuildContext context) {
    final type = listenerType(byHour);
    if (type == null) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: type.name.toUpperCase(), style: t.caption2.copyWith(color: t.accent, letterSpacing: 1.2)),
            TextSpan(text: '  ·  peaks at ${hourLabel(type.hour)}', style: t.caption2.copyWith(color: t.textMuted)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
