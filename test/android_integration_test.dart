import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/android_integration.dart';

void main() {
  test('widget payload falls back when nothing is playing', () {
    final p = AndroidIntegration.widgetPayload(null, false);
    expect(p['artist'], 'Nothing playing');
    expect(p['playing'], false);
  });

  test('widget payload reflects the current item', () {
    final p = AndroidIntegration.widgetPayload(
      const MediaItem(id: '1', title: 'T', artist: 'A'),
      true,
    );
    expect(p, {'title': 'T', 'artist': 'A', 'playing': true, 'active': true, 'art': ''});
  });

  test('widget payload prefers the original artwork over the car proxy', () {
    final p = AndroidIntegration.widgetPayload(
      MediaItem(
        id: '1',
        title: 'T',
        artUri: Uri.parse('content://auth/net?u=x'),
        extras: const {'artSrc': 'https://h/getCoverArt?id=1'},
      ),
      false,
      active: false,
    );
    expect(p['art'], 'https://h/getCoverArt?id=1');
    expect(p['active'], false);
  });
}
