import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/local_library/logic/local_index.dart';
import 'package:navivibe/features/local_library/logic/local_models.dart';
import 'package:navivibe/services/open_intent.dart';

void main() {
  group('parse', () {
    test('voice search keeps the focus hints', () {
      final i = OpenIntent.parse({
        'kind': 'search',
        'query': ' radiohead ',
        'focus': 'vnd.android.cursor.item/artist',
        'artist': 'Radiohead',
        'album': null,
      }) as SearchIntent;
      expect(i.query, 'radiohead');
      expect(i.extras['android.intent.extra.artist'], 'Radiohead');
      expect(i.extras['android.intent.extra.focus'], 'vnd.android.cursor.item/artist');
    });

    test('an empty voice request is still a search ("play some music")', () {
      final i = OpenIntent.parse({'kind': 'search', 'query': ''}) as SearchIntent;
      expect(i.query, isEmpty);
    });

    test('the title stands in when the query is missing', () {
      final i = OpenIntent.parse({'kind': 'search', 'title': 'Karma Police'}) as SearchIntent;
      expect(i.query, 'Karma Police');
    });

    test('view needs a uri; junk is ignored', () {
      expect(OpenIntent.parse({'kind': 'view'}), isNull);
      expect(OpenIntent.parse({'kind': 'other'}), isNull);
      expect(OpenIntent.parse(null), isNull);
      expect(OpenIntent.parse('x'), isNull);
    });
  });

  group('opened files', () {
    test('become a local song with a stable id and a readable title', () {
      const a = ViewIntent(uri: 'content://media/external/audio/media/42', name: 'my_song-v2.flac');
      final song = a.toSong();
      expect(isLocalSongId(song.id), isTrue);
      expect(song.title, 'my song-v2');
      expect(a.toSong().id, song.id);
      expect(const ViewIntent(uri: 'content://x/other').toSong().id, isNot(song.id));
    });

    test('file:// uris play from their path; content:// uris stay as they are', () {
      expect(const ViewIntent(uri: 'content://a/b').path, 'content://a/b');
      expect(const ViewIntent(uri: 'file:///sdcard/Music/a.mp3').path, '/sdcard/Music/a.mp3');
    });

    test('the title falls back to the uri tail, then to a generic name', () {
      expect(const ViewIntent(uri: 'content://a/dl/track%20one.mp3').toSong().title, 'track one');
      expect(titleFromFileName(''), 'Audio file');
      expect(titleFromFileName('/x/y/z.ogg'), 'z');
    });

    test('registering the file lets the playback path find it', () {
      const v = ViewIntent(uri: 'content://a/b/1', name: 'a.mp3');
      final song = v.toSong();
      LocalLibraryIndex.instance.register(song.id, v.path);
      expect(LocalLibraryIndex.instance.pathFor(song.id), 'content://a/b/1');
      expect(LocalLibraryIndex.uriFor(v.path).scheme, 'content');
      LocalLibraryIndex.instance.clear();
    });
  });
}
