# Upgrade NaviVibe UI & Smart Shuffle

This plan covers introducing the new Dashboard screen (replacing Favorites in the bottom navigation bar) and adjusting the Smart Shuffle engine to pull 16 songs at a time instead of 15.

## User Review Required

> [!IMPORTANT]
> The `DashboardScreen` relies heavily on custom charts (Heatmap, Radar, Line, Contribution) and the `flutter-navivibe-ui` design system. I will implement these according to the skill references. Please let me know if you want to prioritize specific metrics or adjust the layout order before I begin.

## Open Questions

> [!WARNING]
> Since we are removing Favorites from the bottom bar, I will leave `lib/screens/favorites_screen.dart` untouched so it can still be accessed from the Home screen as you mentioned. Is that correct?

## Proposed Changes

### Dashboard & Navigation Layer

#### [NEW] [dashboard_screen.dart](file:///home/subi/Documents/flutter-_navi/lib/screens/dashboard_screen.dart)
Create the new Dashboard screen using the UI skill patterns:
- Implement `DashboardScreen` with a `SliverAppBar` and `_PeriodSelector`.
- Build the `_MetricsGrid` (Plays, Minutes, Skip Rate, Streak).
- Implement `_HourlyHeatmap` and `_GenreBreakdown` (using `fl_chart`).
- Implement `_ListeningTimeline` and `_ContributionGraph`.

#### [MODIFY] [app_scaffold.dart](file:///home/subi/Documents/flutter-_navi/lib/widgets/app_scaffold.dart)
Replace the Favorites navigation tab with Dashboard:
- Update `_items` to replace `Favorites` with `Dashboard` using `Icons.dashboard_outlined` and `Icons.dashboard_rounded`.
- Update `_screens` array to replace `FavoritesScreen()` with `DashboardScreen()`.

---

### Smart Shuffle Constants Layer

#### [MODIFY] [player_provider.dart](file:///home/subi/Documents/flutter-_navi/lib/providers/player_provider.dart)
- Update `_smartLocalBatchSize` from `15` to `16`.
- Update corresponding comments documenting the batch size.

#### [MODIFY] [shuffle_providers.dart](file:///home/subi/Documents/flutter-_navi/lib/features/ai_shuffle/logic/shuffle_providers.dart)
- Update default parameter `count = 15` to `count = 16` in `ShuffleQueueNotifier.fetchNext`.

#### [MODIFY] [shuffle_repository.dart](file:///home/subi/Documents/flutter-_navi/lib/features/ai_shuffle/data/repositories/shuffle_repository.dart)
- Update default parameter `count = 15` to `count = 16` in `ShuffleRepository.getNext`.

#### [MODIFY] [shuffle_api_service.dart](file:///home/subi/Documents/flutter-_navi/lib/features/ai_shuffle/data/services/shuffle_api_service.dart)
- Update default parameter `count = 15` to `count = 16` in `ShuffleApiService.getNext`.

## Verification Plan

### Automated Tests
- N/A (UI and logic constant tweaks, but will ensure app compiles cleanly).

### Manual Verification
- Launch the app and verify the bottom navigation bar has "Dashboard" instead of "Favorites".
- Tap "Dashboard" and ensure it loads the stats components without crashing.
- Trigger Smart Shuffle and verify the queue length reflects the 16 song increment.
