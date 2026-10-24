import 'package:flutter/widgets.dart';

import '../../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../../screens/home_screen.dart';
import '../../screens/library_screen.dart';
import '../../screens/search_screen.dart';
import '../../screens/stats/stats_screen.dart';
import '../art/navi_icons.dart';

/// The app's top-level destinations, in Apple Music's order (Search last).
/// Everything that switches tabs refers to these by name, never by position.
enum AppTab {
  home('Home', NaviGlyph.home, 'tab_home', Duration(milliseconds: 1980)),
  shuffle('Shuffle', NaviGlyph.aiShuffle, 'tab_shuffle', Duration(milliseconds: 2970)),
  stats('Stats', NaviGlyph.dashboard, 'tab_stats', Duration(milliseconds: 1980)),
  library('Library', NaviGlyph.library, 'tab_library', Duration(milliseconds: 1980)),
  search('Search', NaviGlyph.search, null, Duration.zero);

  const AppTab(this.label, this.icon, this.illustration, this.illustrationDuration);
  final String label;

  /// Drawn filled when the tab is selected.
  final NaviGlyph icon;

  /// Animated illustration for the phone tab bar (see `OneShotIcon`); null
  /// keeps the glyph. The sidebar and TV rail keep the glyphs.
  final String? illustration;
  final Duration illustrationDuration;

  Widget get screen => switch (this) {
        AppTab.home => const HomeScreen(),
        AppTab.shuffle => const AiShuffleScreen(),
        AppTab.stats => const StatsScreen(),
        AppTab.library => const LibraryScreen(),
        AppTab.search => const SearchScreen(),
      };
}
