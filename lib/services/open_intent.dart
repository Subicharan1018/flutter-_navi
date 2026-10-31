import '../features/local_library/logic/local_models.dart';
import '../models/song.dart';

/// What Android asked the app to do when it was opened as a music player
/// (see `IntentRouter.kt`): a voice request or an audio file to play.
sealed class OpenIntent {
  const OpenIntent();

  /// Null for anything we don't act on.
  static OpenIntent? parse(Object? raw) {
    if (raw is! Map) return null;
    String? str(String k) {
      final v = raw[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    switch (raw['kind']) {
      case 'search':
        return SearchIntent(
          query: str('query') ?? str('title') ?? '',
          focus: str('focus'),
          artist: str('artist'),
          album: str('album'),
        );
      case 'view':
        final uri = str('uri');
        return uri == null ? null : ViewIntent(uri: uri, name: str('name'));
    }
    return null;
  }
}

/// "Play X on NaviVibe". An empty query means "play some music".
class SearchIntent extends OpenIntent {
  final String query;
  final String? focus;
  final String? artist;
  final String? album;
  const SearchIntent({required this.query, this.focus, this.artist, this.album});

  /// The extras `AudioHandler.playFromSearch` reads.
  Map<String, dynamic> get extras => {
    'android.intent.extra.focus': focus,
    'android.intent.extra.artist': artist,
    'android.intent.extra.album': album,
  };
}

/// "Open with NaviVibe" on an audio file (`content://` or `file://`).
class ViewIntent extends OpenIntent {
  final String uri;
  final String? name;
  const ViewIntent({required this.uri, this.name});

  /// What `just_audio` opens.
  String get path => uri.startsWith('file:') ? Uri.parse(uri).path : uri;

  /// A queue entry for the file. Its id is stable per URI, so opening the same
  /// file again keeps its history; the title is the file name without extension.
  Song toSong() {
    final id = localSongIdFor(uri);
    return Song(
      id: id,
      title: titleFromFileName(name ?? Uri.decodeComponent(Uri.parse(uri).pathSegments.lastOrNull ?? '')),
      artist: 'Unknown artist',
      album: 'Opened file',
      coverArt: id,
      duration: 0,
      track: 0,
      year: 0,
    );
  }
}

String titleFromFileName(String name) {
  final base = name.contains('/') ? name.substring(name.lastIndexOf('/') + 1) : name;
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  final clean = stem.replaceAll('_', ' ').trim();
  return clean.isEmpty ? 'Audio file' : clean;
}
