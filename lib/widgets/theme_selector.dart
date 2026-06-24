import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../providers/settings_provider.dart';

class ThemeSelector extends ConsumerWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    final tokens = ThemeVariants.of(current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('THEME', style: tokens.labelMd),
        ),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemCount: AppThemeMode.values.length,
            itemBuilder: (context, i) {
              final mode = AppThemeMode.values[i];
              return _ThemeCard(
                mode: mode,
                isSelected: mode == current,
                onTap: () =>
                    ref.read(settingsProvider.notifier).setThemeMode(mode),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final AppThemeMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeVariants.of(mode);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 110,
        decoration: BoxDecoration(
          color: t.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? t.accent : t.outline,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ThemePreviewPill(t: t),
            const SizedBox(height: 10),
            Text(
              mode.label,
              style: t.textStyle(13, FontWeight.w600, t.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: t.accent, size: 16)
            else
              SizedBox(
                height: 16,
                child: Text(
                  _shortDesc(mode),
                  style: t.textStyle(9, FontWeight.w400, t.textMuted),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _shortDesc(AppThemeMode m) {
    switch (m) {
      case AppThemeMode.spotify:
        return 'Classic dark';
      case AppThemeMode.aura:
        return 'Gradient mesh';
      case AppThemeMode.frost:
        return 'Glassmorphism';
      case AppThemeMode.neumorphic:
        return 'Soft UI';
      case AppThemeMode.analog:
        return 'Retro vinyl';
      case AppThemeMode.zen:
        return 'Minimalist';
    }
  }
}

class _ThemePreviewPill extends StatelessWidget {
  final AppThemeTokens t;
  const _ThemePreviewPill({required this.t});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 40,
      decoration: BoxDecoration(
        color: t.bgBase,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.outline, width: 1),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: t.bgOverlay,
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.55,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: t.accent,
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle, color: t.accent),
            child: Icon(
              Icons.play_arrow_rounded,
              size: 14,
              color: t.isLight ? Colors.white : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
