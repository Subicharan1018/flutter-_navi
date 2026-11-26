import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/wrapped/data/wrapped_models.dart';
import 'package:navivibe/features/wrapped/data/wrapped_story.dart';
import 'package:navivibe/features/wrapped/film/film.dart';
import 'package:navivibe/features/wrapped/film/film_assets.dart';

/// A full year: five songs, six artists, a 16-day streak in March, a busy hour at 11 pm.
WrappedData fixtureWrapped({bool thin = false}) {
  if (thin) {
    return WrappedData(
      year: 2026, totalMinutes: 30, totalPlays: 5, uniqueSongs: 4, uniqueArtists: 2, listeningDays: 1, skipRate: 0, peakHour: 9,
      hourly: List.filled(24, 0), songs: const [], artists: const [], genres: const [],
      months: [for (var m = 1; m <= 12; m++) WrappedMonth(month: m, minutes: 0)], days: const [], longestStreak: 0,
    );
  }
  String iso(int m, int d) => '2026-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  final days = <String, int>{
    for (var m = 1; m <= 12; m++)
      for (var d = 1; d <= 28; d += 3) iso(m, d): 20 + (m * d) % 70,
    for (var d = 5; d <= 20; d++) iso(3, d): 40 + d,
    iso(10, 14): 412,
  };
  final dates = days.keys.toList()..sort();
  return WrappedData(
    year: 2026, totalMinutes: 41230, totalPlays: 9120, uniqueSongs: 1480, uniqueArtists: 312, listeningDays: 318, skipRate: 0.18, peakHour: 23,
    hourly: [for (var h = 0; h < 24; h++) h == 23 ? 900 : (h >= 21 || h <= 1) ? 500 - (h % 7) * 30 : 80 + (h * 37) % 160],
    songs: const [
      WrappedSong(title: 'Munbe Vaa', artist: 'A. R. Rahman', plays: 212, minutes: 960, album: 'Sillunu Oru Kaadhal'),
      WrappedSong(title: 'Kadhal Sadugudu', artist: 'Harris Jayaraj', plays: 180, minutes: 820, album: 'Alaipayuthey'),
      WrappedSong(title: 'Vaseegara', artist: 'Bombay Jayashri', plays: 161, minutes: 700, album: 'Minnale'),
      WrappedSong(title: 'Nenjukkul Peidhidum', artist: 'Harris Jayaraj', plays: 140, minutes: 640),
      WrappedSong(title: 'Anbil Avan', artist: 'A. R. Rahman', plays: 122, minutes: 530),
    ],
    artists: const [
      WrappedArtist(name: 'A. R. Rahman', plays: 1900, minutes: 8800, songs: 140),
      WrappedArtist(name: 'Harris Jayaraj', plays: 1400, minutes: 6100, songs: 99),
      WrappedArtist(name: 'Anirudh', plays: 900, minutes: 3900, songs: 64),
      WrappedArtist(name: 'Sid Sriram', plays: 600, minutes: 2500, songs: 40),
      WrappedArtist(name: 'Yuvan', plays: 400, minutes: 1700, songs: 31),
      WrappedArtist(name: 'Ilaiyaraaja', plays: 300, minutes: 1300, songs: 22),
    ],
    genres: const [
      WrappedGenre(name: 'Tamil film', pct: 54),
      WrappedGenre(name: 'Pop', pct: 21),
      WrappedGenre(name: 'Indie', pct: 13),
      WrappedGenre(name: 'Classical', pct: 8),
      WrappedGenre(name: 'Rock', pct: 4),
    ],
    months: [
      for (var m = 1; m <= 12; m++)
        WrappedMonth(month: m, minutes: [2100, 1800, 4800, 3000, 2500, 2200, 3100, 3500, 3900, 5200, 4300, 3800][m - 1], topGenre: 'Tamil film', topSong: 'Munbe Vaa', topArtist: 'A. R. Rahman'),
    ],
    days: [for (final d in dates) WrappedDay(date: d, minutes: days[d]!)],
    longestStreak: 16, streakStart: '2026-03-05', streakEnd: '2026-03-20',
    bestDay: const WrappedDay(date: '2026-10-14', minutes: 412),
    story: const WrappedStory(
      bpm: 96,
      albums: [
        WrappedAlbum('Sillunu Oru Kaadhal', 'A. R. Rahman', 334, 2, 'Munbe Vaa|A. R. Rahman'),
        WrappedAlbum('Alaipayuthey', 'Harris Jayaraj', 180, 1, 'Kadhal Sadugudu|Harris Jayaraj'),
        WrappedAlbum('Minnale', 'Bombay Jayashri', 161, 1, 'Vaseegara|Bombay Jayashri'),
        WrappedAlbum('Ghajini', 'Harris Jayaraj', 140, 1, 'Nenjukkul Peidhidum|Harris Jayaraj'),
      ],
      obsession: Obsession('Vaseegara', 'Bombay Jayashri', 87, 3),
      race: {
        'A. R. Rahman': [80, 190, 420, 560, 700, 820, 980, 1150, 1330, 1560, 1740, 1900],
        'Harris Jayaraj': [140, 300, 380, 500, 610, 760, 840, 930, 1080, 1200, 1300, 1400],
        'Anirudh': [60, 120, 200, 260, 420, 560, 640, 700, 760, 810, 860, 900],
        'Sid Sriram': [40, 90, 140, 200, 260, 300, 360, 420, 470, 520, 560, 600],
        'Yuvan': [90, 130, 160, 190, 230, 260, 290, 310, 330, 360, 380, 400],
        'Ilaiyaraaja': [20, 50, 80, 110, 140, 170, 190, 210, 230, 260, 280, 300],
      },
      loyal: Loyal('A. R. Rahman', [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12]),
      comeback: Comeback('Yuvan', 4, 9),
      week: [52, 48, 61, 70, 118, 96, 84],
      known: 46,
      languages: [WrappedGenre(name: 'Tamil', pct: 71), WrappedGenre(name: 'English', pct: 18), WrappedGenre(name: 'Hindi', pct: 8), WrappedGenre(name: 'Malayalam', pct: 3)],
      composers: [
        WrappedArtist(name: 'A. R. Rahman', plays: 910, minutes: 0, songs: 14),
        WrappedArtist(name: 'Harris Jayaraj', plays: 640, minutes: 0, songs: 9),
        WrappedArtist(name: 'Anirudh Ravichander', plays: 420, minutes: 0, songs: 7),
      ],
      moods: [WrappedGenre(name: 'Romantic', pct: 46), WrappedGenre(name: 'Sad', pct: 22), WrappedGenre(name: 'Party', pct: 18), WrappedGenre(name: 'Chill', pct: 9), WrappedGenre(name: 'Happy', pct: 5)],
      era: Era(2008, 1986, 2026, 'Mandram Vandha', 'Hangova (From "DC")'),
      ends: Bookends(
        WrappedPlay(title: 'Nenjukkul Peidhidum', artist: 'Harris Jayaraj', at: '2026-01-01 00:04'),
        WrappedPlay(title: 'Munbe Vaa', artist: 'A. R. Rahman', at: '2026-11-24 12:40'),
      ),
    ),
  );
}

/// Stand-in artwork with a shape and colours of its own, so a picture made of particles can be recognised.
Future<ui.Image> fakeArt(int seed) {
  const hues = [18.0, 205.0, 42.0, 150.0, 0.0, 215.0];
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  Color hue(double s, double l) => HSLColor.fromAHSL(1, hues[seed % 6], s, l).toColor();
  c.drawRect(const Rect.fromLTWH(0, 0, 256, 256), Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(256, 256), [hue(0.6, 0.55), hue(0.5, 0.2)]));
  c.drawCircle(Offset(90 + seed * 14, 110), 70, Paint()..color = hue(0.75, 0.72));
  c.drawRect(Rect.fromLTWH(30, 170 + seed * 6, 190, 22), Paint()..color = const Color(0xFFF4EFE6));
  return rec.endRecording().toImage(256, 256);
}

/// The film with its artwork in. Call inside `tester.runAsync`.
Future<WrappedFilm> fixtureFilm({WrappedData? data, bool art = true}) async {
  final d = data ?? fixtureWrapped();
  final assets = FilmAssets();
  if (art) {
    for (var i = 0; i < d.songs.length; i++) {
      final art = await fakeArt(i);
      assets.covers[d.songs[i].coverKey] = art;
      assets.hues[d.songs[i].coverKey] = await imageHue(art);
    }
    for (var i = 0; i < d.artists.length; i++) {
      assets.people[d.artists[i].name] = await fakeArt(i + 1);
    }
  }
  assets.year = await textPoints('${d.year}', 1300);
  return WrappedFilm(d, assets);
}

Widget wrappedApp(Widget child, {bool reduced = false}) {
  final tokens = AppThemeTokens.fallback;
  return ThemeTokens(
    tokens: tokens,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(tokens),
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: c!,
      ),
      home: Scaffold(backgroundColor: Colors.black, body: child),
    ),
  );
}
