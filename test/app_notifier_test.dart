import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/app_notifier.dart';
import 'package:navivibe/services/notification_triggers.dart';

void main() {
  test('notifies only when enabled and the app is in the background', () {
    expect(AppNotifier.shouldShow(foreground: false, enabled: true), isTrue);
    expect(AppNotifier.shouldShow(foreground: true, enabled: true), isFalse);
    expect(AppNotifier.shouldShow(foreground: false, enabled: false), isFalse);
  });

  test('an update is announced once per build and not after it was dismissed', () {
    expect(shouldAnnounceUpdate(build: 12, notifiedBuild: 0, dismissedBuild: 0), isTrue);
    expect(shouldAnnounceUpdate(build: 12, notifiedBuild: 12, dismissedBuild: 0), isFalse);
    expect(shouldAnnounceUpdate(build: 12, notifiedBuild: 0, dismissedBuild: 12), isFalse);
    expect(shouldAnnounceUpdate(build: 13, notifiedBuild: 12, dismissedBuild: 12), isTrue);
  });

  test('only a rise in invitations is news', () {
    expect(invitationsIncreased(null, 1), isTrue);
    expect(invitationsIncreased(0, 2), isTrue);
    expect(invitationsIncreased(2, 1), isFalse);
    expect(invitationsIncreased(1, 1), isFalse);
    expect(invitationsIncreased(null, 0), isFalse);
  });

  test('messages read plainly', () {
    expect(invitationText(1), contains('new invitation'));
    expect(invitationText(3), contains('3 invitations'));
    expect(downloadsText(1, 1), 'Your song is ready offline.');
    expect(downloadsText(5, 5), 'All 5 songs are ready offline.');
    expect(downloadsText(3, 5), contains('3 of 5'));
  });

  group('Windows toast', () {
    test('text cannot break out of the XML or the PowerShell string', () {
      final script = AppNotifier.windowsToastScript(
        "Evil' ; Remove-Item x; '",
        '<script>&"</script>',
      );
      expect(script, contains('Evil&apos; ; Remove-Item x; &apos;'));
      expect(script, contains('&lt;script&gt;&amp;&quot;&lt;/script&gt;'));
      // Every quote inside the literal is doubled, so the literal can't end early.
      final literal = script.split("LoadXml(")[1].split(")\n")[0];
      expect(literal.startsWith("'") && literal.endsWith("'"), isTrue);
      final inner = literal.substring(1, literal.length - 1);
      expect(RegExp(r"(?<!')'(?!')").hasMatch(inner.replaceAll("''", '')), isFalse);
    });

    test('the encoded command is UTF-16LE base64', () {
      final bytes = base64.decode(AppNotifier.encodeForPowerShell('Aé'));
      expect(bytes, [0x41, 0x00, 0xE9, 0x00]);
    });
  });
}
