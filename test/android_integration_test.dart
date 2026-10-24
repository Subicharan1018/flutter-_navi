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
    expect(p, {'title': 'T', 'artist': 'A', 'playing': true});
  });
}
