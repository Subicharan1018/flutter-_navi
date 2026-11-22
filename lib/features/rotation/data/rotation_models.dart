/// What the shuffle server's rotation routes return (`/rotation*`): songs
/// resting, songs that belong to a season, and the settings for both.
library;

String _str(Object? v) => v is String ? v.trim() : '';
int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
List<Map<String, dynamic>> _maps(Object? v) =>
    [for (final x in (v is List ? v : const [])) if (x is Map) Map<String, dynamic>.from(x)];

/// How long a song can rest from the song menu.
enum RestLength {
  twoWeeks(14, '2 weeks'),
  oneMonth(30, '1 month'),
  threeMonths(90, '3 months');

  final int days;
  final String label;
  const RestLength(this.days, this.label);
}

/// A song kept out of your mixes for now.
class RestingSong {
  final String songId;
  final String title;
  final String artist;
  final DateTime until;

  /// True when the server rested it because you were wearing it out.
  final bool auto;

  const RestingSong({required this.songId, required this.title, required this.artist, required this.until, required this.auto});

  static RestingSong? parse(Map<String, dynamic> j) {
    final id = _str(j['song_id']);
    final until = _int(j['until']);
    if (id.isEmpty || until <= 0) return null;
    return RestingSong(
      songId: id,
      title: _str(j['title']).isEmpty ? id : _str(j['title']),
      artist: _str(j['artist']),
      until: DateTime.fromMillisecondsSinceEpoch(until * 1000),
      auto: j['auto'] == true,
    );
  }
}

/// A festival or devotional season, with whether it is on today.
class SeasonInfo {
  final String key;
  final String label;
  final bool inSeason;

  /// "5 Oct" to "18 Nov": the usual window; the dates move a little each year.
  final String from;
  final String to;

  const SeasonInfo({required this.key, required this.label, required this.inSeason, this.from = '', this.to = ''});

  static SeasonInfo? parse(Map<String, dynamic> j) {
    final key = _str(j['key']);
    if (key.isEmpty) return null;
    return SeasonInfo(
      key: key,
      label: _str(j['label']).isEmpty ? key : _str(j['label']),
      inSeason: j['in_season'] == true,
      from: _str(j['from']),
      to: _str(j['to']),
    );
  }
}

/// A song that only plays in its season.
class SeasonalSong {
  final String songId;
  final String title;
  final String artist;
  final String season;
  final String label;
  final bool inSeason;

  /// True when you tagged it; false when the server guessed from its title or your plays.
  final bool manual;

  const SeasonalSong({
    required this.songId,
    required this.title,
    required this.artist,
    required this.season,
    required this.label,
    required this.inSeason,
    required this.manual,
  });

  static SeasonalSong? parse(Map<String, dynamic> j) {
    final id = _str(j['song_id']);
    final season = _str(j['season']);
    if (id.isEmpty || season.isEmpty) return null;
    return SeasonalSong(
      songId: id,
      title: _str(j['title']).isEmpty ? id : _str(j['title']),
      artist: _str(j['artist']),
      season: season,
      label: _str(j['label']).isEmpty ? season : _str(j['label']),
      inSeason: j['in_season'] == true,
      manual: j['manual'] == true,
    );
  }
}

class RotationPrefs {
  /// Rest songs you are wearing out, quietly.
  final bool autoRest;

  /// Keep seasonal songs out of mixes outside their season.
  final bool seasons;

  /// The Home shelf, and a few such songs in Smart Shuffle.
  final bool back;

  const RotationPrefs({this.autoRest = true, this.seasons = true, this.back = true});

  factory RotationPrefs.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return RotationPrefs(
      autoRest: m['auto_rest'] != false,
      seasons: m['seasons'] != false,
      back: m['back'] != false,
    );
  }

  RotationPrefs copyWith({bool? autoRest, bool? seasons, bool? back}) =>
      RotationPrefs(autoRest: autoRest ?? this.autoRest, seasons: seasons ?? this.seasons, back: back ?? this.back);

  @override
  bool operator ==(Object other) =>
      other is RotationPrefs && other.autoRest == autoRest && other.seasons == seasons && other.back == back;

  @override
  int get hashCode => Object.hash(autoRest, seasons, back);
}

/// `GET /rotation`.
class Rotation {
  final List<RestingSong> resting;
  final List<SeasonalSong> seasonal;
  final List<SeasonInfo> seasons;
  final RotationPrefs prefs;

  const Rotation({this.resting = const [], this.seasonal = const [], this.seasons = const [], this.prefs = const RotationPrefs()});

  factory Rotation.fromJson(Map<String, dynamic> j) => Rotation(
        resting: [for (final m in _maps(j['resting'])) ?RestingSong.parse(m)],
        seasonal: [for (final m in _maps(j['seasonal'])) ?SeasonalSong.parse(m)],
        seasons: [for (final m in _maps(j['seasons'])) ?SeasonInfo.parse(m)],
        prefs: RotationPrefs.fromJson(j['prefs']),
      );

  bool isResting(String songId) => resting.any((r) => r.songId == songId);

  /// The season [songId] is tagged with, if any.
  SeasonalSong? seasonOf(String songId) {
    for (final s in seasonal) {
      if (s.songId == songId) return s;
    }
    return null;
  }
}

/// "back on 12 Dec": when a resting song returns.
String backOnLabel(DateTime until) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'back on ${until.day} ${months[until.month - 1]}';
}
