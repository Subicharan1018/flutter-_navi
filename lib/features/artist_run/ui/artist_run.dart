import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../core/theme.dart';
import '../../../models/album.dart';
import '../../../utils/format.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/ui/media.dart' show SectionHeader;
import '../logic/artist_run.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

/// "With you": what the listener's own play log says about this artist, set
/// straight on the page as three big figures and one line. Only real counts;
/// an artist never played shows nothing.
class ArtistWithYou extends StatelessWidget {
  final ArtistHistory history;
  const ArtistWithYou({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final fig = naviText(30, FontWeight.w700, t.textPrimary, height: 1.05, tabular: true);
    Widget stat(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: fig),
          ),
          const SizedBox(height: Space.xxs),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
        ],
      ),
    );
    final top = history.topSong;
    final summary =
        '${history.plays} ${history.plays == 1 ? 'play' : 'plays'}, '
        '${listeningTime(history.minutes)}, since ${_monthYear(history.first!)}'
        '${top == null ? '' : '. Most played: $top'}';
    return Semantics(
      container: true,
      label: 'With you. $summary',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('With You', style: t.title2),
              const SizedBox(height: Space.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    stat(compactCount(history.plays), history.plays == 1 ? 'play' : 'plays'),
                    stat(listeningTime(history.minutes), 'listening'),
                  ],
                ),
              ),
              if (history.first != null && history.last != null) ...[
                const SizedBox(height: Space.lg),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: _ListeningSpan(first: history.first!, last: history.last!),
                ),
              ],
              if (top != null) ...[
                const SizedBox(height: Space.md),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Most played  ', style: t.footnote),
                      TextSpan(
                        text: top,
                        style: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: history.topSongPlays > 1 ? '  ${history.topSongPlays} plays' : '',
                        style: t.footnote,
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The career at a glance as a ribbon: a hairline from the first release to
/// the latest with one dot per year that has an album, as large as that year's
/// song count. Years you have played are white, the rest dim. No bars.
class CareerStrip extends StatelessWidget {
  final List<ReleaseYear> years;
  final ArtistHistory history;
  const CareerStrip({super.key, required this.years, required this.history});

  @override
  Widget build(BuildContext context) {
    final dated = [
      for (final y in years)
        if (y.year > 0) y,
    ];
    if (dated.length < 2) return const SizedBox.shrink();
    final t = ThemeTokens.of(context);
    final first = dated.last.year;
    final last = dated.first.year;
    final songs = {for (final y in dated) y.year: y.songs};
    final heard = {
      for (final y in dated)
        if (y.albums.any((a) => history.playsOf(a) > 0)) y.year,
    };
    final span = last - first + 1;
    return Semantics(
      label: 'Releases from $first to $last, ${dated.length} years with an album',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.md),
          child: Column(
            children: [
              SizedBox(
                height: 40,
                width: double.infinity,
                child: CustomPaint(
                  painter: CareerStripPainter(
                    first: first,
                    span: span,
                    songs: songs,
                    heard: heard,
                    heardColor: t.accent,
                    idleColor: t.accentDim,
                  ),
                ),
              ),
              const SizedBox(height: Space.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$first', style: t.caption1),
                  Text('$last', style: t.caption1),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CareerStripPainter extends CustomPainter {
  final int first;
  final int span;
  final Map<int, int> songs;
  final Set<int> heard;

  final Color heardColor;
  final Color idleColor;
  const CareerStripPainter({
    required this.first,
    required this.span,
    required this.songs,
    required this.heard,
    required this.heardColor,
    required this.idleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final peak = songs.values.fold(1, math.max);
    final slot = size.width / span;
    final lineY = size.height - 10;
    final paint = Paint();
    canvas.drawRect(Rect.fromLTWH(0, lineY - 0.5, size.width, 1), paint..color = idleColor.withValues(alpha: 0.5));
    for (var i = 0; i < span; i++) {
      final n = songs[first + i];
      if (n == null) continue;
      final r = 2.5 + 4.5 * (n / peak);
      canvas.drawCircle(Offset(slot * (i + 0.5), lineY), r, paint..color = heard.contains(first + i) ? heardColor : idleColor);
    }
  }

  @override
  bool shouldRepaint(CareerStripPainter old) =>
      old.first != first ||
      old.span != span ||
      old.heardColor != heardColor ||
      old.idleColor != idleColor ||
      !_sameMap(old.songs, songs) ||
      old.heard.length != heard.length ||
      !old.heard.containsAll(heard);

  static bool _sameMap(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

/// The discography as a year spine: a big tabular numeral per year, a hairline
/// down the page, and that year's covers. A hairline under each cover fills to
/// your share of plays, so the era you live in shows without a single number.
/// Tap a year to play what came out in it.
///
/// Returned as slivers so a hundred-album artist builds only the rows on
/// screen.
List<Widget> releaseTimelineSlivers(
  BuildContext context, {
  required List<ReleaseYear> years,
  required ArtistHistory history,
  required String Function(Album) coverUrl,
  required ValueChanged<Album> onOpen,
  required ValueChanged<ReleaseYear> onPlayYear,
  required void Function(Album) onLongPress,
}) {
  final t = ThemeTokens.of(context);
  final size = (ArtSize.of(context).tile * 0.6).roundToDouble();
  return [
    const SliverToBoxAdapter(child: SectionHeader(title: 'Albums')),
    SliverToBoxAdapter(
      child: CareerStrip(years: years, history: history),
    ),
    SliverList.builder(
      itemCount: years.length,
      itemBuilder: (context, i) => _YearRow(
        key: ValueKey('year-${years[i].year}'),
        year: years[i],
        first: i == 0,
        last: i == years.length - 1,
        size: size,
        history: history,
        tokens: t,
        coverUrl: coverUrl,
        onOpen: onOpen,
        onPlayYear: onPlayYear,
        onLongPress: onLongPress,
      ),
    ),
  ];
}

class _YearRow extends StatelessWidget {
  final ReleaseYear year;
  final bool first;
  final bool last;
  final double size;
  final ArtistHistory history;
  final AppThemeTokens tokens;
  final String Function(Album) coverUrl;
  final ValueChanged<Album> onOpen;
  final ValueChanged<ReleaseYear> onPlayYear;
  final void Function(Album) onLongPress;

  const _YearRow({
    super.key,
    required this.year,
    required this.first,
    required this.last,
    required this.size,
    required this.history,
    required this.tokens,
    required this.coverUrl,
    required this.onOpen,
    required this.onPlayYear,
    required this.onLongPress,
  });

  static const double _numeral = 72;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final dated = year.year > 0;
    final label = dated ? '${year.year}' : 'Undated';
    final heard = year.albums.fold(0, (n, a) => n + history.playsOf(a));
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _numeral + Space.gutter,
            child: CupertinoClickable(
              onTap: () => onPlayYear(year),
              scaleFactor: 0.96,
              semanticLabel: 'Play $label, ${year.songs} ${year.songs == 1 ? 'song' : 'songs'}',
              child: Padding(
                padding: const EdgeInsets.only(left: Space.gutter, top: Space.md),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: dated
                        ? naviText(
                            21,
                            FontWeight.w700,
                            heard > 0 ? t.textPrimary : t.textSecondary,
                            height: 1.1,
                            tabular: true,
                          )
                        : t.footnote,
                  ),
                ),
              ),
            ),
          ),
          // The spine: a hairline with a dot per year, broken at the ends.
          SizedBox(
            width: 17,
            child: CustomPaint(
              painter: _SpinePainter(
                color: t.separatorOpaque,
                dot: heard > 0 ? t.accent : t.accentDim,
                first: first,
                last: last,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.gutter, Space.md),
              child: Wrap(
                spacing: Space.md,
                runSpacing: Space.md,
                children: [
                  for (final a in year.albums)
                    _Release(
                      album: a,
                      size: size,
                      history: history,
                      tokens: t,
                      url: coverUrl(a),
                      onOpen: onOpen,
                      onLongPress: onLongPress,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpinePainter extends CustomPainter {
  final Color color;
  final Color dot;
  final bool first;
  final bool last;
  const _SpinePainter({required this.color, required this.dot, required this.first, required this.last});

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    const dotY = Space.md + 10.0;
    final line = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(x, first ? dotY : 0), Offset(x, last ? dotY : size.height), line);
    canvas.drawCircle(Offset(x, dotY), 3, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_SpinePainter old) =>
      old.color != color || old.dot != dot || old.first != first || old.last != last;
}

class _Release extends StatelessWidget {
  final Album album;
  final double size;
  final ArtistHistory history;
  final AppThemeTokens tokens;
  final String url;
  final ValueChanged<Album> onOpen;
  final void Function(Album) onLongPress;
  const _Release({
    required this.album,
    required this.size,
    required this.history,
    required this.tokens,
    required this.url,
    required this.onOpen,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final plays = history.playsOf(album);
    return CupertinoClickable(
      onTap: () => onOpen(album),
      onLongPress: () => onLongPress(album),
      scaleFactor: 0.96,
      semanticLabel: '${album.name}${album.year > 0 ? ', ${album.year}' : ''}${plays > 0 ? ', $plays plays' : ''}',
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverArt(url: url, size: size, radius: Radii.cover, placeholderIcon: NaviGlyph.library),
            const SizedBox(height: Space.xs),
            Text(
              album.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.caption1.copyWith(color: t.textPrimary),
            ),
            if (plays > 0) Text(plays == 1 ? '1 play' : '$plays plays', style: t.caption1),
          ],
        ),
      ),
    );
  }
}

/// Your first and latest play as one line: a dot at each end of a hairline
/// with the month under it. The story of how long you have known the artist.
class _ListeningSpan extends StatelessWidget {
  final DateTime first;
  final DateTime last;
  const _ListeningSpan({required this.first, required this.last});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    Widget end(String caption, DateTime d, CrossAxisAlignment a) => Column(
      crossAxisAlignment: a,
      children: [
        Text(caption, style: t.caption1),
        Text(_monthYear(d), style: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
      ],
    );
    return Column(
      children: [
        SizedBox(
          height: 8,
          width: double.infinity,
          child: CustomPaint(painter: _SpanPainter(line: t.separatorOpaque, dot: t.accent)),
        ),
        const SizedBox(height: Space.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            end('First played', first, CrossAxisAlignment.start),
            end('Latest', last, CrossAxisAlignment.end),
          ],
        ),
      ],
    );
  }
}

class _SpanPainter extends CustomPainter {
  final Color line;
  final Color dot;
  const _SpanPainter({required this.line, required this.dot});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(Offset(4, y), Offset(size.width - 4, y), Paint()..color = line..strokeWidth = 1);
    final p = Paint()..color = dot;
    canvas.drawCircle(Offset(4, y), 4, p);
    canvas.drawCircle(Offset(size.width - 4, y), 4, p);
  }

  @override
  bool shouldRepaint(_SpanPainter old) => old.line != line || old.dot != dot;
}
