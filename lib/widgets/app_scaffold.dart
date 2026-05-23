import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/home_screen.dart';
import '../screens/search_screen.dart';
import '../screens/library_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/dashboard_screen.dart';
import '../features/ai_shuffle/ui/ai_shuffle_screen.dart';
import '../services/replay_upload_service.dart';
import '../services/listening_log_service.dart';
import '../services/window_manager_service.dart';
import '../core/theme.dart';
import '../core/keyboard_shortcuts.dart';
import '../providers/settings_provider.dart';
import '../providers/library_provider.dart';
import '../fluid_background.dart';
import '../utils/platform_utils.dart';
import 'mini_player.dart';

// =============================================================================
// AppScaffold
//
// Adaptive layout:
//   Desktop (width ≥ 800px) → NavigationRail sidebar + content + mini player
//   Mobile / narrow           → Bottom navigation bar (original layout)
//
// The keyboard shortcuts widget wraps the entire scaffold so hotkeys work
// regardless of which screen is active.
// =============================================================================

class AppScaffold extends ConsumerStatefulWidget {
  const AppScaffold({super.key});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold>
    with WidgetsBindingObserver, WindowLifecycleMixin {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState(); // WindowLifecycleMixin.initState() attaches window listener
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(replayUploadServiceProvider).performUploadIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose(); // WindowLifecycleMixin.dispose() detaches listener
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
    _NavItem(icon: Icons.home_outlined,           activeIcon: Icons.home_rounded,               label: 'Home'),
    _NavItem(icon: Icons.search_outlined,         activeIcon: Icons.search_rounded,             label: 'Search'),
    _NavItem(icon: Icons.auto_awesome_outlined,   activeIcon: Icons.auto_awesome,               label: 'AI Shuffle'),
    _NavItem(icon: Icons.dashboard_outlined,      activeIcon: Icons.dashboard_rounded,          label: 'Dashboard'),
    _NavItem(icon: Icons.library_music_outlined,  activeIcon: Icons.library_music_rounded,      label: 'Library'),
  ];

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    AiShuffleScreen(),
    DashboardScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens      = ThemeTokens.of(context);
    final meshEnabled = ref.watch(settingsProvider).meshGradientEnabled;
    final isOffline   = ref.watch(isOfflineProvider);

    // Wrap everything in keyboard shortcuts — only active on desktop.
    return NaviKeyboardShortcuts(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useDesktopLayout = PlatformUtils.prefersSidebarNavigation &&
              constraints.maxWidth >= PlatformUtils.kDesktopBreakpoint;

          if (useDesktopLayout) {
            return _DesktopScaffold(
              currentIndex: _currentIndex,
              onNavTap: (i) => setState(() => _currentIndex = i),
              items: _items,
              screens: _screens,
              meshEnabled: meshEnabled,
              isOffline: isOffline,
              tokens: tokens,
            );
          }

          return _MobileScaffold(
            currentIndex: _currentIndex,
            onNavTap: (i) => setState(() => _currentIndex = i),
            items: _items,
            screens: _screens,
            meshEnabled: meshEnabled,
            isOffline: isOffline,
            tokens: tokens,
          );
        },
      ),
    );
  }
}

// =============================================================================
// Desktop layout — sidebar NavigationRail
// =============================================================================

class _DesktopScaffold extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavTap;
  final List<_NavItem> items;
  final List<Widget> screens;
  final bool meshEnabled;
  final bool isOffline;
  final AppThemeTokens tokens;

  const _DesktopScaffold({
    required this.currentIndex,
    required this.onNavTap,
    required this.items,
    required this.screens,
    required this.meshEnabled,
    required this.isOffline,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final sidebar = _DesktopSidebar(
      currentIndex: currentIndex,
      onTap: onNavTap,
      items: items,
      tokens: tokens,
      meshEnabled: meshEnabled,
    );

    final content = Column(
      children: [
        if (isOffline) _OfflineBanner(tokens: tokens),
        Expanded(
          child: IndexedStack(index: currentIndex, children: screens),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: tokens.outline.withValues(alpha: 0.25),
        ),
        const MiniPlayer(),
      ],
    );

    final body = Row(
      children: [
        sidebar,
        VerticalDivider(
          width: 1,
          color: tokens.outline.withValues(alpha: 0.4),
        ),
        Expanded(child: content),
      ],
    );

    if (meshEnabled) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: FluidBackground(
                colors: [
                  tokens.bgBase,
                  Color.lerp(tokens.bgBase, tokens.accent, 0.18)!,
                  Color.lerp(tokens.accent, tokens.bgBase, 0.55)!,
                  tokens.accent.withValues(alpha: 0.70),
                ],
              ),
            ),
            body,
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: tokens.bgBase,
      body: body,
    );
  }
}

// =============================================================================
// Desktop sidebar
// =============================================================================

class _DesktopSidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;
  final AppThemeTokens tokens;
  final bool meshEnabled;

  const _DesktopSidebar({
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.tokens,
    required this.meshEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 220,
          color: tokens.bgBase.withValues(alpha: meshEnabled ? 0.65 : 0.95),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App logo / name header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: tokens.accent, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      'NaviVibe',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: tokens.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Divider(color: tokens.outline.withValues(alpha: 0.3), height: 1),
              const SizedBox(height: 8),

              // Nav items
              ...List.generate(items.length, (i) {
                final item   = items[i];
                final active = currentIndex == i;
                return _SidebarNavItem(
                  item: item,
                  active: active,
                  tokens: tokens,
                  onTap: () => onTap(i),
                );
              }),

              const Spacer(),

              // Keyboard shortcut hint at the bottom (desktop UX)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text(
                  'Space: play/pause  ·  ←→: skip',
                  style: TextStyle(
                    fontSize: 10,
                    color: tokens.textMuted.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarNavItem extends StatefulWidget {
  final _NavItem item;
  final bool active;
  final AppThemeTokens tokens;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.item,
    required this.active,
    required this.tokens,
    required this.onTap,
  });

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final tokens = widget.tokens;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: active
                ? tokens.accent.withValues(alpha: 0.15)
                : _hovered
                    ? tokens.textPrimary.withValues(alpha: 0.06)
                    : Colors.transparent,
          ),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  active ? widget.item.activeIcon : widget.item.icon,
                  key: ValueKey(active),
                  color: active ? tokens.accent : tokens.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? tokens.accent : tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Mobile layout (unchanged from original)
// =============================================================================

class _MobileScaffold extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavTap;
  final List<_NavItem> items;
  final List<Widget> screens;
  final bool meshEnabled;
  final bool isOffline;
  final AppThemeTokens tokens;

  const _MobileScaffold({
    required this.currentIndex,
    required this.onNavTap,
    required this.items,
    required this.screens,
    required this.meshEnabled,
    required this.isOffline,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final navBar = ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: tokens.bgBase.withValues(alpha: meshEnabled ? 0.70 : 0.92),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(items.length, (i) {
                  final item   = items[i];
                  final active = currentIndex == i;
                  return Expanded(
                    child: Semantics(
                      selected: active,
                      label: item.label,
                      child: GestureDetector(
                        onTap: () => onNavTap(i),
                        behavior: HitTestBehavior.opaque,
                        child: SizedBox(
                          height: 56,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  active ? item.activeIcon : item.icon,
                                  key: ValueKey(active),
                                  color: active ? tokens.accent : tokens.textMuted,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                                  color: active ? tokens.accent : tokens.textMuted,
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
      return Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: FluidBackground(
                colors: [
                  tokens.bgBase,
                  Color.lerp(tokens.bgBase, tokens.accent, 0.18)!,
                  Color.lerp(tokens.accent, tokens.bgBase, 0.55)!,
                  tokens.accent.withValues(alpha: 0.70),
                ],
              ),
            ),
            IndexedStack(index: currentIndex, children: screens),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isOffline) _OfflineBanner(tokens: tokens),
            const MiniPlayer(),
            navBar,
          ],
        ),
      );
    }

    return Scaffold(
      extendBody: true,
      backgroundColor: tokens.bgBase,
      body: IndexedStack(index: currentIndex, children: screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOffline) _OfflineBanner(tokens: tokens),
          const MiniPlayer(),
          navBar,
        ],
      ),
    );
  }
}

// =============================================================================
// Shared helpers
// =============================================================================

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}

/// Non-dismissible offline banner using theme tokens.
class _OfflineBanner extends StatelessWidget {
  final AppThemeTokens tokens;
  const _OfflineBanner({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.gold.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: tokens.gold.withValues(alpha: 0.3), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 14, color: tokens.gold),
          const SizedBox(width: 6),
          Text(
            'Offline — showing downloaded songs only',
            style: tokens.textStyle(12, FontWeight.w500, tokens.gold),
          ),
        ],
      ),
    );
  }
}
