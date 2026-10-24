import 'package:flutter/widgets.dart';

import '../../utils/platform_utils.dart';

// =============================================================================
// window_size.dart — one place that turns a width into a layout class.
//
//   compact   < 800    phone-style shell: bottom tabs, one pane
//   medium    < 1200   sidebar shell, Now Playing opens as a full page
//   expanded  >= 1200  sidebar shell plus the Now Playing side panel
//
// The cut-offs are the same two numbers PlatformUtils already documents, so
// every screen that asks "is this wide?" gives the same answer.
// =============================================================================

enum WindowSize {
  compact,
  medium,
  expanded;

  static WindowSize of(double width) {
    if (width < PlatformUtils.kDesktopBreakpoint) return compact;
    if (width < PlatformUtils.kWideScreenBreakpoint) return medium;
    return expanded;
  }

  static WindowSize ofContext(BuildContext context) => of(MediaQuery.sizeOf(context).width);

  bool get isCompact => this == compact;
  bool get isExpanded => this == expanded;

  /// True when the side panel beside the content fits.
  bool get hasSidePanel => this == expanded;
}

/// Which navigation chrome a window of [size] gets.
enum ShellKind {
  /// Bottom tab bar and floating mini player.
  phone,

  /// Sidebar, content, player bar (desktop windows and large tablets).
  sidebar,

  /// 10-foot: icon rail, big targets, remote friendly.
  tv;

  /// Picks the shell. A TV always gets [tv]; a desktop window or a tablet
  /// (shortest side 600 dp or more) gets [sidebar] once it is wide enough;
  /// everything else, including a narrowed desktop window, stays [phone].
  static ShellKind of(Size size) {
    if (PlatformUtils.isTv) return tv;
    if (size.width < PlatformUtils.kDesktopBreakpoint) return phone;
    if (PlatformUtils.isDesktop || size.shortestSide >= 600) return sidebar;
    return phone;
  }

  static ShellKind ofContext(BuildContext context) => of(MediaQuery.sizeOf(context));
}
