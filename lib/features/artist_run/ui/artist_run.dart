
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
              LayoutBuilder(
                builder: (context, c) {
                  final figures = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      stat(compactCount(history.plays), history.plays == 1 ? 'play' : 'plays'),
                      stat(listeningTime(history.minutes), 'listening'),
                    ],
                  );
                  final span = history.first != null && history.last != null
                      ? _ListeningSpan(first: history.first!, last: history.last!)
                      : null;
                  final mostPlayed = top == null
                      ? null
                      : Text.rich(
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
                        );
                  // Wide: the counts on the left, the story of how long you have
                  // known them on the right, so the page margin is used and the
                  // block does not leave a hole beside it.
                  if (c.maxWidth >= 720) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [figures, if (mostPlayed != null) ...[const SizedBox(height: Space.md), mostPlayed]],
                          ),
                        ),
                        const SizedBox(width: Space.huge),
                        Expanded(child: Padding(padding: const EdgeInsets.only(top: Space.sm), child: span ?? const SizedBox.shrink())),
                      ],
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        figures,
                        if (span != null) ...[const SizedBox(height: Space.lg), span],
                        if (mostPlayed != null) ...[const SizedBox(height: Space.md), mostPlayed],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The discography as a year spine: a big tabular numeral per year, a hairline
/// down the page, and that year's covers. Under each cover its name and, if you
/// have played it, the plain count ("9 plays"); years you have heard are bright.
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
            Text(_together(first, last), style: t.footnote.copyWith(color: t.textSecondary)),
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

/// "3 yr 3 mo": how long between first and latest play, in plain words.
String _together(DateTime a, DateTime b) {
  final months = (b.year - a.year) * 12 + b.month - a.month;
  final y = months ~/ 12;
  final m = months % 12;
  if (y == 0) return m <= 1 ? 'this month' : '$m months';
  return m == 0 ? '$y yr' : '$y yr $m mo';
}
