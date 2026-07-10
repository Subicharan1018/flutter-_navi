import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/navivibe_replay_provider.dart';
import '../widgets/mini_player.dart';

// =============================================================================
// NavivibeReplayScreen — Apple Music Replay-style yearly review.
//
// Design:
//   • Full-screen accent gradient hero with giant total-minutes number
//   • Year watermark ('25) rendered large and translucent behind stats
//   • Top Song / Artist / Album previews inline on gradient
//   • 2×2 quick-stat grid with divider lines
//   • Enhanced genre bars with colour dots
//   • Taller monthly carousel tiles with gradient tint
//   • Bold rank badges on track + artist lists
// =============================================================================

// ── Helpers ──────────────────────────────────────────────────────────────────

String _fmtComma(int v) {
  if (v < 1000) return '$v';
  final s = v.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _fmtMin(double min) {
  final h = (min / 60).floor();
  final m = (min % 60).round();
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

/// Compute a hero-grade gradient pair from any accent colour.
/// Clamps lightness so white text always reads well.
({Color top, Color bottom}) _heroGradient(Color accent) {
  final hsl = HSLColor.fromColor(accent);
  final top = hsl
      .withLightness(hsl.lightness.clamp(0.28, 0.48))
      .withSaturation(hsl.saturation.clamp(0.5, 1.0))
      .toColor();
  final bottom = hsl
      .withLightness((hsl.lightness * 0.3).clamp(0.04, 0.16))
      .withSaturation(hsl.saturation.clamp(0.55, 1.0))
      .toColor();
  return (top: top, bottom: bottom);
}

// =============================================================================
// Entry point
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
      value: SystemUiOverlayStyle.light, // always light on gradient hero
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
// _ReplayBody — main scrollable content
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
        // ── Apple-style gradient hero ────────────────────────────────────────
        SliverToBoxAdapter(
          child: _AppleHeroSection(
            replay: replay,
            topPad: topPad,
            onBack: onBack,
            availableYears: replay.availableYears,
            selectedYear: selectedYear,
            onYearSelected: onYearSelected,
          ),
        ),

        // ── Quick stats 2×2 grid ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: _QuickStatGrid(replay: replay),
          ).animate(delay: 100.ms).fadeIn(duration: 420.ms)
              .slideY(begin: 0.06, end: 0),
        ),

        // ── Genre breakdown ─────────────────────────────────────────────────
        if (replay.topGenres.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _AppleGenreCard(genres: replay.topGenres),
            ).animate(delay: 180.ms).fadeIn(duration: 420.ms),
          ),

        // ── Peak hour ───────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _PeakHourRow(
              peakHour: replay.peakHourIst,
              heatmap: replay.hourlyHeatmap,
            ),
          ).animate(delay: 240.ms).fadeIn(duration: 420.ms),
        ),

        // ── Month-by-month horizontal carousel ──────────────────────────────
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
                child: Text(
                  'MONTH BY MONTH',
                  style: tokens
                      .textStyle(11, FontWeight.w700, tokens.textMuted)
                      .copyWith(letterSpacing: 1.4),
                ),
              ),
              SizedBox(
                height: 114,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemCount: replay.monthlyCards.length,
                  itemBuilder: (ctx, i) {
                    final card = replay.monthlyCards[i];
                    return _MonthTile(
                      card: card,
                      accentColor: tokens.accent,
                      onTap: () =>
                          _openMonthDetail(ctx, card.year, card.month),
                    )
                        .animate(delay: (i * 40).clamp(0, 320).ms)
                        .fadeIn(duration: 300.ms)
                        .scale(
                          begin: const Offset(0.92, 0.92),
                          end: const Offset(1, 1),
                        );
                  },
                ),
              ),
            ],
          ).animate(delay: 300.ms).fadeIn(duration: 420.ms),
        ),

        // ── Top tracks list ─────────────────────────────────────────────────
        if (replay.topTracks.length > 1) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              label: 'TOP TRACKS',
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => _TrackRow(track: replay.topTracks[i], rank: i + 1)
                  .animate(delay: (i * 30).clamp(0, 250).ms)
                  .fadeIn(duration: 280.ms)
                  .slideX(begin: 0.03, end: 0),
              childCount: replay.topTracks.length,
            ),
          ),
        ],

        // ── Top artists list ────────────────────────────────────────────────
        if (replay.topArtists.length > 1) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              label: 'TOP ARTISTS',
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 8),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) =>
                  _ArtistRow(artist: replay.topArtists[i], rank: i + 1)
                      .animate(delay: (i * 30).clamp(0, 250).ms)
                      .fadeIn(duration: 280.ms)
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
}

// ---------------------------------------------------------------------------
// Apple-style gradient hero
// ---------------------------------------------------------------------------

class _AppleHeroSection extends StatelessWidget {
  final YearlyReplayResponse replay;
  final double topPad;
  final VoidCallback onBack;
  final List<int> availableYears;
  final int selectedYear;
  final ValueChanged<int> onYearSelected;

  const _AppleHeroSection({
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
    final grad = _heroGradient(tokens.accent);

    // Year watermark string — e.g. '25
    final yearStr = "'${selectedYear.toString().substring(
        selectedYear.toString().length - 2)}";

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [grad.top, grad.bottom],
        ),
      ),
      child: Stack(
        children: [
          // ── Giant year watermark ──────────────────────────────────────────
          Positioned(
            right: -16,
            top: topPad + 24,
            child: Text(
              yearStr,
              style: TextStyle(
                fontSize: 180,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.05),
                letterSpacing: -10,
                height: 1.0,
              ),
            ),
          ),

          // ── Main content column ──────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nav bar
              Padding(
                padding: EdgeInsets.fromLTRB(4, topPad + 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: onBack,
                    ),
                    const Spacer(),
                    Text(
                      'Replay',
                      style: tokens
                          .textStyle(17, FontWeight.w700, Colors.white)
                          .copyWith(letterSpacing: -0.3),
                    ),
                    const Spacer(),
                    if (availableYears.length > 1)
                      _YearPicker(
                        years: availableYears,
                        selected: selectedYear,
                        onChanged: onYearSelected,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '$selectedYear',
                          style: tokens.textStyle(
                            13,
                            FontWeight.w700,
                            Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Total Minutes label + giant animated number
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Minutes',
                      style: tokens.textStyle(
                        14,
                        FontWeight.w500,
                        Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TweenAnimationBuilder<int>(
                      tween: IntTween(
                        begin: 0,
                        end: replay.totalPlays > 0
                            ? replay.totalMinutes.round()
                            : 0,
                      ),
                      duration: const Duration(milliseconds: 1400),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, _) => Text(
                        _fmtComma(value),
                        style: tokens
                            .textStyle(64, FontWeight.w900, Colors.white)
                            .copyWith(
                              letterSpacing: -3.0,
                              height: 1.0,
                            ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.08, end: 0),

              // Thin divider
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Container(
                  height: 0.5,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
              ),

              // Top Song highlight
              if (replay.topTracks.isNotEmpty)
                _HeroHighlightRow(
                  icon: Icons.music_note_rounded,
                  label: 'Top Song',
                  title: replay.topTracks.first.title,
                  subtitle: replay.topTracks.first.artist,
                ).animate(delay: 250.ms).fadeIn(duration: 420.ms)
                    .slideX(begin: 0.06, end: 0),

              // Top Artist highlight
              if (replay.topArtists.isNotEmpty)
                _HeroHighlightRow(
                  icon: Icons.person_rounded,
                  label: 'Top Artist',
                  title: replay.topArtists.first.artist,
                  subtitle: '${replay.topArtists.first.uniqueSongs} songs',
                ).animate(delay: 350.ms).fadeIn(duration: 420.ms)
                    .slideX(begin: 0.06, end: 0),

              // Top Album highlight (from first track's album)
              if (replay.topTracks.isNotEmpty &&
                  replay.topTracks.first.album.isNotEmpty)
                _HeroHighlightRow(
                  icon: Icons.album_rounded,
                  label: 'Top Album',
                  title: replay.topTracks.first.album,
                  subtitle: replay.topTracks.first.artist,
                ).animate(delay: 450.ms).fadeIn(duration: 420.ms)
                    .slideX(begin: 0.06, end: 0),

              const SizedBox(height: 28),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero highlight row — compact item on the gradient
// ---------------------------------------------------------------------------

class _HeroHighlightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String title;
  final String subtitle;

  const _HeroHighlightRow({
    required this.icon,
    required this.label,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      child: Row(
        children: [
          // Icon container
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.85),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          // Text column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: tokens
                      .textStyle(
                        11,
                        FontWeight.w600,
                        Colors.white.withValues(alpha: 0.5),
                      )
                      .copyWith(letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens
                      .textStyle(15, FontWeight.w700, Colors.white)
                      .copyWith(letterSpacing: -0.2),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.textStyle(
                    12,
                    FontWeight.w400,
                    Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Year picker — translucent pill on the hero gradient
// ---------------------------------------------------------------------------

class _YearPicker extends StatelessWidget {
  final List<int> years;
  final int selected;
  final ValueChanged<int> onChanged;

  const _YearPicker({
    required this.years,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.7,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$selected',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more_rounded,
              size: 16,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  void _show(BuildContext ctx) {
    final tokens = ThemeTokens.of(ctx);
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: tokens.bgSurfaceOpaque,
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Year',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ...years.map(
              (y) => ListTile(
                title: Text(
                  '$y',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        y == selected ? FontWeight.w700 : FontWeight.w400,
                    color:
                        y == selected ? tokens.accent : tokens.textPrimary,
                  ),
                ),
                trailing: y == selected
                    ? Icon(Icons.check_rounded,
                        color: tokens.accent, size: 18)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  onChanged(y);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick stat grid — 2×2 with divider lines
// ---------------------------------------------------------------------------

class _QuickStatGrid extends StatelessWidget {
  final YearlyReplayResponse replay;
  const _QuickStatGrid({required this.replay});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final dividerColor = tokens.outline.withValues(alpha: 0.4);

    return Container(
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: tokens.outline.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: 'Total Plays',
                    value: _fmtComma(replay.totalPlays),
                  ),
                ),
                Container(width: 0.5, color: dividerColor),
                Expanded(
                  child: _StatCell(
                    label: 'Listening Days',
                    value: '${replay.listeningDays}',
                  ),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: dividerColor),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: 'Unique Songs',
                    value: _fmtComma(replay.uniqueSongs),
                  ),
                ),
                Container(width: 0.5, color: dividerColor),
                Expanded(
                  child: _StatCell(
                    label: 'Unique Artists',
                    value: '${replay.uniqueArtists}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;

  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tokens
                .textStyle(11, FontWeight.w500, tokens.textMuted)
                .copyWith(letterSpacing: 0.3),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: tokens
                .textStyle(24, FontWeight.w800, tokens.textPrimary)
                .copyWith(letterSpacing: -0.8),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Genre card — colour dots + rounded animated bars
// ---------------------------------------------------------------------------

class _AppleGenreCard extends StatelessWidget {
  final List<ReplayGenre> genres;
  const _AppleGenreCard({required this.genres});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final top = genres.take(5).toList();
    final maxPct = top.isEmpty ? 1.0 : top.first.pct;

    final barColors = [
      tokens.accent,
      tokens.accent.withValues(alpha: 0.78),
      tokens.accent.withValues(alpha: 0.58),
      tokens.accent.withValues(alpha: 0.40),
      tokens.accent.withValues(alpha: 0.25),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: tokens.outline.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR SOUND',
            style: tokens
                .textStyle(11, FontWeight.w700, tokens.textMuted)
                .copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 16),
          ...top.asMap().entries.map((e) {
            final i = e.key;
            final g = e.value;
            final fill =
                maxPct > 0 ? (g.pct / maxPct).clamp(0.0, 1.0) : 0.0;
            final color = barColors[i % barColors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Colour dot
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          g.genre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tokens.textStyle(
                            12,
                            FontWeight.w600,
                            tokens.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${g.pct.toStringAsFixed(0)}%',
                        style:
                            tokens.textStyle(11, FontWeight.w600, color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: fill),
                      duration: Duration(milliseconds: 550 + i * 80),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 8,
                        backgroundColor: tokens.bgElevated,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
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
// Peak hour — waveform bar chart
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
    final counts = List.generate(24, (h) => heatmap[h.toString()] ?? 0);
    final maxCount =
        counts.isEmpty ? 1 : counts.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.bgSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: tokens.outline.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Label + hour
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PEAK HOUR',
                style: tokens
                    .textStyle(11, FontWeight.w700, tokens.textMuted)
                    .copyWith(letterSpacing: 1.0),
              ),
              const SizedBox(height: 4),
              Text(
                _label(peakHour),
                style: tokens
                    .textStyle(24, FontWeight.w800, tokens.accent)
                    .copyWith(letterSpacing: -0.5),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Waveform bars
          Expanded(
            child: SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(24, (h) {
                  final frac =
                      maxCount > 0 ? counts[h] / maxCount : 0.0;
                  final isPeak = h == peakHour;
                  return Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 0.8),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: frac),
                        duration: Duration(milliseconds: 400 + h * 8),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, _) => Container(
                          height: math.max(3, 48 * v),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: isPeak
                                ? tokens.accent
                                : tokens.accent.withValues(
                                    alpha: 0.15 + 0.5 * v),
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
// Month tile — taller, gradient-tinted horizontal scroll tile
// ---------------------------------------------------------------------------

class _MonthTile extends StatelessWidget {
  final ReplayMonthlyCard card;
  final Color accentColor;
  final VoidCallback onTap;

  const _MonthTile({
    required this.card,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final hasActivity = card.totalPlays > 0;

    return CupertinoClickable(
      onTap: onTap,
      child: Container(
        width: 112,
        decoration: BoxDecoration(
          gradient: hasActivity
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accentColor.withValues(alpha: 0.14),
                    accentColor.withValues(alpha: 0.04),
                  ],
                )
              : null,
          color: hasActivity ? null : tokens.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasActivity
                ? accentColor.withValues(alpha: 0.22)
                : tokens.outline.withValues(alpha: 0.5),
            width: 0.7,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Month abbreviation
            Text(
              card.monthName.substring(0, 3).toUpperCase(),
              style: tokens
                  .textStyle(
                    11,
                    FontWeight.w800,
                    hasActivity ? tokens.accent : tokens.textMuted,
                  )
                  .copyWith(letterSpacing: 0.8),
            ),
            const SizedBox(height: 6),
            // Play count
            Text(
              '${card.totalPlays}',
              style: tokens
                  .textStyle(22, FontWeight.w800, tokens.textPrimary)
                  .copyWith(letterSpacing: -0.5),
            ),
            Text(
              'plays',
              style:
                  tokens.textStyle(10, FontWeight.w400, tokens.textMuted),
            ),
            const Spacer(),
            // Top track name
            if (card.topTrack != null)
              Text(
                card.topTrack!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tokens.textStyle(
                  10,
                  FontWeight.w600,
                  tokens.textSecondary,
                ),
              )
            else
              Text(
                '—',
                style:
                    tokens.textStyle(10, FontWeight.w400, tokens.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header with divider line
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
      child: Row(
        children: [
          Text(
            label,
            style: tokens
                .textStyle(11, FontWeight.w700, tokens.textMuted)
                .copyWith(letterSpacing: 1.4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 0.5,
              color: tokens.outline.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Track row — bold rank numbers, accent tint for top 3
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.outline.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: tokens
                  .textStyle(
                    isTop3 ? 22 : 14,
                    FontWeight.w900,
                    isTop3 ? tokens.accent : tokens.textMuted,
                  )
                  .copyWith(letterSpacing: -0.5),
            ),
          ),
          const SizedBox(width: 12),
          // Icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isTop3
                  ? tokens.accent.withValues(alpha: 0.1)
                  : tokens.bgElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 18,
              color: isTop3 ? tokens.accent : tokens.textMuted,
            ),
          ),
          const SizedBox(width: 12),
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
                    13,
                    FontWeight.w600,
                    tokens.textPrimary,
                  ),
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.textStyle(
                    11,
                    FontWeight.w400,
                    tokens.textMuted,
                  ),
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
                  12,
                  FontWeight.w600,
                  tokens.textSecondary,
                ),
              ),
              Text(
                _fmtMin(track.totalMinutes),
                style: tokens.textStyle(
                  10,
                  FontWeight.w400,
                  tokens.textMuted,
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
// Artist row — bold rank numbers, accent tint for top 3
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: tokens.outline.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: tokens
                  .textStyle(
                    isTop3 ? 22 : 14,
                    FontWeight.w900,
                    isTop3 ? tokens.accent : tokens.textMuted,
                  )
                  .copyWith(letterSpacing: -0.5),
            ),
          ),
          const SizedBox(width: 12),
          // Circle icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isTop3
                  ? tokens.accent.withValues(alpha: 0.1)
                  : tokens.bgElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              size: 20,
              color: isTop3 ? tokens.accent : tokens.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          // Artist name + details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.textStyle(
                    13,
                    FontWeight.w600,
                    tokens.textPrimary,
                  ),
                ),
                Text(
                  '${artist.uniqueSongs} songs · ${artist.playCount} plays',
                  style: tokens.textStyle(
                    11,
                    FontWeight.w400,
                    tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtMin(artist.totalMinutes),
            style: tokens.textStyle(
              12,
              FontWeight.w600,
              tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly detail bottom sheet
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
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Expanded(
              child: async.when(
                data: (data) => _MonthDetailContent(
                  data: data,
                  scrollController: sc,
                ),
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: tokens.accent,
                    strokeWidth: 2,
                  ),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          color: tokens.textMuted, size: 36),
                      const SizedBox(height: 12),
                      Text(
                        'Could not load month data',
                        style: TextStyle(color: tokens.textMuted),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => ref
                            .invalidate(navivibeMonthlyReplayProvider(key)),
                        child: Text(
                          'Retry',
                          style: TextStyle(color: tokens.accent),
                        ),
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

  const _MonthDetailContent({
    required this.data,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final dividerColor = tokens.outline.withValues(alpha: 0.4);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      children: [
        // Header
        Text(
          '${data.monthName} ${data.year}',
          style: tokens
              .textStyle(28, FontWeight.w900, tokens.textPrimary)
              .copyWith(letterSpacing: -1.0),
        ),
        const SizedBox(height: 16),

        // Quick stats — 2×2 grid
        Container(
          decoration: BoxDecoration(
            color: tokens.bgSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: tokens.outline.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCell(
                        label: 'Plays',
                        value: '${data.totalPlays}',
                      ),
                    ),
                    Container(width: 0.5, color: dividerColor),
                    Expanded(
                      child: _StatCell(
                        label: 'Time',
                        value: data.totalHoursLabel,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: dividerColor),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCell(
                        label: 'Songs',
                        value: '${data.uniqueSongs}',
                      ),
                    ),
                    Container(width: 0.5, color: dividerColor),
                    Expanded(
                      child: _StatCell(
                        label: 'Streak',
                        value: '${data.streakDays}d 🔥',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Daily mini chart
        if (data.dailyBreakdown.isNotEmpty) ...[
          _SheetSection('DAILY ACTIVITY'),
          const SizedBox(height: 8),
          _DailyMiniChart(days: data.dailyBreakdown),
          const SizedBox(height: 20),
        ],

        // Top tracks
        if (data.topTracks.isNotEmpty) ...[
          _SheetSection('TOP TRACKS'),
          const SizedBox(height: 6),
          ...data.topTracks.asMap().entries.map(
                (e) => _TrackRow(track: e.value, rank: e.key + 1)
                    .animate(delay: (e.key * 25).ms)
                    .fadeIn(duration: 220.ms),
              ),
          const SizedBox(height: 20),
        ],

        // Top artists
        if (data.topArtists.isNotEmpty) ...[
          _SheetSection('TOP ARTISTS'),
          const SizedBox(height: 6),
          ...data.topArtists.take(5).toList().asMap().entries.map(
                (e) => _ArtistRow(artist: e.value, rank: e.key + 1)
                    .animate(delay: (e.key * 25).ms)
                    .fadeIn(duration: 220.ms),
              ),
          const SizedBox(height: 20),
        ],

        // Recent plays
        if (data.recentPlays.isNotEmpty) ...[
          _SheetSection('RECENT PLAYS'),
          const SizedBox(height: 6),
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
              .textStyle(11, FontWeight.w700, tokens.textMuted)
              .copyWith(letterSpacing: 1.3),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 0.5,
            color: tokens.outline.withValues(alpha: 0.45),
          ),
        ),
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
    final show =
        days.length <= 31 ? days : days.sublist(days.length - 31);

    return SizedBox(
      height: 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: show.map((d) {
          final frac = maxPlays > 0 ? d.playCount / maxPlays : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: frac),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Container(
                  height: math.max(3, 48 * v),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: tokens.accent
                        .withValues(alpha: 0.25 + 0.75 * v),
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
            color: tokens.outline.withValues(alpha: 0.3),
            width: 0.4,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tokens.bgElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.music_note_rounded,
              size: 16,
              color: tokens.textMuted,
            ),
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
                    12,
                    FontWeight.w600,
                    tokens.textPrimary,
                  ),
                ),
                Text(
                  play.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.textStyle(
                    10,
                    FontWeight.w400,
                    tokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (timeStr.isNotEmpty)
                Text(
                  timeStr,
                  style: tokens.textStyle(
                    10,
                    FontWeight.w400,
                    tokens.textMuted,
                  ),
                ),
              const SizedBox(height: 3),
              SizedBox(
                width: 40,
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
                              ? tokens.accent
                                  .withValues(alpha: 0.55)
                              : tokens.textMuted
                                  .withValues(alpha: 0.35),
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
// Loading state — gradient hero skeleton
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  final double topPad;
  final VoidCallback onBack;
  const _LoadingBody({required this.topPad, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final grad = _heroGradient(tokens.accent);

    return Column(
      children: [
        // Gradient hero skeleton
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                grad.top.withValues(alpha: 0.7),
                grad.bottom.withValues(alpha: 0.7),
              ],
            ),
          ),
          padding: EdgeInsets.fromLTRB(4, topPad + 4, 12, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nav bar
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: onBack,
                  ),
                  const Spacer(),
                  Text(
                    'Replay',
                    style: tokens
                        .textStyle(17, FontWeight.w700, Colors.white)
                        .copyWith(letterSpacing: -0.3),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 32),
              // Total Minutes skeleton
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 58,
                      width: 200,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              // Divider skeleton
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 0.5,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              const SizedBox(height: 20),
              // Highlight row skeletons
              ...List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 10,
                            width: 60,
                            decoration: BoxDecoration(
                              color:
                                  Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 14,
                            width: 150,
                            decoration: BoxDecoration(
                              color:
                                  Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 10,
                            width: 90,
                            decoration: BoxDecoration(
                              color:
                                  Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Content skeleton
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // Stat grid skeleton
              Container(
                height: 130,
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              const SizedBox(height: 16),
              // Genre card skeleton
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  borderRadius: BorderRadius.circular(18),
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
// Error state — gradient header + centred message
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
    final grad = _heroGradient(tokens.accent);

    return Column(
      children: [
        // Gradient header bar
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                grad.top.withValues(alpha: 0.6),
                grad.bottom.withValues(alpha: 0.4),
              ],
            ),
          ),
          padding: EdgeInsets.fromLTRB(4, topPad + 4, 12, 20),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: onBack,
              ),
              const Spacer(),
              Text(
                'Replay',
                style: tokens
                    .textStyle(17, FontWeight.w700, Colors.white)
                    .copyWith(letterSpacing: -0.3),
              ),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
        ),
        const Spacer(),
        Icon(Icons.wifi_off_rounded, color: tokens.textMuted, size: 52),
        const SizedBox(height: 16),
        Text(
          'Could not load Replay',
          style: tokens.textStyle(
            18,
            FontWeight.w600,
            tokens.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            error.toString().contains('401')
                ? 'Authentication failed. Check your server credentials.'
                : 'Make sure your Navivibe server is reachable.',
            textAlign: TextAlign.center,
            style: tokens.textStyle(
              13,
              FontWeight.w400,
              tokens.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: tokens.accent,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
          onPressed: onRetry,
          child: Text(
            'Retry',
            style: tokens.textStyle(
              15,
              FontWeight.w700,
              Colors.white,
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }
}
