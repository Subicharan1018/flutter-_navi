// =============================================================================
// RecommendationCard — Smart Shuffle recommendation, NaviVibe design system.
// =============================================================================

import 'package:flutter/material.dart';
import '../../../../core/theme.dart';
import '../../../../widgets/navi_ui.dart';
import '../../data/models/recommended_song.dart';

class RecommendationCard extends StatefulWidget {
  final RecommendedSong song;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const RecommendationCard({
    super.key,
    required this.song,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<RecommendationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(vsync: this, duration: kAnimFast);
    _scale = Tween(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _pressCtrl, curve: kCurveStandard));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    final score = widget.song.scores.finalScore.clamp(0.0, 1.0);

    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: s8, vertical: s4),
          decoration: BoxDecoration(
            color: tokens.bgSurface,
            borderRadius: radiusMd,
            border: Border.all(
              color: tokens.textPrimary.withValues(alpha: 0.07),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row ──────────────────────────────────────────────────
                Row(
                  children: [
                    // Rank bubble
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: tokens.accent.withValues(alpha: 0.12),
                        borderRadius: radiusSm,
                        border: Border.all(
                          color: tokens.accent.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${widget.song.rank}',
                        style: tokens.textStyle(
                          12,
                          FontWeight.w700,
                          tokens.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: s12),
                    // Title + composer
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.song.title,
                            style: tokens.textStyle(
                              14,
                              FontWeight.w600,
                              tokens.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.song.composer.isNotEmpty
                                ? widget.song.composer
                                : 'Unknown Composer',
                            style: tokens.textStyle(
                              12,
                              FontWeight.w400,
                              tokens.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: s8),
                    // Starter badge — habitual session opener (v3.1)
                    if (widget.song.isStarter) ...[
                      _BadgeChip(
                        label: '▶ STARTER',
                        color: const Color(0xFF4ADE80),
                      ),
                      const SizedBox(width: s4),
                    ],
                    // Genre chip
                    if (widget.song.genreBucket.isNotEmpty)
                      _GenreChip(
                        bucket: widget.song.genreBucket,
                        tokens: tokens,
                      ),
                    if (widget.song.isExplore) ...[
                      const SizedBox(width: s4),
                      _BadgeChip(label: 'EXPLORE', color: const Color(0xFF64D2FF)),
                    ] else if (widget.song.isColdStart) ...[
                      const SizedBox(width: s4),
                      _BadgeChip(label: 'NEW', color: tokens.accent),
                    ],
                    const SizedBox(width: s8),
                    // Add-to-queue
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: 0.1),
                          borderRadius: radiusSm,
                          border: Border.all(
                            color: tokens.accent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(
                          Icons.playlist_add_rounded,
                          color: tokens.accent,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: s12),

                // ── Score bar ─────────────────────────────────────────────────
                Row(
                  children: [
                    Text(
                      'MATCH',
                      style: tokens
                          .textStyle(9, FontWeight.w600, tokens.textMuted)
                          .copyWith(letterSpacing: 0.8),
                    ),
                    const SizedBox(width: s8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: radiusFull,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: score),
                          duration: kAnimSlow,
                          builder: (_, v, _) => LinearProgressIndicator(
                            value: v,
                            backgroundColor: tokens.textPrimary.withValues(
                              alpha: 0.07,
                            ),
                            valueColor: AlwaysStoppedAnimation(
                              _scoreColor(score, tokens),
                            ),
                            minHeight: 5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: s8),
                    Text(
                      '${(score * 100).toStringAsFixed(0)}%',
                      style: tokens.textStyle(
                        11,
                        FontWeight.w700,
                        _scoreColor(score, tokens),
                      ),
                    ),
                  ],
                ),

                // ── Pairing indicator (v3.1) ──────────────────────────────────
                if (widget.song.pairing != null) ...[
                  const SizedBox(height: s8),
                  Row(
                    children: [
                      Icon(
                        Icons.link_rounded,
                        size: 13,
                        color: tokens.accent.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: s4),
                      Expanded(
                        child: Text(
                          widget.song.pairing!.isSecondOrder
                              ? 'Pairs after "${widget.song.pairing!.follows}" '
                                    '(2-song combo) · ${widget.song.pairing!.timesFollowed}× in your sessions'
                              : 'Pairs after "${widget.song.pairing!.follows}" '
                                    '· ${widget.song.pairing!.timesFollowed}× in your sessions',
                          style: tokens.textStyle(
                            10,
                            FontWeight.w500,
                            tokens.accent.withValues(alpha: 0.9),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                // ── Why caption ───────────────────────────────────────────────
                if (widget.song.why.isNotEmpty) ...[
                  const SizedBox(height: s8),
                  Text(
                    widget.song.why,
                    style: tokens
                        .textStyle(11, FontWeight.w400, tokens.textSecondary)
                        .copyWith(fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _scoreColor(double score, AppThemeTokens tokens) {
    if (score >= 0.7) return tokens.accent;
    if (score >= 0.4) return const Color(0xFFFFD700);
    return const Color(0xFFFF6B6B);
  }
}

// ── Genre chip ─────────────────────────────────────────────────────────────────

class _GenreChip extends StatelessWidget {
  final String bucket;
  final AppThemeTokens tokens;

  const _GenreChip({required this.bucket, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _genreStyle(bucket);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: radiusFull,
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  (String, Color) _genreStyle(String bucket) {
    switch (bucket) {
      case 'melody':
        return ('♪ MELODY', const Color(0xFF64D2FF));
      case 'kuthu':
        return ('🥁 KUTHU', const Color(0xFFFF6B6B));
      case 'devotional':
        return ('🙏 DEVOTIONAL', const Color(0xFFFFD700));
      case 'rock':
        return ('🎸 ROCK', const Color(0xFFFF8C42));
      default:
        return (bucket.toUpperCase(), const Color(0xFFBB86FC));
    }
  }
}

// ── Badge chip ─────────────────────────────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  final String label;
  final Color color;

  const _BadgeChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: radiusFull,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
