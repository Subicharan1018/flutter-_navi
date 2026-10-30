import 'package:flutter/widgets.dart';

import '../../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../../features/social/ui/jam/jam_tab.dart';
import '../../screens/home_screen.dart';
import '../../screens/library_screen.dart';
import '../../screens/search_screen.dart';
import '../../screens/stats/stats_screen.dart';
import '../art/navi_icons.dart';

/// The app's top-level destinations, in Apple Music's order (Search last).
/// Everything that switches tabs refers to these by name, never by position.
enum AppTab {
  home('Home', NaviGlyph.home),
  shuffle('Shuffle', NaviGlyph.aiShuffle),
  jam('Jam', NaviGlyph.jam),
  stats('Stats', NaviGlyph.dashboard),
  library('Library', NaviGlyph.library),
  search('Search', NaviGlyph.search);

  const AppTab(this.label, this.icon);
  final String label;

  /// Drawn filled when the tab is selected.
  final NaviGlyph icon;


  /// The one destination list every shell draws from: the phone tab bar and
  /// the TV rail show [mainTabs] (+ Search); the sidebar shows [browseTabs]
  /// above its Library section.
  static final List<AppTab> mainTabs = values.where((t) => t != search).toList();
  static const List<AppTab> browseTabs = [home, shuffle, jam, stats];

  Widget get screen => switch (this) {
        AppTab.home => const HomeScreen(),
        AppTab.shuffle => const AiShuffleScreen(),
        AppTab.jam => const JamTabScreen(),
        AppTab.stats => const StatsScreen(),
        AppTab.library => const LibraryScreen(),
        AppTab.search => const SearchScreen(),
      };
}
