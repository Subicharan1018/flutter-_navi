import '../data/models/recommended_song.dart';

/// Why one song is in the mix, in plain words, from what the Smart Shuffle
/// server actually sent for it (play history at this moment, sound fit,
/// composer loyalty, the song it usually follows, whether it is new to you).
/// Nothing here is invented: a reason appears only when its number is high
/// enough to be true.
class PickWhy {
  /// The strongest reason, short enough for a table cell.
  final String short;

  /// Every reason that applies, strongest first, as full sentences.
  final List<String> reasons;

  const PickWhy({required this.short, required this.reasons});

  /// Used when the server sent nothing to explain a pick.
  static const generic = PickWhy(short: 'Fits your taste', reasons: ['Fits your taste overall.']);
}

// A score must reach these to be claimed as a reason (all scores are 0..1).
const double whyStrongHistory = 0.5;
const double whySomeHistory = 0.25;
const double whyStrongFit = 0.6;
const double whyStrongComposer = 0.5;
const int whyLongGapDays = 60;

PickWhy pickWhy(RecommendedSong rec) {
  final out = <(String short, String long)>[];

  if (rec.isStarter) {
    out.add(('Your usual opener', 'You usually start this time of day with it.'));
  }
  final pairing = rec.pairing;
  if (pairing != null && pairing.follows.isNotEmpty) {
    final times = pairing.timesFollowed;
    out.add((
      'Follows “${pairing.follows}”',
      'You usually play it after “${pairing.follows}”'
          '${times > 1 ? ' ($times times)' : ''}.',
    ));
  }
  final history = rec.scores.contextHistory;
  if (history >= whyStrongHistory) {
    out.add(('You play it now', 'You play it a lot at moments like this.'));
  } else if (history >= whySomeHistory) {
    out.add(('You’ve played it now', 'You have played it around this time before.'));
  }
  final loyalty = rec.loyalty;
  if (loyalty != null && loyalty >= whyStrongHistory) {
    out.add(('A song you keep', 'One of the songs you come back to most at this moment.'));
  }
  if (rec.scores.audioFit >= whyStrongFit) {
    out.add(('Sounds like now', 'It sounds like this moment: its energy and mood fit.'));
  }
  if (rec.scores.composerLoyalty >= whyStrongComposer && rec.composer.isNotEmpty) {
    out.add(('Composer you like', 'By ${rec.composer}, a composer you keep returning to.'));
  }
  if (rec.isExplore) {
    out.add(('New to you', 'You have not played it yet. It was picked for how it sounds.'));
  }
  final gap = rec.daysSincePlay;
  if (gap != null && gap >= whyLongGapDays) {
    out.add(('Back after $gap days', 'You have not played it in $gap days.'));
  }

  if (out.isEmpty) {
    final server = rec.why.trim();
    if (server.isEmpty) return PickWhy.generic;
    return PickWhy(short: server, reasons: [server]);
  }
  return PickWhy(short: out.first.$1, reasons: [for (final r in out) r.$2]);
}
