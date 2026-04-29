import 'dart:ui';
import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/library_screen.dart';
import '../screens/favorites_screen.dart';
import '../core/theme.dart';
import 'mini_player.dart';

// =============================================================================
// AppScaffold
// Spotify-accurate bottom navigation + glassmorphism mini-player slot.
// =============================================================================

class AppScaffold extends StatefulWidget {
  const AppScaffold({super.key});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  int _currentIndex = 0;

  static const List<_NavItem> _items = [
    _NavItem(icon: Icons.home_outlined,   activeIcon: Icons.home_rounded,          label: 'Home'),
    _NavItem(icon: Icons.search_outlined, activeIcon: Icons.search_rounded,         label: 'Search'),
    _NavItem(icon: Icons.favorite_outline, activeIcon: Icons.favorite_rounded,      label: 'Favorites'),
    _NavItem(icon: Icons.library_music_outlined, activeIcon: Icons.library_music_rounded, label: 'Library'),
  ];

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    FavoritesScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.coreBackground,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Glassmorphism mini player ──────────────────────────────────────
          const MiniPlayer(),

          // ── Navigation bar ─────────────────────────────────────────────────
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: AppTheme.coreBackground.withOpacity(0.92),
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
                                            ? AppTheme.spotifyGreen
                                            : AppTheme.textMuted,
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
                                            ? AppTheme.spotifyGreen
                                            : AppTheme.textMuted,
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
          ),
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
