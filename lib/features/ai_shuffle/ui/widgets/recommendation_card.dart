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
          ),
          child: Padding(
            padding: const EdgeInsets.all(s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Top row ──────────────────────────────────────────────────
                Row(
                  children: [
                    // Rank text (muted, regular weight)
                    Container(
                      width: 24,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${widget.song.rank}',
                        style: tokens.textStyle(
                          13,
                          FontWeight.w500,
                          tokens.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: s8),
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
                        tokens: tokens,
                      ),
                      const SizedBox(width: s4),
                    ],
                    // Genre chip (neutral pill)
                    if (widget.song.genreBucket.isNotEmpty)
                      _GenreChip(
                        bucket: widget.song.genreBucket,
                        tokens: tokens,
                      ),
                    if (widget.song.isExplore) ...[
                      const SizedBox(width: s4),
                      _BadgeChip(label: 'EXPLORE', tokens: tokens),
                    ] else if (widget.song.isColdStart) ...[
                      const SizedBox(width: s4),
                      _BadgeChip(label: 'NEW', tokens: tokens),
                    ],
                    const SizedBox(width: s8),
                    // Add-to-queue
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: tokens.bgElevated,
                          borderRadius: radiusSm,
                        ),
                        child: Icon(
                          Icons.playlist_add_rounded,
                          color: tokens.textSecondary,
                          size: 18,
                        ),
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
                    _cleanWhy(widget.song.why),
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

  String _cleanWhy(String why) {
    final idx = why.indexOf('—');
    if (idx != -1) return why.substring(0, idx).trim();
    return why;
  }
}

// ── Genre chip (neutral pill style) ───────────────────────────────────────────

class _GenreChip extends StatelessWidget {
  final String bucket;
  final AppThemeTokens tokens;

  const _GenreChip({required this.bucket, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        borderRadius: radiusFull,
      ),
      child: Text(
        bucket.toUpperCase(),
        style: tokens.textStyle(
          9,
          FontWeight.w600,
          tokens.textSecondary,
        ),
      ),
    );
  }
}

// ── Badge chip (neutral pill style) ───────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  final String label;
  final AppThemeTokens tokens;

  const _BadgeChip({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        borderRadius: radiusFull,
      ),
      child: Text(
        label,
        style: tokens.textStyle(
          9,
          FontWeight.w600,
          tokens.textSecondary,
        ),
      ),
    );
  }
}
