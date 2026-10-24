import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/crash_log.dart';
import '../core/theme.dart';

/// "Last error" row for Settings > About. Renders nothing when no error has
/// been recorded; tap shows the text with copy and clear actions.
class LastErrorRow extends StatefulWidget {
  const LastErrorRow({super.key});

  @override
  State<LastErrorRow> createState() => _LastErrorRowState();
}

class _LastErrorRowState extends State<LastErrorRow> {
  late Future<String?> _error = CrashLog.read();

  void _show(String text) {
    showDialog<void>(
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
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              setState(() => _error = CrashLog.read());
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _error,
      builder: (context, snap) {
        final text = snap.data;
        if (text == null) return const SizedBox.shrink();
        final tokens = ThemeTokens.of(context);
        return Column(
          children: [
            InkWell(
              onTap: () => _show(text),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Last error',
                        style: TextStyle(
                            color: tokens.textPrimary, fontSize: 15)),
                    Text(text.split('\n').first.split('T').first,
                        style:
                            TextStyle(color: tokens.textMuted, fontSize: 15)),
                  ],
                ),
              ),
            ),
            Divider(height: 1, indent: 16, color: tokens.outline),
          ],
        );
      },
    );
  }
}
