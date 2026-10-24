import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/crash_log.dart';
import 'ui/grouped_list.dart';

/// The last recorded uncaught error, or null. Invalidate after clearing.
final lastErrorProvider = FutureProvider.autoDispose<String?>(
  (ref) => CrashLog.read(),
);

/// "Last error" row for Settings > About; shows the text with copy and clear.
class LastErrorRow extends StatelessWidget {
  final String text;
  final VoidCallback onCleared;
  const LastErrorRow({super.key, required this.text, required this.onCleared});

  @override
  Widget build(BuildContext context) {
    return GroupedRow(
      title: 'Last error',
      value: text.split('\n').first.split('T').first,
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Last error'),
          content: SingleChildScrollView(child: SelectableText(text)),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () async {
                await CrashLog.clear();
                if (ctx.mounted) Navigator.pop(ctx);
                onCleared();
              },
              child: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }
}
