/// What the shuffle server's personal endpoints return: the weekly mix, Flow
/// batches, "never recommend" entries and a month of listening.
library;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
double _double(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String _str(Object? v) => v is String ? v.trim() : '';
List<Map<String, dynamic>> _maps(Object? v) =>
    [for (final x in (v is List ? v : const [])) if (x is Map) Map<String, dynamic>.from(x)];

/// One song the server picked, in the shape `/predict/discovery` has always had.
class ListenPick {
  final String songId;
  final String title;
  final String artist;

  /// Why it's here, in one line ("You play a lot of Anirudh").
  final String why;

  /// Flow only: whether you already know it.
  final bool fresh;

  /// A song in a language you rarely play, offered to see if you like it.
  final bool explore;

  /// Its language code ("ml"), when the server says.
  final String language;

  const ListenPick({
    required this.songId,
    required this.title,
    required this.artist,
    required this.why,
    this.fresh = false,
    this.explore = false,
    this.language = '',
  });

  /// "Malayalam" for "ml"; the code itself for a language this app doesn't name.
  String get languageName => languageNames[language] ?? language.toUpperCase();

  /// Null for an item without a song id: it can't be played.
  static ListenPick? parse(Map<String, dynamic> j) {
    final id = _str(j['navidrome_id'] ?? j['id']);
    if (id.isEmpty) return null;
    return ListenPick(
      songId: id,
      title: _str(j['title']),
      artist: _str(j['artist']),
      why: _str(j['why']),
      fresh: j['kind'] == 'fresh',
      explore: j['explore'] == true || j['kind'] == 'explore',
      language: _str(j['language']),
    );
  }

  static List<ListenPick> parseAll(Object? v) => [
        for (final m in _maps(v))
          ?parse(m),
      ];
}

/// This week's mix (`GET /mix/weekly`).
class WeeklyMix {
  /// The Monday this mix was made for, ISO date.
  final DateTime? weekOf;

  /// When the next mix arrives.
  final DateTime? nextRefresh;
  final List<ListenPick> items;

  const WeeklyMix({required this.items, this.weekOf, this.nextRefresh});

  factory WeeklyMix.fromJson(Map<String, dynamic> j) => WeeklyMix(
        weekOf: DateTime.tryParse(_str(j['week_of'])),
        nextRefresh: DateTime.tryParse(_str(j['next_refresh'])),
        items: ListenPick.parseAll(j['items']),
      );
}

/// A reaction the next Flow batch learns from.
enum FlowAction { like, skip, play }

class FlowFeedback {
  final String songId;
  final FlowAction action;
  const FlowFeedback(this.songId, this.action);

  Map<String, String> toJson() => {'id': songId, 'action': action.name};

  @override
  bool operator ==(Object other) => other is FlowFeedback && other.songId == songId && other.action == action;

  @override
  int get hashCode => Object.hash(songId, action);
}

const Map<String, String> languageNames = {
  'ta': 'Tamil',
  'en': 'English',
  'te': 'Telugu',
  'ml': 'Malayalam',
  'hi': 'Hindi',
  'kn': 'Kannada',
  'ko': 'Korean',
  'ja': 'Japanese',
  'es': 'Spanish',
  'fr': 'French',
  'pa': 'Punjabi',
  'bn': 'Bengali',
};

/// How many songs of a Flow batch are familiar, fresh, and in a new language.
class FlowBlend {
  final int familiar;
  final int fresh;
  final int explore;
  const FlowBlend({this.familiar = 0, this.fresh = 0, this.explore = 0});

  int get total => familiar + fresh + explore;

  factory FlowBlend.fromJson(Object? j) => j is Map
      ? FlowBlend(familiar: _int(j['familiar']), fresh: _int(j['fresh']), explore: _int(j['explore']))
      : const FlowBlend();

  @override
  bool operator ==(Object other) =>
      other is FlowBlend && other.familiar == familiar && other.fresh == fresh && other.explore == explore;

  @override
  int get hashCode => Object.hash(familiar, fresh, explore);
}

/// One reply of `POST /flow/next`.
class FlowBatch {
  final List<ListenPick> items;

  /// How much of the batch is songs you haven't played (0 to 1).
  final double freshShare;
  final String? mood;
  final FlowBlend blend;

  const FlowBatch({required this.items, this.freshShare = 0.4, this.mood, this.blend = const FlowBlend()});

  factory FlowBatch.fromJson(Map<String, dynamic> j) => FlowBatch(
        items: ListenPick.parseAll(j['items']),
        freshShare: _double(j['fresh_share']),
        mood: j['mood'] is String ? j['mood'] as String : null,
        blend: FlowBlend.fromJson(j['blend']),
      );
}

/// A mood chip: [mood] is what the server takes, [songs] how many carry it.
class FlowMood {
  final String mood;
  final int songs;
  const FlowMood(this.mood, this.songs);

  /// "Calm", "Energetic": how the chip reads.
  String get label => mood.isEmpty ? mood : mood[0].toUpperCase() + mood.substring(1);
}

List<FlowMood> parseFlowMoods(Map<String, dynamic> j) => [
      for (final m in _maps(j['moods']))
        if (_str(m['mood']).isNotEmpty) FlowMood(_str(m['mood']), _int(m['songs'])),
    ];

/// What "never recommend" can be about.
enum TasteKind {
  song,
  artist,
  composer;

  static TasteKind? parse(Object? v) {
    for (final k in values) {
      if (k.name == v) return k;
    }
    return null;
  }
}

/// One thing the listener told the server never to recommend.
class TasteExclusion {
  final TasteKind kind;

  /// The song id, or the artist's or composer's name.
  final String value;

  /// What to call it on screen: the song's title, or the name.
  final String label;
  final DateTime? addedAt;

  const TasteExclusion({required this.kind, required this.value, required this.label, this.addedAt});

  /// Null for an entry this app version doesn't know the kind of.
  static TasteExclusion? parse(Map<String, dynamic> j) {
    final kind = TasteKind.parse(j['kind']);
    final value = _str(j['value']);
    if (kind == null || value.isEmpty) return null;
    final at = _int(j['added_at']);
    return TasteExclusion(
      kind: kind,
      value: value,
      label: _str(j['label']).isEmpty ? value : _str(j['label']),
      addedAt: at > 0 ? DateTime.fromMillisecondsSinceEpoch(at * 1000) : null,
    );
  }

  static List<TasteExclusion> parseAll(Map<String, dynamic> j) => [
        for (final m in _maps(j['exclusions']))
          ?parse(m),
      ];

  @override
  bool operator ==(Object other) => other is TasteExclusion && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// A song in the month's lists.
class MonthSong {
  final String songId;
  final String title;
  final String artist;
  final int plays;
  final int minutes;
  const MonthSong({required this.songId, required this.title, required this.artist, required this.plays, this.minutes = 0});

  static MonthSong? parse(Map<String, dynamic> j) {
    final id = _str(j['id']);
    if (id.isEmpty) return null;
    return MonthSong(
        songId: id, title: _str(j['title']), artist: _str(j['artist']), plays: _int(j['plays']), minutes: _int(j['minutes']));
  }
}

/// An artist or composer in the month's lists; [artId] is a song whose cover
/// stands for them.
class MonthPerson {
  final String name;
  final int plays;
  final int minutes;
  final String? artId;
  const MonthPerson({required this.name, required this.plays, required this.minutes, this.artId});

  static MonthPerson? parse(Map<String, dynamic> j) {
    final name = _str(j['name']);
    if (name.isEmpty) return null;
    final art = _str(j['art_id']);
    return MonthPerson(name: name, plays: _int(j['plays']), minutes: _int(j['minutes']), artId: art.isEmpty ? null : art);
  }
}

class MonthKey {
  final int year;
  final int month;
  const MonthKey(this.year, this.month);

  @override
  bool operator ==(Object other) => other is MonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// A month of listening (`GET /stats/month`).
class MonthStats {
  final int year;
  final int month;
  final String monthName;
  final int totalPlays;
  final int totalMinutes;
  final int previousMinutes;
  final int activeDays;
  final int daysInMonth;
  final int streakDays;
  final int uniqueSongs;

  /// Minutes listened on each day of the month, day 1 first.
  final List<int> dailyMinutes;
  final List<MonthSong> topSongs;
  final List<MonthPerson> topArtists;
  final List<MonthPerson> topComposers;
  final int newSongsCount;
  final List<MonthSong> newSongs;

  /// Months with listening on record, newest first.
  final List<MonthKey> months;

  const MonthStats({
    required this.year,
    required this.month,
    required this.monthName,
    required this.totalPlays,
    required this.totalMinutes,
    required this.previousMinutes,
    required this.activeDays,
    required this.daysInMonth,
    required this.streakDays,
    required this.uniqueSongs,
    required this.dailyMinutes,
    required this.topSongs,
    required this.topArtists,
    required this.topComposers,
    required this.newSongsCount,
    required this.newSongs,
    required this.months,
  });

  bool get isEmpty => totalPlays == 0;

  factory MonthStats.fromJson(Map<String, dynamic> j) => MonthStats(
        year: _int(j['year']),
        month: _int(j['month']),
        monthName: _str(j['month_name']),
        totalPlays: _int(j['total_plays']),
        totalMinutes: _int(j['total_minutes']),
        previousMinutes: _int(j['previous_minutes']),
        activeDays: _int(j['active_days']),
        daysInMonth: _int(j['days_in_month']),
        streakDays: _int(j['streak_days']),
        uniqueSongs: _int(j['unique_songs']),
        dailyMinutes: [for (final x in (j['daily_minutes'] is List ? j['daily_minutes'] as List : const [])) _int(x)],
        topSongs: [for (final m in _maps(j['top_songs'])) ?MonthSong.parse(m)],
        topArtists: [for (final m in _maps(j['top_artists'])) ?MonthPerson.parse(m)],
        topComposers: [for (final m in _maps(j['top_composers'])) ?MonthPerson.parse(m)],
        newSongsCount: _int(j['new_songs_count']),
        newSongs: [for (final m in _maps(j['new_songs'])) ?MonthSong.parse(m)],
        months: [
          for (final m in _maps(j['months'])) MonthKey(_int(m['year']), _int(m['month'])),
        ],
      );
}
