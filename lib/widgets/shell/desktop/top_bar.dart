import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/focus/navi_focus.dart';
import '../../../core/theme.dart';
import '../../../features/online_fetch/logic/online_fetch_providers.dart';
import '../../../features/online_fetch/ui/fetch_activity.dart' show showFetchDownloads;
import '../../../features/pairing/ui/sign_in_another_device_screen.dart';
import '../../../features/social/logic/social_providers.dart' show invitationCountProvider;
import '../../../features/updates/logic/update_providers.dart';
import '../../../features/updates/ui/updates_screen.dart';
import '../../../providers/search_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../screens/settings_screen.dart';
import '../../../utils/platform_utils.dart';
import '../../art/navi_icons.dart';
import '../../desktop_dialogs.dart';
import '../../ui/action_sheet.dart';
import '../app_tab.dart';
import '../nav_stack.dart';

// =============================================================================
// top_bar.dart — the one bar along the top of the desktop window.
//
// Back and forward, a search field in the middle (Ctrl+K; results show as the
// Search page), notifications and the profile on the right. On Windows the
// window's own buttons follow, and every empty part of the bar drags the
// window; on Linux the system draws the title bar and this sits under it.
// =============================================================================

/// The field in the top bar; Ctrl+K and "/" focus it.
final FocusNode desktopSearchFocus = FocusNode(debugLabel: 'top-search');

/// True while the desktop shell is on screen, so the Windows title bar becomes
/// the full top bar (and a plain title on the sign-in screen).
final ValueNotifier<bool> desktopShellActive = ValueNotifier(false);

class DesktopTopBar extends ConsumerWidget {
  /// Windows: the bar moves the window when dragged, and [trailing] holds the
  /// window buttons.
  final bool dragsWindow;
  final Widget? trailing;
  const DesktopTopBar({super.key, this.dragsWindow = false, this.trailing});

  static const double height = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget bar = Material(
      color: Colors.transparent, // the window's one ground shows through
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            const SizedBox(width: Space.sm),
            const _NavButtons(),
            const SizedBox(width: Space.sm),
            const Expanded(child: Center(child: _TopSearch())),
            const SizedBox(width: Space.sm),
            const _Bell(),
            const _Profile(),
            const SizedBox(width: Space.xs),
            ?trailing,
          ],
        ),
      ),
    );
    if (dragsWindow) {
      // Empty parts of the bar drag the window; double-click maximises.
      bar = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: () async => await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize(),
        child: bar,
      );
    }
    return bar;
  }
}

// ── Back / forward ───────────────────────────────────────────────────────────

class _NavButtons extends StatelessWidget {
  const _NavButtons();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([activeTab, forwardRevision, ...tabTrails.values.map((t) => t.routes)]),
      builder: (context, _) {
        final tab = activeTab.value;
        final back = tabTrails[tab]!.canPop;
        final fwd = canGoForward(tab);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BarButton(
              glyph: NaviGlyph.chevronLeft,
              tooltip: 'Back (Alt+←)',
              onTap: back ? popActiveTab : null,
            ),
            _BarButton(
              glyph: NaviGlyph.chevron,
              tooltip: 'Forward (Alt+→)',
              onTap: fwd ? () => goForward(context) : null,
            ),
          ],
        );
      },
    );
  }
}

class _BarButton extends StatefulWidget {
  final NaviGlyph glyph;
  final String tooltip;
  final VoidCallback? onTap;

  const _BarButton({required this.glyph, required this.tooltip, required this.onTap});

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final on = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: on,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: NaviPressable(
            onTap: widget.onTap,
            radius: 16,
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on && _hover ? t.hover : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: NaviIcon(widget.glyph, size: 18, color: on ? t.textPrimary : t.textMuted.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Search ───────────────────────────────────────────────────────────────────

class _TopSearch extends ConsumerStatefulWidget {
  const _TopSearch();

  @override
  ConsumerState<_TopSearch> createState() => _TopSearchState();
}

class _TopSearchState extends ConsumerState<_TopSearch> {
  late final _controller = TextEditingController(text: ref.read(searchQueryProvider));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    desktopSearchFocus.addListener(_onFocus);
  }

  @override
  void dispose() {
    desktopSearchFocus.removeListener(_onFocus);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Focusing the field (click or Ctrl+K) opens the Search page, which lists
  /// recent searches until something is typed.
  void _onFocus() {
    if (desktopSearchFocus.hasFocus) {
      if (activeTab.value != AppTab.search) selectAppTab(AppTab.search);
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    }
    setState(() {});
  }

  void _changed(String text) {
    setState(() {});
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), () {
      ref.read(searchQueryProvider.notifier).state = text.trim();
    });
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    desktopSearchFocus.requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    // Something else changed the query (a recent search tapped): mirror it.
    ref.listen(searchQueryProvider, (_, next) {
      if (_controller.text.trim() != next) {
        _controller.text = next;
        setState(() {});
      }
    });
    final focused = desktopSearchFocus.hasFocus;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, minWidth: 120),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_controller.text.isNotEmpty) {
              _clear();
            } else {
              desktopSearchFocus.unfocus();
            }
          },
        },
        child: Container(
          height: 36, // centred in the 48 bar: 6 px above and below
          decoration: BoxDecoration(
            color: focused ? t.bgElevated : t.fill,
            borderRadius: BorderRadius.circular(Radii.capsule),
            border: Border.all(color: focused ? t.textSecondary : Colors.transparent, width: 1),
          ),
          child: Row(
            children: [
              const SizedBox(width: Space.md),
              NaviIcon(NaviGlyph.search, size: 16, color: t.textSecondary),
              const SizedBox(width: Space.sm),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: desktopSearchFocus,
                  onChanged: _changed,
                  onSubmitted: (q) {
                    _timer?.cancel();
                    ref.read(searchQueryProvider.notifier).state = q.trim();
                  },
                  textInputAction: TextInputAction.search,
                  style: t.subheadline.copyWith(color: t.textPrimary),
                  cursorColor: t.textPrimary,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: 'Search songs, albums, artists',
                    hintStyle: t.subheadline,
                  ),
                ),
              ),
              if (_controller.text.isNotEmpty)
                Tooltip(
                  message: 'Clear',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _clear,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                        child: NaviIcon(NaviGlyph.close, size: 14, color: t.textSecondary),
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: Space.md),
                  child: Text('Ctrl K', style: t.caption2.copyWith(color: t.textMuted)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Notifications ────────────────────────────────────────────────────────────

class _Bell extends ConsumerWidget {
  const _Bell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final check = ref.watch(updateCheckProvider).asData?.value;
    final dismissed = ref.watch(dismissedUpdateProvider);
    final update = check != null && check.available && check.manifest.build > dismissed;
    final invites = ref.watch(invitationCountProvider);
    final fetching = ref.watch(onlineFetchAvailableProvider) && !ref.watch(fetchJobsProvider.select((d) => d.isEmpty));
    final any = update || invites > 0 || fetching;

    void open() {
      showDesktopMenu<void>(
        context: context,
        width: 300,
        builder: (_) => SheetGroup(children: [
          if (!any)
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Text('Nothing new.', style: t.footnote),
            ),
          if (update)
            SheetAction(
              label: 'Update available',
              detail: 'NaviVibe ${check.manifest.version}',
              icon: NaviGlyph.download,
              onTap: () => navigateInApp(context, const UpdatesScreen()),
            ),
          if (invites > 0)
            SheetAction(
              label: invites == 1 ? '1 Jam invitation' : '$invites Jam invitations',
              detail: 'Open Jam to join',
              icon: NaviGlyph.group,
              onTap: () => selectAppTab(AppTab.jam),
            ),
          if (fetching)
            SheetAction(
              label: 'Downloads in progress',
              icon: NaviGlyph.downloadCircle,
              onTap: () => showFetchDownloads(context),
            ),
        ]),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _BarButton(glyph: NaviGlyph.bell, tooltip: 'Notifications', onTap: open),
        if (any)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: t.textPrimary, shape: BoxShape.circle, border: Border.all(color: t.bgSurface, width: 1.5)),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Profile ──────────────────────────────────────────────────────────────────

class _Profile extends ConsumerWidget {
  const _Profile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final name = ref.watch(settingsProvider.select((s) => s.username));
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Tooltip(
      message: name.isEmpty ? 'Profile' : name,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: NaviPressable(
          radius: 15,
          onTap: () => showDesktopMenu<void>(
            context: context,
            builder: (_) => SheetGroup(children: [
              if (name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.md, 6, Space.md, 6),
                  child: Text(name, style: t.footnote.copyWith(fontWeight: FontWeight.w600)),
                ),
              SheetAction(
                label: 'Settings',
                icon: NaviGlyph.gear,
                detail: 'Ctrl+,',
                onTap: () => navigateInApp(context, const SettingsScreen()),
              ),
              SheetAction(
                label: 'Sign in another device',
                icon: NaviGlyph.person,
                onTap: () => navigateInApp(context, const SignInAnotherDeviceScreen()),
              ),
              SheetAction(
                label: 'Updates',
                icon: NaviGlyph.download,
                onTap: () => navigateInApp(context, const UpdatesScreen()),
              ),
            ]),
          ),
          child: Semantics(
            button: true,
            label: 'Profile',
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: Space.xs),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.bgOverlay, shape: BoxShape.circle, border: Border.all(color: t.outline, width: 0.5)),
              child: Text(initial, style: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether the shell should draw this bar itself (Linux, where the system owns
/// the title bar) rather than relying on the Windows title bar to host it.
bool get shellDrawsTopBar => PlatformUtils.isDesktop && !PlatformUtils.isWindows;
