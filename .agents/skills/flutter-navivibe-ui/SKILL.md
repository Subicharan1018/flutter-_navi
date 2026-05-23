---
name: flutter-navivibe-ui
description: >
  Flutter UI skill for the NaviVibe music app. Use this skill whenever the user
  wants to build, refactor, or add UI screens, widgets, components, charts, or
  dashboard sections to the NaviVibe Flutter app. Triggers for: "build a dashboard",
  "add a stats screen", "make UI consistent", "add interactive charts", "contribution
  graph in Flutter", "listening stats UI", "radar chart Flutter", "line chart Flutter",
  "liquid glass button Flutter", "NaviVibe UI", "consistent design system", "add
  animations", "interactive widget Flutter". Always use this skill for any NaviVibe
  Flutter UI work — it encodes the design system, API contract, and component patterns.
---

# Flutter NaviVibe UI Skill

You are building UI for **NaviVibe** — a Flutter music player with an AI shuffle engine.
Before writing any code, read this skill fully. It defines the design system, the API,
and the component library you must follow for every screen and widget.

---

## 0. Quick Reference — What's Available

| Need | Read |
|---|---|
| Design tokens, theme, colors | Section 1 |
| Reusable widget patterns | Section 2 |
| Dashboard screen (full) | Section 3 |
| Charts (line, radar, heatmap, contribution) | Section 4 |
| Animated / interactive widgets | Section 5 |
| API integration (NaviVibe endpoints) | `references/api.md` |
| Full widget code templates | `references/widgets.md` |

---

## 1. Design System

### 1.1 AppThemeTokens — Always Use These

Never hardcode colors. Always reference `AppThemeTokens` or `ThemeTokens` from
`lib/core/theme.dart`. The god-node audit identified `../core/theme.dart` with 73 edges —
every widget must import it.

```dart
// ✅ CORRECT
Container(color: AppThemeTokens.surface)
Text('Hello', style: AppThemeTokens.labelMd)

// ❌ NEVER
Container(color: Color(0xFF1A1A2E))
Text('Hello', style: TextStyle(color: Colors.white))
```

### 1.2 Spacing & Radius Scale

```dart
// Spacing — use multiples of 4
const s4  = 4.0;
const s8  = 8.0;
const s12 = 12.0;
const s16 = 16.0;
const s20 = 20.0;
const s24 = 24.0;
const s32 = 32.0;

// Border radius
const radiusSm = BorderRadius.all(Radius.circular(8));
const radiusMd = BorderRadius.all(Radius.circular(12));
const radiusLg = BorderRadius.all(Radius.circular(16));
const radiusXl = BorderRadius.all(Radius.circular(24));
const radiusFull = BorderRadius.all(Radius.circular(999));
```

### 1.3 Typography Scale

```dart
// Always use AppThemeTokens text styles — never raw TextStyle
AppThemeTokens.displayLg   // 28px, w600 — screen titles
AppThemeTokens.displayMd   // 22px, w600 — section headers
AppThemeTokens.titleLg     // 18px, w500 — card titles
AppThemeTokens.titleMd     // 16px, w500 — item titles
AppThemeTokens.labelLg     // 14px, w500 — labels
AppThemeTokens.labelMd     // 13px, w400 — secondary labels
AppThemeTokens.labelSm     // 11px, w400 — captions, badges
AppThemeTokens.mono        // 13px, monospace — numbers, stats
```

### 1.4 Color Semantic Tokens

```dart
AppThemeTokens.primary        // Brand accent
AppThemeTokens.surface        // Card/container background
AppThemeTokens.surfaceVariant // Slightly elevated surface
AppThemeTokens.onSurface      // Primary text on surface
AppThemeTokens.onSurfaceMuted // Secondary/muted text
AppThemeTokens.success        // Green — high ratios, streaks
AppThemeTokens.warning        // Amber — medium ratios
AppThemeTokens.error          // Red — low ratios, skips
AppThemeTokens.info           // Blue — informational
```

### 1.5 Animation Defaults

```dart
// Standard durations — always use these
const kAnimFast   = Duration(milliseconds: 150);
const kAnimNormal = Duration(milliseconds: 250);
const kAnimSlow   = Duration(milliseconds: 400);

// Standard curves
const kCurveStandard = Curves.easeInOut;
const kCurveSpring   = Curves.elasticOut;
const kCurveDecel    = Curves.decelerate;
```

---

## 2. Core Widget Patterns

### 2.1 NaviCard — Base Card Component

All cards in NaviVibe use this pattern. Copy exactly.

```dart
class NaviCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? color;

  const NaviCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: kAnimNormal,
      decoration: BoxDecoration(
        color: color ?? AppThemeTokens.surface,
        borderRadius: radiusMd,
        border: Border.all(
          color: AppThemeTokens.onSurface.withOpacity(0.08),
          width: 0.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radiusMd,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(s16),
            child: child,
          ),
        ),
      ),
    );
  }
}
```

### 2.2 StatMetricTile — Number Summary Card

```dart
// Use for: total plays, total minutes, skip rate, streak days
NaviCard(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Total Plays', style: AppThemeTokens.labelMd.copyWith(
        color: AppThemeTokens.onSurfaceMuted,
      )),
      const SizedBox(height: s4),
      Text('$value', style: AppThemeTokens.displayMd.copyWith(
        color: AppThemeTokens.onSurface,
        fontFeatures: [FontFeature.tabularFigures()],
      )),
      if (subtitle != null) ...[
        const SizedBox(height: s4),
        Text(subtitle!, style: AppThemeTokens.labelSm.copyWith(
          color: AppThemeTokens.onSurfaceMuted,
        )),
      ],
    ],
  ),
)
```

### 2.3 ListenRatioBar — Progress Indicator

Maps `listen_ratio` (0.0–1.0) from API to color-coded bar.

```dart
class ListenRatioBar extends StatelessWidget {
  final double ratio; // 0.0 – 1.0
  final double height;

  const ListenRatioBar({super.key, required this.ratio, this.height = 4});

  Color get _color {
    if (ratio >= 0.8) return AppThemeTokens.success;
    if (ratio >= 0.5) return AppThemeTokens.warning;
    return AppThemeTokens.error;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radiusFull,
      child: LinearProgressIndicator(
        value: ratio,
        backgroundColor: AppThemeTokens.onSurface.withOpacity(0.08),
        valueColor: AlwaysStoppedAnimation(_color),
        minHeight: height,
      ),
    );
  }
}
```

### 2.4 LiquidGlassButton — Interactive CTA

Equivalent of the React `LiquidButton`. Use for primary actions (shuffle, play, rebuild).

```dart
class LiquidGlassButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool isLoading;

  const LiquidGlassButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.isLoading = false,
  });

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: kAnimFast);
    _scale = Tween(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: kCurveStandard),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { _ctrl.forward(); setState(() => _pressed = true); },
      onTapUp: (_)   { _ctrl.reverse(); setState(() => _pressed = false); widget.onTap?.call(); },
      onTapCancel: () { _ctrl.reverse(); setState(() => _pressed = false); },
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: s24),
          decoration: BoxDecoration(
            borderRadius: radiusFull,
            color: AppThemeTokens.primary.withOpacity(0.12),
            border: Border.all(color: AppThemeTokens.primary.withOpacity(0.4)),
            boxShadow: _pressed ? [] : [
              BoxShadow(
                color: AppThemeTokens.primary.withOpacity(0.2),
                blurRadius: 12, offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: AppThemeTokens.primary, size: 18),
                const SizedBox(width: s8),
              ],
              if (widget.isLoading)
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppThemeTokens.primary,
                  ),
                )
              else
                Text(widget.label, style: AppThemeTokens.labelLg.copyWith(
                  color: AppThemeTokens.primary, fontWeight: FontWeight.w600,
                )),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## 3. Dashboard Screen — Full Implementation

The dashboard maps to the NaviVibe API `/listening-log/stats` and `/model/status` endpoints.
Read `references/api.md` for full endpoint details before touching data layer.

### 3.1 Screen Structure

```
DashboardScreen
├── SliverAppBar (collapsible header with period selector)
├── SliverToBoxAdapter
│   ├── _MetricsGrid         (plays, minutes, skip rate, streak)
│   ├── _HourlyHeatmap       (hourly_heatmap from API)
│   ├── _GenreBreakdown      (radar chart — genre_breakdown)
│   ├── _ListeningTimeline   (line chart — daily plays over time)
│   ├── _ContributionGraph   (calendar grid — daily activity)
│   ├── _TopArtistsList      (top_artists)
│   ├── _TopTracksList       (top_tracks)
│   └── _ModelStatusCard     (model/status endpoint)
```

### 3.2 Period Selector (tab bar)

```dart
// Maps to API: period = daily | weekly | monthly | all
enum StatsPeriod { daily, weekly, monthly, all }

class _PeriodSelector extends StatelessWidget {
  final StatsPeriod selected;
  final ValueChanged<StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: StatsPeriod.values.map((p) {
          final isSelected = p == selected;
          return AnimatedContainer(
            duration: kAnimNormal,
            margin: const EdgeInsets.only(right: s8),
            child: ChoiceChip(
              label: Text(p.name.toUpperCase()),
              selected: isSelected,
              onSelected: (_) => onChanged(p),
              selectedColor: AppThemeTokens.primary.withOpacity(0.15),
              labelStyle: AppThemeTokens.labelMd.copyWith(
                color: isSelected
                  ? AppThemeTokens.primary
                  : AppThemeTokens.onSurfaceMuted,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
```

### 3.3 Metrics Grid

```dart
// Pulls from ListeningStatsResponse:
// total_plays, total_minutes, skip_rate, streak_days
Widget _buildMetricsGrid(ListeningStatsResponse stats) {
  return GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisSpacing: s12,
    mainAxisSpacing: s12,
    childAspectRatio: 1.6,
    children: [
      _MetricCard(label: 'Total Plays',   value: '${stats.totalPlays}',
                  icon: Icons.play_arrow_rounded, color: AppThemeTokens.primary),
      _MetricCard(label: 'Minutes',       value: '${stats.totalMinutes}',
                  icon: Icons.timer_outlined,     color: AppThemeTokens.info),
      _MetricCard(label: 'Skip Rate',     value: '${(stats.skipRate * 100).toStringAsFixed(0)}%',
                  icon: Icons.skip_next_rounded,  color: AppThemeTokens.warning),
      _MetricCard(label: 'Day Streak',    value: '${stats.streakDays}',
                  icon: Icons.local_fire_department_rounded, color: AppThemeTokens.success),
    ],
  );
}
```

---

## 4. Charts

Read `references/widgets.md` → Section A for full chart implementations.

### 4.1 Hourly Heatmap

Maps `hourly_heatmap: { "0": 0, "8": 12, "21": 42 }` from API.
Use `CustomPaint` — do NOT use a third-party chart library for this.

- 24 columns (hours), rows = days of week (if weekly) or single row (if daily)
- Cell color: `AppThemeTokens.primary.withOpacity(intensity)` where intensity = count / maxCount
- Show hour labels 0, 6, 12, 18, 23 only

### 4.2 Genre Radar Chart

Maps `genre_breakdown: [{ genre, play_count, pct }]`.
Use `fl_chart` RadarChart. Read `references/widgets.md` → Section B.

```dart
// Required package — already in pubspec if fl_chart is present
RadarChart(
  RadarChartData(
    radarShape: RadarShape.polygon,
    radarBackgroundColor: Colors.transparent,
    borderData: FlBorderData(show: false),
    gridBorderData: BorderSide(color: AppThemeTokens.onSurface.withOpacity(0.1)),
    tickBorderData: BorderSide(color: Colors.transparent),
    titleTextStyle: AppThemeTokens.labelSm.copyWith(
      color: AppThemeTokens.onSurfaceMuted,
    ),
    dataSets: [ /* map genre_breakdown */ ],
  ),
)
```

### 4.3 Listening Timeline (Line Chart)

Use `fl_chart` LineChart. Maps daily play counts.
- X axis: dates, show every 3rd label
- Y axis: play count
- Line: `AppThemeTokens.primary`, strokeWidth 2.5
- Dotted line style for current incomplete period
- Animated `LineChartBarData` with `isCurved: true`

### 4.4 Contribution Graph (Calendar Heatmap)

Equivalent of the React `ContributionGraph` component.
Full implementation in `references/widgets.md` → Section C.

- 53 columns × 7 rows grid
- Each cell: 10×10 rounded square
- Color: `AppThemeTokens.primary.withOpacity(level * 0.25)`
- Tooltip on long press: show date + play count
- Month labels above columns
- Day labels (Sun/Mon..) on left

---

## 5. Interactive & Animated Widgets

### 5.1 Rules for All Animations

```dart
// ✅ ALWAYS: dispose AnimationControllers
@override
void dispose() {
  _controller.dispose();
  super.dispose();
}

// ✅ ALWAYS: check mounted before setState after async
if (!mounted) return;
setState(() { ... });

// ✅ ALWAYS: use SingleTickerProviderStateMixin for one controller
// ✅ ALWAYS: use TickerProviderStateMixin for multiple controllers

// ❌ NEVER: animate inside build() directly
// ❌ NEVER: use Future.delayed for animation without cancellation
```

### 5.2 Shimmer Loading Skeleton

Use for all loading states — never show blank screen or spinner alone.

```dart
class NaviSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const NaviSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius,
  });

  @override
  State<NaviSkeleton> createState() => _NaviSkeletonState();
}

class _NaviSkeletonState extends State<NaviSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppThemeTokens.onSurface.withOpacity(_anim.value * 0.1),
          borderRadius: widget.borderRadius ?? radiusSm,
        ),
      ),
    );
  }
}
```

### 5.3 Animated Number Counter

Use when updating stat values between periods.

```dart
class AnimatedCounter extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = kAnimSlow,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      builder: (_, v, __) => Text(
        v.toString(),
        style: style ?? AppThemeTokens.displayMd,
      ),
    );
  }
}
```

### 5.4 Swipeable Song Tile

For top_tracks list — swipe right to favorite, swipe left to skip.

```dart
// Wrap each song tile in Dismissible
Dismissible(
  key: ValueKey(track.title),
  direction: DismissDirection.horizontal,
  background: _swipeBg(Icons.favorite, AppThemeTokens.success, Alignment.centerLeft),
  secondaryBackground: _swipeBg(Icons.skip_next, AppThemeTokens.error, Alignment.centerRight),
  confirmDismiss: (dir) async {
    if (dir == DismissDirection.startToEnd) { onFavorite(track); }
    else { onSkip(track); }
    return false; // don't actually dismiss, just trigger action
  },
  child: _SongTile(track: track),
)
```

---

## 6. State Management Rules

Always use Riverpod (it's your existing setup — `flutter_riverpod` is god node #1).

```dart
// Dashboard stats provider
final statsProvider = FutureProvider.family<ListeningStatsResponse, StatsPeriod>(
  (ref, period) async {
    final service = ref.watch(subsonicServiceProvider);
    return service.getListeningStats(period: period.name);
  },
);

// Model status provider
final modelStatusProvider = FutureProvider<ModelStatusResponse>(
  (ref) async {
    final service = ref.watch(subsonicServiceProvider);
    return service.getModelStatus();
  },
);

// Always handle all 3 states
ref.watch(statsProvider(period)).when(
  data: (stats) => _buildContent(stats),
  loading: () => _buildSkeleton(),
  error: (e, _) => _buildError(e),
);
```

---

## 7. Error & Empty States

Every list and chart MUST have an error state and empty state.

```dart
// Error state
NaviCard(
  child: Column(
    children: [
      Icon(Icons.wifi_off_rounded, color: AppThemeTokens.error, size: 32),
      const SizedBox(height: s12),
      Text('Could not load stats', style: AppThemeTokens.titleMd),
      const SizedBox(height: s8),
      Text(error.toString(), style: AppThemeTokens.labelMd.copyWith(
        color: AppThemeTokens.onSurfaceMuted,
      )),
      const SizedBox(height: s16),
      LiquidGlassButton(label: 'Retry', onTap: () => ref.invalidate(statsProvider)),
    ],
  ),
)

// Empty state
NaviCard(
  child: Column(
    children: [
      Icon(Icons.music_off_rounded, color: AppThemeTokens.onSurfaceMuted, size: 32),
      const SizedBox(height: s12),
      Text('No data yet', style: AppThemeTokens.titleMd),
      Text('Start listening to see your stats', style: AppThemeTokens.labelMd.copyWith(
        color: AppThemeTokens.onSurfaceMuted,
      )),
    ],
  ),
)
```

---

## 8. Code Quality Checklist (run before every PR)

- [ ] No hardcoded colors — all via `AppThemeTokens`
- [ ] All `AnimationController`s disposed in `dispose()`
- [ ] All `mounted` checks after every `await`
- [ ] All `StreamSubscription`s cancelled in `dispose()`
- [ ] Every list has loading + empty + error state
- [ ] No `setState` inside `build()`
- [ ] No `context` captured across async gaps (use `ref` instead)
- [ ] All models are immutable with `copyWith`
- [ ] `NaviCard` used for all card containers
- [ ] `NaviSkeleton` used for all loading states

---

## 9. Reference Files

- `references/api.md` — Full NaviVibe API contract (endpoints, params, response shapes)
- `references/widgets.md` — Full widget code: HourlyHeatmap, ContributionGraph, RadarChart, LineChart, ModelStatusCard
