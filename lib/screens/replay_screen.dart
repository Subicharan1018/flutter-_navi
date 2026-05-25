import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/replay_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';
import '../widgets/mini_player.dart';
import 'replay/widgets/replay_widgets.dart';

// =============================================================================
// Replay Screen — Apple Music-style listening analytics
// Two tabs: Monthly Replay | This Week
// Data sourced from the Drift database (real SQLite listening events)
// =============================================================================

class ReplayScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const ReplayScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends ConsumerState<ReplayScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _monthLabel() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.year}';
  }

  String _weekLabel() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${monthNames[monday.month - 1]} ${monday.day} – ${sunday.day}';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ThemeTokens.of(context).isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: ThemeTokens.of(context).bgBase,
        body: Stack(
          children: [
            Column(
              children: [
                // ── Header ────────────────────────────────────────────────
                ReplayHeader(
                  topPad: topPad,
                  tabController: _tabController,
                  monthLabel: _monthLabel(),
                  weekLabel: _weekLabel(),
                  onBack: () => Navigator.pop(context),
                ),

                // ── Tab views ─────────────────────────────────────────────
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      ReplayTabContent(
                        provider: monthlyReplayProvider,
                        periodLabel: _monthLabel(),
                        emptyLabel:
                            'Listen more this month to\nbuild your Monthly Replay',
                        showDailyChart: false,
                      ),
                      ReplayTabContent(
                        provider: weeklyReplayProvider,
                        periodLabel: _weekLabel(),
                        emptyLabel:
                            'Listen more this week to\nbuild your Weekly Replay',
                        showDailyChart: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── Mini player overlay ─────────────────────────────────────
            const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayer()),
          ],
        ),
      ),
    );
  }
}
