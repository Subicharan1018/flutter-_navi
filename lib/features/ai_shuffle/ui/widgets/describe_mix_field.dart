import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../widgets/ui/controls.dart';
import '../../logic/mix_intent_provider.dart';

/// "Describe a mix": type what you want to hear; the server picks the
/// library songs that fit, and Smart Shuffle ranks them for you. Shows what
/// it understood ("Tuned for Tamil · Melody · calm") with a way back.
class DescribeMixField extends ConsumerStatefulWidget {
  /// Back to the regular tuned-for-now picks.
  final VoidCallback onClear;
  const DescribeMixField({super.key, required this.onClear});

  @override
  ConsumerState<DescribeMixField> createState() => _DescribeMixFieldState();
}

class _DescribeMixFieldState extends ConsumerState<DescribeMixField> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clear() {
    _text.clear();
    widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = ref.watch(mixIntentProvider);
    final result = s.result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: NaviSearchField(
            controller: _text,
            placeholder: 'Describe a mix, like “calm Tamil melodies”',
            onSubmitted: (q) => ref.read(mixIntentProvider.notifier).apply(q),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.md),
          child: switch ((s.busy, s.error, result)) {
            (true, _, _) => Row(children: [
                const CupertinoActivityIndicator(radius: 7),
                const SizedBox(width: Space.sm),
                Text('Finding songs that fit…', style: t.footnote),
              ]),
            (_, final String error, _) => Text(error, style: t.footnote.copyWith(color: t.warning)),
            (_, _, final r?) => Row(
                children: [
                  Icon(CupertinoIcons.sparkles, size: 15, color: t.accent),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: Text(
                      'Tuned for ${r.summary}'
                      '${r.relaxed.isEmpty ? '' : ' (loosened ${r.relaxed.join(', ')} to find enough)'}'
                      ' · ${r.count} ${r.count == 1 ? 'song' : 'songs'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.footnote,
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: Space.sm),
                    minimumSize: const Size(44, 32),
                    onPressed: _clear,
                    child: Text('Clear', style: t.footnote.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}
