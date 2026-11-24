import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../../core/theme.dart';
import '../../../models/composer.dart' show nameKey;
import '../../../utils/format.dart';
import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/media.dart';
import '../logic/credit_index.dart';
import 'credit_screen.dart';
import 'film_screen.dart';

void openFilm(BuildContext context, String filmKey, String title) =>
    navigateInApp(context, FilmScreen(filmKey: filmKey, title: title));

void openPerson(BuildContext context, String name, {CreditRole? role}) =>
    navigateInApp(context, CreditScreen(personKey: nameKey(name), name: name, role: role));

/// From Now Playing: close the player first, then open the page in the tab underneath.
void openPersonFromPlayer(BuildContext context, String name, {CreditRole? role}) {
  Navigator.of(context).maybePop();
  openPerson(context, name, role: role);
}

/// The round monogram-free tile that stands in for a person.
class PersonGlyph extends StatelessWidget {
  final double size;
  const PersonGlyph({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: t.bgElevated, shape: BoxShape.circle),
      child: NaviIcon(NaviGlyph.person, size: size * 0.42, color: t.textMuted),
    );
  }
}

/// The year as a quiet block where a film's cover would be: films have no art of their own.
class FilmGlyph extends StatelessWidget {
  final int? year;
  final double size;
  const FilmGlyph({super.key, this.year, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.bgElevated, borderRadius: BorderRadius.circular(Radii.cover)),
      child: year == null
          ? NaviIcon(NaviGlyph.note, size: size * 0.42, color: t.textMuted)
          : Text("'${(year! % 100).toString().padLeft(2, '0')}", style: t.footnote.copyWith(fontWeight: FontWeight.w600, color: t.textSecondary)),
    );
  }
}

class FilmRow extends StatelessWidget {
  final FilmEntry film;
  final bool showSeparator;
  final VoidCallback? onBeforeOpen;

  /// Overrides the default subtitle (year · song count).
  final String? subtitle;
  const FilmRow({super.key, required this.film, this.showSeparator = true, this.onBeforeOpen, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final md = film.musicDirectors;
    return CollectionRow(
      title: film.title,
      subtitle: subtitle ??
          [if (film.year != null) '${film.year}', if (md.isNotEmpty) md.first, songCount(film.songs.length)].join(' · '),
      leading: FilmGlyph(year: film.year),
      showSeparator: showSeparator,
      onTap: () {
        onBeforeOpen?.call();
        openFilm(context, film.key, film.title);
      },
    );
  }
}

class PersonRow extends StatelessWidget {
  final PersonEntry person;
  final CreditRole? role;
  final bool showSeparator;
  final VoidCallback? onBeforeOpen;
  const PersonRow({super.key, required this.person, this.role, this.showSeparator = true, this.onBeforeOpen});

  @override
  Widget build(BuildContext context) {
    final n = role == null ? person.songs.length : person.byRole[role]?.length ?? 0;
    return CollectionRow(
      title: person.name,
      subtitle: role == null ? [for (final r in person.roles) r.label].join(' · ') : songCount(n),
      leading: const PersonGlyph(),
      showSeparator: showSeparator,
      onTap: () {
        onBeforeOpen?.call();
        openPerson(context, person.name, role: role);
      },
    );
  }
}

/// A line of text that is a name you can open: "Music director  Anirudh Ravichander ›".
class CreditLine extends StatelessWidget {
  final String label;
  final List<String> names;
  final bool showSeparator;
  const CreditLine({super.key, required this.label, required this.names, this.showSeparator = true});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final gutter = pageGutter(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: gutter, vertical: Space.md),
      decoration: BoxDecoration(
        border: showSeparator ? Border(bottom: BorderSide(color: t.outline, width: 0.5)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 112, child: Text(label, style: t.footnote.copyWith(color: t.textMuted))),
          Expanded(
            child: Wrap(
              spacing: Space.md,
              runSpacing: Space.xs,
              children: [
                for (final n in names)
                  CupertinoClickable(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      openPerson(context, n);
                    },
                    semanticLabel: '$label: $n',
                    child: Text(n, style: t.body.copyWith(color: t.textPrimary)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades and lifts a child in once, [index] steps after the page opens. Nothing moves when the
/// system asks for reduced motion.
class RiseIn extends StatelessWidget {
  final int index;
  final Widget child;
  const RiseIn({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + 70 * index.clamp(0, 6)),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: c)),
      child: child,
    );
  }
}

/// Role filter under a credit page's title: plain words, the chosen one white with an underline.
class RoleTabs extends StatelessWidget {
  final List<CreditRole> roles;
  final CreditRole? selected;
  final Map<CreditRole, int> counts;
  final int total;
  final ValueChanged<CreditRole?> onSelect;
  const RoleTabs({super.key, required this.roles, required this.selected, required this.counts, required this.total, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    Widget tab(String label, bool on, VoidCallback tap) => CupertinoClickable(
          onTap: tap,
          semanticLabel: label,
          child: Padding(
            padding: const EdgeInsets.only(right: Space.lg, top: Space.sm, bottom: Space.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: t.subheadline.copyWith(color: on ? t.textPrimary : t.textMuted, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 2,
                  width: on ? 22 : 0,
                  color: t.textPrimary,
                ),
              ],
            ),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: pageGutter(context)),
      child: Row(children: [
        tab('All $total', selected == null, () => onSelect(null)),
        for (final r in roles) tab('${r.heading} ${counts[r] ?? 0}', selected == r, () => onSelect(r)),
      ]),
    );
  }
}
