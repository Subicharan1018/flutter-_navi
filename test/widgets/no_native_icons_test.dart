import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// NaviVibe draws every glyph itself (`NaviIcon` / `NaviGlyph`). A Material
/// `Icons.*` or Cupertino `CupertinoIcons.*` reference in lib/ would put a
/// system icon back into the app.
void main() {
  test('lib/ uses no Material or Cupertino icons', () {
    final native = RegExp(r'\b(Cupertino)?Icons\.[a-zA-Z_]');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (native.hasMatch(code)) offenders.add('${file.path}:${i + 1}  ${lines[i].trim()}');
      }
    }
    expect(offenders, isEmpty, reason: 'Use NaviIcon(NaviGlyph.…) instead:\n${offenders.join('\n')}');
  });
}
