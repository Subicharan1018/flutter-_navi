import '../data/wrapped_models.dart';
import 'film.dart';
import 'scenes_end.dart';
import 'scenes_mid.dart';
import 'scenes_open.dart';

const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String sayHour(int h) => h == 0
    ? 'midnight'
    : h == 12
    ? 'noon'
    : h < 12
    ? '$h am'
    : '${h - 12} pm';

String sayDate(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  return d == null ? '' : '${d.day} ${monthNames[d.month - 1]}';
}

String grouped(int v) {
  final s = '$v';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// A song's name without the film it is from: 'Hangova (From "DC")' is Hangova.
String nice(String title) {
  final out = title.replaceAll(RegExp(r'\s*[\(\[]\s*(from|feat\.?|ft\.?|with)\b[^\)\]]*[\)\]]', caseSensitive: false), '').trim();
  return out.isEmpty ? title : out;
}

/// The film, in order. A scene with nothing behind it is left out. Until the year is [settled] the film runs only as
/// far as what is known, so nothing is ever added behind you: more of it appears ahead. Neighbours never share a colour world.
List<FilmScene> filmScenes(WrappedData d, {bool settled = true}) {
  if (d.isEmpty) return settled ? [IgniteScene(), SandScene(), ReceiptScene(), SpiritScene(d), MixtapeScene()] : [IgniteScene()];
  final s = d.story;
  return [
    IgniteScene(),
    SandScene(),
    if (d.songs.length >= 3) ScratchScene(),
    if (d.songs.isNotEmpty) TurntableScene(),
    if (d.songs.length >= 2) FlapScene(d),
    if (d.artists.isNotEmpty) PinboardScene(),
    if (d.genres.isNotEmpty) RibbonScene(),
    if (d.hourly.any((v) => v > 0)) SkylineScene(),
    if (d.busiestMonth != null) RidgeScene(),
    if (settled) ...[
      if (s.race.length >= 3) RaceScene(d),
      if (s.albums.length >= 2) CrateScene(),
      if (s.obsession != null) ObsessionScene(),
      if (s.ends != null) CassetteScene(),
      if (s.composers.length >= 2) ReelScene(),
      if (s.languages.length >= 2) StampsScene(),
      if (s.moods.isNotEmpty) WeatherScene(),
      if (s.era != null) TunerScene(),
      if (s.week.any((v) => v > 0)) FadersScene(),
      if (d.days.isNotEmpty) CalendarScene(),
      if (d.uniqueSongs > 0) WarpScene(),
      if (s.loyal != null) ScoreboardScene(),
      if (d.bestDay != null) ShoreScene(d),
      ReceiptScene(),
      SpiritScene(d),
      MixtapeScene(),
    ],
  ];
}
