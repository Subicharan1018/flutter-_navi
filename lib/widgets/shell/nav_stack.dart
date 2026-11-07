import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_tab.dart';

// =============================================================================
// nav_stack.dart — the app's back stack.
//
// Every tab owns a Navigator, so each keeps its own history when you switch
// away and back, on a phone, a desktop window and a TV alike. [NavTrail] watches
// one tab's stack so the shell can answer "can I go back?" and draw
// breadcrumbs; [navigateInApp] pushes onto whichever tab is showing.
// =============================================================================

/// One step on a tab's stack, for breadcrumbs.
class Crumb {
  final String title;
  final Route<dynamic> route;
  const Crumb(this.title, this.route);
}

/// Watches one tab's Navigator and publishes its stack.
class NavTrail extends NavigatorObserver {
  final AppTab tab;
  NavTrail(this.tab);

  final ValueNotifier<List<Route<dynamic>>> routes = ValueNotifier(const []);

  int get depth => routes.value.length;
  bool get canPop => depth > 1;

  /// Titles for breadcrumbs; the root is the tab's own name and routes pushed
  /// without a name are skipped.
  List<Crumb> get crumbs => [
        for (var i = 0; i < routes.value.length; i++)
          if (i == 0)
            Crumb(tab.label, routes.value[i])
          else if (routes.value[i].settings.name case final name? when name.isNotEmpty)
            Crumb(name, routes.value[i]),
      ];

  void _set(List<Route<dynamic>> next) {
    void apply() => routes.value = next;
    // Observers also fire while the Navigator itself is being built.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  // Compute against the latest pending value so same-frame changes compose.
  List<Route<dynamic>> _pending = const [];

  void _update(List<Route<dynamic>> Function(List<Route<dynamic>>) change) {
    _pending = change(_pending);
    _set(_pending);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      // No previous route means a fresh Navigator: start the stack over.
      _update((l) => previousRoute == null ? [route] : [...l, route]);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update((l) => [...l]..remove(route));

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update((l) => [...l]..remove(route));

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _update((l) {
        final next = [...l];
        final i = oldRoute == null ? -1 : next.indexOf(oldRoute);
        if (i >= 0 && newRoute != null) next[i] = newRoute;
        return next;
      });
}

/// One navigator key and trail per tab.
final Map<AppTab, GlobalKey<NavigatorState>> tabNavigators = {
  for (final tab in AppTab.values) tab: GlobalKey<NavigatorState>(debugLabel: 'tab-${tab.name}'),
};

final Map<AppTab, NavTrail> tabTrails = {for (final tab in AppTab.values) tab: NavTrail(tab)};

/// The tab currently showing; pushes made without a context of their own go
/// into its stack.
final ValueNotifier<AppTab> activeTab = ValueNotifier(AppTab.home);

/// Opens [screen] inside the app chrome: the active tab's stack, so the tab
/// bar / sidebar and the player stay on screen. Works from sheets and dialogs
/// too, since it doesn't depend on [context]'s own navigator.
///
/// [title] is the breadcrumb label; without it one is derived from the screen's
/// class name (`AlbumDetailsScreen` → "Album Details").
void navigateInApp(BuildContext context, Widget screen, {String? title}) {
  final tab = activeTab.value;
  // Going somewhere new ends whatever "forward" there was.
  if (_forward[tab]!.isNotEmpty) {
    _forward[tab]!.clear();
    forwardRevision.value++;
  }
  _push(context, tab, screen, title);
}

void _push(BuildContext context, AppTab tab, Widget screen, String? title) {
  final name = title ?? titleFromType(screen.runtimeType);
  final route = MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => screen,
  );
  _entries[route] = _Entry(screen, name);
  (tabNavigators[tab]?.currentState ?? Navigator.of(context)).push(route);
}

class _Entry {
  final Widget screen;
  final String title;
  const _Entry(this.screen, this.title);
}

/// What each pushed route showed, so Back can be undone by Forward.
final Expando<_Entry> _entries = Expando<_Entry>('route entries');

/// Pages Back stepped out of, newest last, per tab.
final Map<AppTab, List<_Entry>> _forward = {for (final tab in AppTab.values) tab: []};

/// Bumped whenever a tab's forward list changes, so toolbars can redraw.
final ValueNotifier<int> forwardRevision = ValueNotifier(0);

bool canGoForward([AppTab? tab]) => _forward[tab ?? activeTab.value]!.isNotEmpty;

/// Re-opens the page Back last left in the active tab. False when there is none.
bool goForward(BuildContext context) {
  final tab = activeTab.value;
  final list = _forward[tab]!;
  if (list.isEmpty) return false;
  final e = list.removeLast();
  forwardRevision.value++;
  _push(context, tab, e.screen, e.title);
  return true;
}

/// "PlaylistDetailsScreen" → "Playlist Details".
String titleFromType(Type type) {
  final raw = type.toString().replaceAll(RegExp(r'^_|<.*>$'), '').replaceAll(RegExp(r'(Screen|Page)$'), '');
  final spaced = raw.replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ').trim();
  return spaced.isEmpty ? raw : spaced;
}

/// Pops one level of the active tab. False when it is already at its root.
bool popActiveTab() {
  final nav = tabNavigators[activeTab.value]?.currentState;
  if (nav == null || !nav.canPop()) return false;
  final top = tabTrails[activeTab.value]!.routes.value.lastOrNull;
  final entry = top == null ? null : _entries[top];
  if (entry != null) {
    _forward[activeTab.value]!.add(entry);
    forwardRevision.value++;
  }
  nav.pop();
  return true;
}

/// Pops the active tab back to [crumb] (a breadcrumb tap).
void popToCrumb(Crumb crumb) =>
    tabNavigators[activeTab.value]?.currentState?.popUntil((r) => r == crumb.route);

/// Asks the shell to switch to [tab] from anywhere (Home's Jam card, the
/// "Jam live" pill, a Library shortcut).
void selectAppTab(AppTab tab) => tabRequest.value = tab;

/// Read by the shell; cleared once it has switched.
final ValueNotifier<AppTab?> tabRequest = ValueNotifier(null);

/// The current tab chosen again: back to its root (iOS); Search goes on into
/// typing (Spotify), so the thumb never reaches for the field at the top.
void reselectTab(AppTab tab) {
  tabNavigators[tab]?.currentState?.popUntil((r) => r.isFirst);
  if (tab == AppTab.search) searchFieldRequest.value = true;
}

/// Set to put the caret in Search's field and raise the keyboard (a second
/// tap on the Search tab, Ctrl+F, '/'). Search clears it once it has, so a
/// request made before Search was first built still lands.
final ValueNotifier<bool> searchFieldRequest = ValueNotifier(false);
