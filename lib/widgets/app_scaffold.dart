import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/library_screen.dart';
import '../screens/favorites_screen.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../services/replay_upload_service.dart';
import '../services/listening_log_service.dart';
import '../core/theme.dart';
import '../providers/settings_provider.dart';
import '../fluid_background.dart';
import 'mini_player.dart';

// =============================================================================
// AppScaffold
// Spotify-accurate bottom navigation + glassmorphism mini-player slot.
// When meshGradientEnabled, a live FluidBackground shader renders behind all
// content — the IndexedStack sits in front on a transparent Scaffold.
// =============================================================================

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Schedule background analytics upload on startup if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(replayUploadServiceProvider).performUploadIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Flush the listening-log retry queue whenever the app comes back to the
  /// foreground. This is the single flush point — no background polling needed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(listeningLogServiceProvider).flushQueue();
    }
  }

  static const List<_NavItem> _items = [
    _NavItem(icon: Icons.home_outlined,   activeIcon: Icons.home_rounded,          label: 'Home'),
    _NavItem(icon: Icons.search_outlined, activeIcon: Icons.search_rounded,         label: 'Search'),
    _NavItem(icon: Icons.auto_awesome_outlined, activeIcon: Icons.auto_awesome,     label: 'AI Shuffle'),
    _NavItem(icon: Icons.favorite_outline, activeIcon: Icons.favorite_rounded,      label: 'Favorites'),
    _NavItem(icon: Icons.library_music_outlined, activeIcon: Icons.library_music_rounded, label: 'Library'),
  ];

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    AiShuffleScreen(),
    FavoritesScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad        = MediaQuery.of(context).padding.bottom;
    final tokens           = ThemeTokens.of(context);
    final meshEnabled      = ref.watch(settingsProvider).meshGradientEnabled;

    final navBar = ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: tokens.bgBase.withOpacity(meshEnabled ? 0.70 : 0.92),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_items.length, (i) {
                  final item    = _items[i];
                  final active  = _currentIndex == i;
                  return Expanded(
                    child: Semantics(
                      selected: active,
                      label: item.label,
                      child: GestureDetector(
                        onTap: () => setState(() => _currentIndex = i),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          height: 56, // ≥ 48dp touch target
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  active ? item.activeIcon : item.icon,
                                  key: ValueKey(active),
                                  color: active
                                      ? tokens.accent
                                      : tokens.textMuted,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: active
                                      ? tokens.accent
                                      : tokens.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );

    if (meshEnabled) {
      // ── Mesh-gradient mode: FluidBackground fills the screen, content
      // stacks on top with a transparent Scaffold background.
      return Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Layer 0: animated mesh gradient shader
            Positioned.fill(
              child: FluidBackground(
                colors: [
                  tokens.bgBase,
                  Color.lerp(tokens.bgBase, tokens.accent, 0.18)!,
                  Color.lerp(tokens.accent, tokens.bgBase, 0.55)!,
                  tokens.accent.withOpacity(0.70),
                ],
              ),
            ),
            // Layer 1: actual screen content
            IndexedStack(index: _currentIndex, children: _screens),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            navBar,
          ],
        ),
      );
    }

    // ── Standard mode: opaque scaffold background.
    return Scaffold(
      extendBody: true,
      backgroundColor: tokens.bgBase,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          navBar,
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
