import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/navivibe_replay_provider.dart';
import '../widgets/mini_player.dart';
import '../widgets/navi_ui.dart';

// =============================================================================
// NavivibeReplayScreen — Apple Music-style yearly Replay.
//
// Design philosophy: compact, content-dense, NO bloated cards.
//   • Hero section: accent-coloured backdrop, giant listening-time number
//   • Quick stats: tight pill row (4 numbers)
//   • Top track + artist: slim 56px rows with icon thumbnails
//   • Genre: segmented bar, single compact card
//   • Peak hour: small 36px waveform inline
//   • Monthly: horizontal scroll strip of small tiles (not a 2-col grid)
//   • Track/artist lists: 48px rows, Apple Music spacing
// =============================================================================

class NavivibeReplayScreen extends ConsumerStatefulWidget {
  const NavivibeReplayScreen({super.key});

  @override
  ConsumerState<NavivibeReplayScreen> createState() =>
      _NavivibeReplayScreenState();
}

class _NavivibeReplayScreenState extends ConsumerState<NavivibeReplayScreen> {
  int? _selectedYear;

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final replayAsync = ref.watch(navivibeYearlyReplayProvider(_selectedYear));
    final topPad = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tokens.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        body: Stack(
          children: [
            replayAsync.when(
              data: (replay) => _ReplayBody(
                replay: replay,
                selectedYear: _selectedYear ?? replay.year,
                topPad: topPad,
                onBack: () => Navigator.pop(context),
                onYearSelected: (y) => setState(() => _selectedYear = y),
              ),
              loading: () => _LoadingBody(
                topPad: topPad,
                onBack: () => Navigator.pop(context),
              ),
              error: (e, _) => _ErrorBody(
                topPad: topPad,
                error: e,
                onBack: () => Navigator.pop(context),
                onRetry: () => ref
                    .invalidate(navivibeYearlyReplayProvider(_selectedYear)),
              ),
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ReplayBody
// ---------------------------------------------------------------------------

class _ReplayBody extends StatelessWidget {
  final YearlyReplayResponse replay;
  final int selectedYear;
  final double topPad;
  final VoidCallback onBack;
  final ValueChanged<int> onYearSelected;

  const _ReplayBody({
    required this.replay,
    required this.selectedYear,
    required this.topPad,
    required this.onBack,
    required this.onYearSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Cinematic hero (accent backdrop + giant number) ──────────────────
        SliverToBoxAdapter(
          child: _HeroSection(
            replay: replay,
            topPad: topPad,
            onBack: onBack,
            availableYears: replay.availableYears,
            selectedYear: selectedYear,
            onYearSelected: onYearSelected,
          ),
        ),

        // ── Quick stat pills ─────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _StatPillRow(replay: replay),
          ).animate(delay: 60.ms).fadeIn(duration: 350.ms),
        ),

        // ── Top track ────────────────────────────────────────────────────────
        if (replay.topTracks.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _SpotlightRow(
                label: 'TOP TRACK',
                title: replay.topTracks.first.title,
                subtitle: replay.topTracks.first.artist,
                trailing: '${replay.topTracks.first.playCount} plays',
                icon: Icons.music_note_rounded,
                iconColor: tokens.accent,
              ),
            ).animate(delay: 90.ms).fadeIn(duration: 350.ms),
          ),

        // ── Top artist ───────────────────────────────────────────────────────
        if (replay.topArtists.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SpotlightRow(
                label: 'TOP ARTIST',
                title: replay.topArtists.first.artist,
                subtitle: '${replay.topArtists.first.uniqueSongs} songs',
                trailing: _fmtMin(replay.topArtists.first.totalMinutes),
                icon: Icons.person_rounded,
                iconColor: tokens.textMuted,
                circle: true,
              ),
            ).animate(delay: 120.ms).fadeIn(duration: 350.ms),
          ),

        // ── Genre breakdown ──────────────────────────────────────────────────
        if (replay.topGenres.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _GenreCard(genres: replay.topGenres),
            ).animate(delay: 150.ms).fadeIn(duration: 350.ms),
          ),

        // ── Peak hour ────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _PeakHourRow(
              peakHour: replay.peakHourIst,
              heatmap: replay.hourlyHeatmap,
            ),
          ).animate(delay: 180.ms).fadeIn(duration: 350.ms),
        ),

        // ── Month-by-month horizontal strip ─────────────────────────────────
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Text(
                  'MONTH BY MONTH',
                  style: tokens
                      .textStyle(10, FontWeight.w700, tokens.textMuted)
                      .copyWith(letterSpacing: 1.4),
                ),
              ),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemCount: replay.monthlyCards.length,
                  itemBuilder: (ctx, i) {
                    final card = replay.monthlyCards[i];
                    return _MonthTile(
                      card: card,
                      onTap: () =>
                          _openMonthDetail(ctx, card.year, card.month),
                    )
                        .animate(delay: (i * 35).clamp(0, 280).ms)
                        .fadeIn(duration: 280.ms)
                        .scale(
                          begin: const Offset(0.92, 0.92),
                          end: const Offset(1, 1),
                        );
                  },
                ),
              ),
            ],
          ).animate(delay: 210.ms).fadeIn(duration: 350.ms),
        ),

        // ── Top tracks list ──────────────────────────────────────────────────
        if (replay.topTracks.length > 1) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              label: 'TOP TRACKS',
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _TrackRow(track: replay.topTracks[i], rank: i + 1)
                  .animate(delay: (i * 30).clamp(0, 250).ms)
                  .fadeIn(duration: 260.ms)
                  .slideX(begin: 0.03, end: 0),
              childCount: replay.topTracks.length,
            ),
          ),
        ],

        // ── Top artists list ─────────────────────────────────────────────────
        if (replay.topArtists.length > 1) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              label: 'TOP ARTISTS',
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) =>
                  _ArtistRow(artist: replay.topArtists[i], rank: i + 1)
                      .animate(delay: (i * 30).clamp(0, 250).ms)
                      .fadeIn(duration: 260.ms)
                      .slideX(begin: 0.03, end: 0),
              childCount: math.min(replay.topArtists.length, 5),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 160)),
      ],
    );
  }

  void _openMonthDetail(BuildContext ctx, int year, int month) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MonthDetailSheet(year: year, month: month),
    );
  }

  static String _fmtMin(double min) {
    final h = (min / 60).floor();
    final m = (min % 60).round();
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ---------------------------------------------------------------------------
// Hero section — accent backdrop, large number, nav bar embedded
// ---------------------------------------------------------------------------

class _HeroSection extends StatelessWidget {
  final YearlyReplayResponse replay;
  final double topPad;
  final VoidCallback onBack;
  final List<int> availableYears;
  final int selectedYear;
  final ValueChanged<int> onYearSelected;

  const _HeroSection({
    required this.replay,
    required this.topPad,
    required this.onBack,
    required this.availableYears,
    required this.selectedYear,
    required this.onYearSelected,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);

    return Container(
      decoration: BoxDecoration(
        color: tokens.accent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nav bar
          Padding(
            padding: EdgeInsets.fromLTRB(4, topPad + 4, 12, 0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: tokens.isLight ? Colors.white : Colors.black,
                    size: 28,
                  ),
                  onPressed: onBack,
                ),
                Expanded(
                  child: Text(
                    'Replay',
                    textAlign: TextAlign.center,
                    style: tokens
                        .textStyle(
                          16,
                          FontWeight.w700,
                          tokens.isLight ? Colors.white : Colors.black,
                        )
                        .copyWith(letterSpacing: -0.3),
                  ),
                ),
                if (availableYears.length > 1)
                  _YearPicker(
                    years: availableYears,
                    selected: selectedYear,
                    onChanged: onYearSelected,
                    light: tokens.isLight,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '$selectedYear',
                      style: tokens.textStyle(
                        13,
                        FontWeight.w700,
                        (tokens.isLight ? Colors.white : Colors.black)
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Big number
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Minutes',
                  style: tokens.textStyle(
                    13,
                    FontWeight.w500,
                    (tokens.isLight ? Colors.white : Colors.black)
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmt(replay.totalPlays > 0
                      ? (replay.totalMinutes).round()
                      : 0),
                  style: tokens
                      .textStyle(
                        56,
                        FontWeight.w900,
                        tokens.isLight ? Colors.white : Colors.black,
                      )
                      .copyWith(letterSpacing: -2.5, height: 1.0),
                ),
              ],
            ),
          ),

          // Top song / artist preview row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              children: [
                if (replay.topTracks.isNotEmpty)
                  Expanded(
                    child: _HeroPreviewItem(
                      label: 'Top Song',
                      title: replay.topTracks.first.title,
                      subtitle: replay.topTracks.first.artist,
                      icon: Icons.music_note_rounded,
                      light: tokens.isLight,
                      tokens: tokens,
                    ),
                  ),
                if (replay.topTracks.isNotEmpty &&
                    replay.topArtists.isNotEmpty)
                  Container(
                    width: 0.5,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: (tokens.isLight ? Colors.white : Colors.black)
                        .withValues(alpha: 0.25),
                  ),
                if (replay.topArtists.isNotEmpty)
                  Expanded(
                    child: _HeroPreviewItem(
                      label: 'Top Artist',
                      title: replay.topArtists.first.artist,
                      subtitle:
                          '${replay.topArtists.first.uniqueSongs} songs',
                      icon: Icons.person_rounded,
                      light: tokens.isLight,
                      tokens: tokens,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  static String _fmt(int v) {
    if (v >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(1)}M';
    }
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return '$v';
  }
}

class _HeroPreviewItem extends StatelessWidget {
  final String label;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool light;
  final AppThemeTokens tokens;

  const _HeroPreviewItem({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.light,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final fg = light ? Colors.white : Colors.black;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: fg.withValues(alpha: 0.85), size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: tokens
                    .textStyle(9, FontWeight.w600, fg.withValues(alpha: 0.6))
                    .copyWith(letterSpacing: 0.8),
              ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    tokens.textStyle(12, FontWeight.w700, fg),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.textStyle(
                    11, FontWeight.w400, fg.withValues(alpha: 0.65)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Year picker (transparent pill on accent bg)
// ---------------------------------------------------------------------------

class _YearPicker extends StatelessWidget {
  final List<int> years;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool light;

  const _YearPicker({
    required this.years,
    required this.selected,
    required this.onChanged,
    required this.light,
  });

  @override
  Widget build(BuildContext context) {
    final fg = light ? Colors.white : Colors.black;
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: fg.withValues(alpha: 0.22), width: 0.7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$selected',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: fg),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more_rounded, size: 14, color: fg),
          ],
        ),
      ),
    );
  }

  void _show(BuildContext ctx) {
    final tokens = ThemeTokens.of(ctx);
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: tokens.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: tokens.outline,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Text('Select Year',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary)),
            const SizedBox(height: 8),
            ...years.map((y) => ListTile(
                  title: Text('$y',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: y == selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: y == selected
                            ? tokens.accent
                            : tokens.textPrimary,
                      )),
                  trailing: y == selected
                      ? Icon(Icons.check_rounded,
                          color: tokens.accent, size: 18)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    onChanged(y);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick stat pill row (4 compact pills)
// ---------------------------------------------------------------------------

class _StatPillRow extends StatelessWidget {
  final YearlyReplayResponse replay;
  const _StatPillRow({required this.replay});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Row(
      children: [
        _Pill(label: 'Plays', value: _fmt(replay.totalPlays), tokens: tokens),
        const SizedBox(width: 8),
        _Pill(label: 'Days', value: '${replay.listeningDays}', tokens: tokens),
        const SizedBox(width: 8),
        _Pill(label: 'Songs', value: _fmt(replay.uniqueSongs), tokens: tokens),
        const SizedBox(width: 8),
        _Pill(
            label: 'Artists',
            value: '${replay.uniqueArtists}',
            tokens: tokens),
      ],
    );
  }

  static String _fmt(int v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '$v';
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final String value;
  final AppThemeTokens tokens;
  const _Pill(
      {required this.label, required this.value, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: tokens.outline.withValues(alpha: 0.6), width: 0.5),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: tokens
                  .textStyle(15, FontWeight.w800, tokens.textPrimary)
                  .copyWith(letterSpacing: -0.4),
            ),
            const SizedBox(height: 1),
            Text(label,
                style:
                    tokens.textStyle(10, FontWeight.w400, tokens.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spotlight row — compact 56px row (top track / top artist)
// ---------------------------------------------------------------------------

class _SpotlightRow extends StatelessWidget {
  final String label;
  final String title;
  final String subtitle;
  final String trailing;
  final IconData icon;
  final Color iconColor;
  final bool circle;

  const _SpotlightRow({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.icon,
    required this.iconColor,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: tokens.outline.withValues(alpha: 0.6), width: 0.5),
      ),
      child: Row(
        children: [
          // Icon thumbnail
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius:
                  circle ? null : BorderRadius.circular(8),
              shape: circle ? BoxShape.circle : BoxShape.rectangle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: tokens
                      .textStyle(9, FontWeight.w600, tokens.accent)
                      .copyWith(letterSpacing: 1.0),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tokens.textStyle(13, FontWeight.w700, tokens.textPrimary),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tokens.textStyle(11, FontWeight.w400, tokens.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trailing,
            style: tokens
                .textStyle(12, FontWeight.w600, tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Genre card — compact animated bars
// ---------------------------------------------------------------------------

class _GenreCard extends StatelessWidget {
  final List<ReplayGenre> genres;
  const _GenreCard({required this.genres});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final top = genres.take(5).toList();
    final maxPct = top.isEmpty ? 1.0 : top.first.pct;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: tokens.outline.withValues(alpha: 0.6), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR SOUND',
            style: tokens
                .textStyle(9, FontWeight.w600, tokens.textMuted)
                .copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 10),
          ...top.asMap().entries.map((e) {
            final i = e.key;
            final g = e.value;
            final fill =
                maxPct > 0 ? (g.pct / maxPct).clamp(0.0, 1.0) : 0.0;
            final opacity = 1.0 - i * 0.18;
            final color = tokens.accent.withValues(alpha: opacity);
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      g.genre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.textStyle(
                          11, FontWeight.w500, tokens.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: fill),
                        duration:
                            Duration(milliseconds: 450 + i * 60),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 6,
                          backgroundColor: tokens.bgElevated,
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${g.pct.toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: tokens.textStyle(
                          10, FontWeight.w600, color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Peak hour — compact inline waveform
// ---------------------------------------------------------------------------

class _PeakHourRow extends StatelessWidget {
  final int peakHour;
  final Map<String, int> heatmap;
  const _PeakHourRow({required this.peakHour, required this.heatmap});

  static String _label(int h) {
    if (h == 0) return '12am';
    if (h < 12) return '${h}am';
    if (h == 12) return '12pm';
    return '${h - 12}pm';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final counts =
        List.generate(24, (h) => heatmap[h.toString()] ?? 0);
    final maxCount =
        counts.isEmpty ? 1 : counts.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: tokens.outline.withValues(alpha: 0.6), width: 0.5),
      ),
      child: Row(
        children: [
          // Left: label + hour
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PEAK HOUR',
                style: tokens
                    .textStyle(9, FontWeight.w600, tokens.textMuted)
                    .copyWith(letterSpacing: 1.0),
              ),
              const SizedBox(height: 2),
              Text(
                _label(peakHour),
                style: tokens.textStyle(
                    18, FontWeight.w800, tokens.accent),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Right: waveform bars
          Expanded(
            child: SizedBox(
              height: 36,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(24, (h) {
                  final frac = maxCount > 0
                      ? counts[h] / maxCount
                      : 0.0;
                  final isPeak = h == peakHour;
                  return Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 0.8),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: frac),
                        duration:
                            Duration(milliseconds: 350 + h * 7),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, _) => Container(
                          height: math.max(2, 36 * v),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: isPeak
                                ? tokens.accent
                                : tokens.accent.withValues(
                                    alpha: 0.2 + 0.45 * v),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Month tile — small horizontal-scroll tile (NOT a giant grid card)
// ---------------------------------------------------------------------------

class _MonthTile extends StatelessWidget {
  final ReplayMonthlyCard card;
  final VoidCallback onTap;
  const _MonthTile({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);

    return CupertinoClickable(
      onTap: onTap,
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          color: tokens.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: tokens.outline.withValues(alpha: 0.6), width: 0.5),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month name + active dot
            Row(
              children: [
                Text(
                  card.monthName.substring(0, 3).toUpperCase(),
                  style: tokens
                      .textStyle(10, FontWeight.w800, tokens.accent)
                      .copyWith(letterSpacing: 0.8),
                ),
                const Spacer(),
                if (card.totalPlays > 0)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${card.totalPlays}',
              style: tokens
                  .textStyle(17, FontWeight.w800, tokens.textPrimary)
                  .copyWith(letterSpacing: -0.5),
            ),
            Text(
              'plays',
              style:
                  tokens.textStyle(9, FontWeight.w400, tokens.textMuted),
            ),
            const Spacer(),
            if (card.topTrack != null)
              Text(
                card.topTrack!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    tokens.textStyle(10, FontWeight.w600, tokens.textSecondary),
              )
            else
              Text('—',
                  style: tokens.textStyle(
                      10, FontWeight.w400, tokens.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  final EdgeInsets padding;
  const _SectionHeader({required this.label, required this.padding});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: padding,
      child: Text(
        label,
        style: tokens
            .textStyle(10, FontWeight.w700, tokens.textMuted)
            .copyWith(letterSpacing: 1.4),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Track row — 48px compact Apple Music style
// ---------------------------------------------------------------------------

class _TrackRow extends StatelessWidget {
  final ReplayTrack track;
  final int rank;
  const _TrackRow({required this.track, required this.rank});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final isTop3 = rank <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: tokens.outline.withValues(alpha: 0.35), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: tokens
                  .textStyle(
                    isTop3 ? 17 : 13,
                    FontWeight.w900,
                    isTop3 ? tokens.accent : tokens.textMuted,
                  )
                  .copyWith(letterSpacing: -0.3),
            ),
          ),
          const SizedBox(width: 12),
          // Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.bgElevated,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.music_note_rounded,
                size: 16, color: tokens.textMuted),
          ),
          const SizedBox(width: 10),
          // Title + artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.textStyle(
                      13, FontWeight.w600, tokens.textPrimary),
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tokens.textStyle(11, FontWeight.w400, tokens.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Play count + time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${track.playCount}×',
                style: tokens.textStyle(
                    12, FontWeight.w600, tokens.textSecondary),
              ),
              Text(
                _fmtMin(track.totalMinutes),
                style: tokens.textStyle(
                    10, FontWeight.w400, tokens.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtMin(double m) {
    final h = (m / 60).floor();
    final min = (m % 60).round();
    if (h > 0) return '${h}h${min}m';
    return '${min}m';
  }
}

// ---------------------------------------------------------------------------
// Artist row — 48px compact
// ---------------------------------------------------------------------------

class _ArtistRow extends StatelessWidget {
  final ReplayArtist artist;
  final int rank;
  const _ArtistRow({required this.artist, required this.rank});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final isTop3 = rank <= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: tokens.outline.withValues(alpha: 0.35), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: tokens.textStyle(
                isTop3 ? 17 : 13,
                FontWeight.w900,
                isTop3 ? tokens.accent : tokens.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.bgElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_rounded,
                size: 18, color: tokens.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.textStyle(
                      13, FontWeight.w600, tokens.textPrimary),
                ),
                Text(
                  '${artist.uniqueSongs} songs · ${artist.playCount} plays',
                  style: tokens.textStyle(
                      11, FontWeight.w400, tokens.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtMin(artist.totalMinutes),
            style: tokens.textStyle(
                12, FontWeight.w600, tokens.textSecondary),
          ),
        ],
      ),
    );
  }

  static String _fmtMin(double m) {
    final h = (m / 60).floor();
    final min = (m % 60).round();
    if (h > 0) return '${h}h${min}m';
    return '${min}m';
  }
}

// ---------------------------------------------------------------------------
// Monthly detail sheet (bottom sheet) — unchanged data, tighter UI
// ---------------------------------------------------------------------------

class _MonthDetailSheet extends ConsumerWidget {
  final int year;
  final int month;
  const _MonthDetailSheet({required this.year, required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    final key = (year: year, month: month);
    final async = ref.watch(navivibeMonthlyReplayProvider(key));

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: tokens.bgBase,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                      color: tokens.outline,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Expanded(
              child: async.when(
                data: (data) =>
                    _MonthDetailContent(data: data, scrollController: sc),
                loading: () => Center(
                  child: CircularProgressIndicator(
                      color: tokens.accent, strokeWidth: 2),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          color: tokens.textMuted, size: 36),
                      const SizedBox(height: 12),
                      Text('Could not load month data',
                          style: TextStyle(color: tokens.textMuted)),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(navivibeMonthlyReplayProvider(key)),
                        child: Text('Retry',
                            style: TextStyle(color: tokens.accent)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthDetailContent extends StatelessWidget {
  final MonthlyReplayResponse data;
  final ScrollController scrollController;
  const _MonthDetailContent(
      {required this.data, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      children: [
        // Header
        Text(
          '${data.monthName} ${data.year}',
          style: tokens
              .textStyle(24, FontWeight.w900, tokens.textPrimary)
              .copyWith(letterSpacing: -0.8),
        ),
        const SizedBox(height: 12),

        // Quick stats pills — same _StatPillRow pattern
        Row(
          children: [
            _Pill(
                label: 'Plays',
                value: '${data.totalPlays}',
                tokens: tokens),
            const SizedBox(width: 6),
            _Pill(
                label: 'Time',
                value: data.totalHoursLabel,
                tokens: tokens),
            const SizedBox(width: 6),
            _Pill(
                label: 'Songs',
                value: '${data.uniqueSongs}',
                tokens: tokens),
            const SizedBox(width: 6),
            _Pill(
                label: 'Streak',
                value: '${data.streakDays}d 🔥',
                tokens: tokens),
          ],
        ),
        const SizedBox(height: 14),

        // Daily mini chart
        if (data.dailyBreakdown.isNotEmpty) ...[
          _SheetSection('DAILY ACTIVITY'),
          const SizedBox(height: 6),
          _DailyMiniChart(days: data.dailyBreakdown),
          const SizedBox(height: 14),
        ],

        // Top tracks
        if (data.topTracks.isNotEmpty) ...[
          _SheetSection('TOP TRACKS'),
          const SizedBox(height: 4),
          ...data.topTracks.asMap().entries.map(
                (e) => _TrackRow(track: e.value, rank: e.key + 1)
                    .animate(delay: (e.key * 25).ms)
                    .fadeIn(duration: 220.ms),
              ),
          const SizedBox(height: 14),
        ],

        // Top artists
        if (data.topArtists.isNotEmpty) ...[
          _SheetSection('TOP ARTISTS'),
          const SizedBox(height: 4),
          ...data.topArtists.take(5).toList().asMap().entries.map(
                (e) => _ArtistRow(artist: e.value, rank: e.key + 1)
                    .animate(delay: (e.key * 25).ms)
                    .fadeIn(duration: 220.ms),
              ),
          const SizedBox(height: 14),
        ],

        // Recent plays
        if (data.recentPlays.isNotEmpty) ...[
          _SheetSection('RECENT PLAYS'),
          const SizedBox(height: 4),
          ...data.recentPlays.take(10).map((p) => _RecentPlayRow(play: p)),
        ],
      ],
    );
  }
}

class _SheetSection extends StatelessWidget {
  final String text;
  const _SheetSection(this.text);

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Row(
      children: [
        Text(
          text,
          style: tokens
              .textStyle(10, FontWeight.w700, tokens.textMuted)
              .copyWith(letterSpacing: 1.3),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Container(height: 0.5, color: tokens.outline)),
      ],
    );
  }
}

class _DailyMiniChart extends StatelessWidget {
  final List<ReplayDailyEntry> days;
  const _DailyMiniChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final maxPlays =
        days.map((d) => d.playCount).reduce(math.max).toDouble();
    final show = days.length <= 31 ? days : days.sublist(days.length - 31);

    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: show.map((d) {
          final frac = maxPlays > 0 ? d.playCount / maxPlays : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: frac),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Container(
                  height: math.max(2, 44 * v),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: tokens.accent.withValues(alpha: 0.3 + 0.7 * v),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RecentPlayRow extends StatelessWidget {
  final ReplayRecentPlay play;
  const _RecentPlayRow({required this.play});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    String timeStr = '';
    try {
      final dt = DateTime.parse(play.playedAtIst);
      timeStr =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: tokens.outline.withValues(alpha: 0.35), width: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: tokens.bgElevated,
                borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.music_note_rounded,
                size: 14, color: tokens.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  play.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.textStyle(
                      12, FontWeight.w600, tokens.textPrimary),
                ),
                Text(
                  play.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.textStyle(
                      10, FontWeight.w400, tokens.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (timeStr.isNotEmpty)
                Text(timeStr,
                    style: tokens.textStyle(
                        10, FontWeight.w400, tokens.textMuted)),
              const SizedBox(height: 3),
              SizedBox(
                width: 36,
                height: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: play.listenRatio.clamp(0.0, 1.0),
                    backgroundColor: tokens.bgElevated,
                    valueColor: AlwaysStoppedAnimation(
                      play.listenRatio >= 0.8
                          ? tokens.accent
                          : play.listenRatio >= 0.5
                              ? tokens.accent.withValues(alpha: 0.55)
                              : tokens.textMuted.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  final double topPad;
  final VoidCallback onBack;
  const _LoadingBody({required this.topPad, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Column(
      children: [
        // Mock hero bg
        Container(
          color: tokens.accent.withValues(alpha: 0.8),
          padding: EdgeInsets.fromLTRB(4, topPad + 4, 12, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: tokens.isLight ? Colors.white : Colors.black,
                        size: 28),
                    onPressed: onBack,
                  ),
                  const Spacer(),
                  Text('Replay',
                      style: tokens.textStyle(
                          16,
                          FontWeight.w700,
                          tokens.isLight ? Colors.white : Colors.black)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NaviSkeleton(height: 11, width: 90),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: NaviSkeleton(height: 52, width: 180),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // Pill skeletons
              Row(
                children: List.generate(
                  4,
                  (_) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: tokens.bgSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Spotlight row skeletons
              ...List.generate(
                2,
                (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: tokens.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Genre card skeleton
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorBody extends StatelessWidget {
  final double topPad;
  final Object error;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  const _ErrorBody({
    required this.topPad,
    required this.error,
    required this.onBack,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Column(
      children: [
        SizedBox(height: topPad + 16),
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: tokens.textPrimary, size: 30),
              onPressed: onBack,
            ),
            const Spacer(),
            Text('Replay', style: tokens.headingSm),
            const SizedBox(width: 48),
          ],
        ),
        const Spacer(),
        Icon(Icons.wifi_off_rounded, color: tokens.textMuted, size: 48),
        const SizedBox(height: 16),
        Text('Could not load Replay',
            style:
                tokens.textStyle(16, FontWeight.w600, tokens.textPrimary)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            error.toString().contains('401')
                ? 'Authentication failed. Check your server credentials.'
                : 'Make sure your Navivibe server is reachable.',
            textAlign: TextAlign.center,
            style:
                tokens.textStyle(13, FontWeight.w400, tokens.textMuted),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: tokens.accent,
            foregroundColor: tokens.isLight ? Colors.white : Colors.black,
            shape: const StadiumBorder(),
            elevation: 0,
          ),
          onPressed: onRetry,
          child: Text('Retry',
              style: tokens.textStyle(
                  14,
                  FontWeight.w700,
                  tokens.isLight ? Colors.white : Colors.black)),
        ),
        const Spacer(),
      ],
    );
  }
}
