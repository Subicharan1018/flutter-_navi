import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/focus/navi_focus.dart';
import '../../../../core/motion.dart';
import '../../../../core/theme.dart';
import '../../data/fetch_models.dart';

/// What kind of result to look for: Songs, Albums, Artists, Playlists, Labels.
/// Set as plain words like a title row — the chosen one in white with a short
/// bar under it, the rest quiet — instead of a boxed segmented control, so the
/// kind reads as part of the search and not as a form widget. Scrolls sideways
/// when the screen is narrow; each word is a full-size target with a focus ring.
class FetchTypeTabs extends StatelessWidget {
  final FetchSearchType value;
  final ValueChanged<FetchSearchType> onChanged;
  const FetchTypeTabs({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final slide = context.motionFull ? Motion.fast : Duration.zero;
    return Semantics(
      container: true,
      label: 'Kind of result',
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          children: [
            for (final ty in FetchSearchType.values)
              Padding(
                padding: const EdgeInsets.only(right: Space.md),
                child: NaviFocusable(
                  radius: 8,
                  semanticLabel: ty.title,
                  onTap: () {
                    if (ty == value) return;
                    HapticFeedback.selectionClick();
                    onChanged(ty);
                  },
                  child: Semantics(
                    selected: ty == value,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: slide,
                          style: t.headline.copyWith(
                            color: ty == value ? t.textPrimary : t.textMuted,
                            fontWeight: ty == value ? FontWeight.w700 : FontWeight.w600,
                          ),
                          child: Text(ty.title),
                        ),
                        const SizedBox(height: 3),
                        // The bar grows out of the middle of the chosen word.
                        AnimatedScale(
                          duration: slide,
                          scale: ty == value ? 1 : 0,
                          child: Container(
                            height: 2,
                            width: 18,
                            decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(1)),
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
