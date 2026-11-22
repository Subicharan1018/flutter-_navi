import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the files that make NaviVibe register as a music player. If one of
/// these lines is deleted, the OS stops listing the app as a music app.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  group('AndroidManifest', () {
    for (final needle in const [
      'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
      'android.permission.POST_NOTIFICATIONS',
      'android:foregroundServiceType="mediaPlayback"',
      'android.media.browse.MediaBrowserService',
      'android.intent.action.MEDIA_BUTTON',
      'android.intent.category.APP_MUSIC',
      'android.intent.category.LEANBACK_LAUNCHER',
      'android.software.leanback',
      'android.media.action.MEDIA_PLAY_FROM_SEARCH',
      'android:mimeType="audio/*"',
      'android:scheme="content"',
      'android:scheme="file"',
      'android:banner=',
      '@xml/automotive_app_desc',
    ]) {
      test('declares $needle', () => expect(manifest, contains(needle)));
    }

    test('leanback is optional so phones still install it', () {
      expect(
        RegExp(r'android\.software\.leanback"\s+android:required="false"').hasMatch(manifest),
        isTrue,
      );
    });
  });

  group('web', () {
    final json = jsonDecode(File('web/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    final index = File('web/index.html').readAsStringSync();

    test('manifest is installable and categorised as music', () {
      expect(json['name'], 'NaviVibe');
      expect(json['categories'], contains('music'));
      expect(json['display'], 'standalone');
      expect(json['theme_color'], isNotEmpty);
      final icons = (json['icons'] as List).cast<Map<String, dynamic>>();
      expect(icons.any((i) => i['sizes'] == '512x512'), isTrue);
      expect(icons.any((i) => i['purpose'] == 'maskable'), isTrue);
    });

    test('index.html links the manifest and theme colour', () {
      expect(index, contains('rel="manifest"'));
      expect(index, contains('name="theme-color"'));
    });
  });
}
