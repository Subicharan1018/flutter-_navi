import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/layout/window_size.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/shell/nav_stack.dart';

void main() {
  tearDown(() {
    PlatformUtils.debugTvOverride = null;
    PlatformUtils.debugDesktopOverride = null;
  });

  group('WindowSize', () {
    test('compact below 800, medium below 1200, expanded from 1200', () {
      expect(WindowSize.of(320), WindowSize.compact);
      expect(WindowSize.of(799.9), WindowSize.compact);
      expect(WindowSize.of(800), WindowSize.medium);
      expect(WindowSize.of(1199), WindowSize.medium);
      expect(WindowSize.of(1200), WindowSize.expanded);
      expect(WindowSize.of(3840), WindowSize.expanded);
    });

    test('only expanded has room for the side panel', () {
      expect(WindowSize.compact.hasSidePanel, isFalse);
      expect(WindowSize.medium.hasSidePanel, isFalse);
      expect(WindowSize.expanded.hasSidePanel, isTrue);
    });
  });

  group('ShellKind', () {
    test('a TV always gets the 10-foot shell', () {
      PlatformUtils.debugTvOverride = true;
      expect(ShellKind.of(const Size(960, 540)), ShellKind.tv);
      expect(ShellKind.of(const Size(400, 800)), ShellKind.tv);
    });

    test('a desktop window is a phone shell until 800 wide, then a sidebar', () {
      PlatformUtils.debugTvOverride = false;
      PlatformUtils.debugDesktopOverride = true;
      expect(ShellKind.of(const Size(480, 700)), ShellKind.phone);
      expect(ShellKind.of(const Size(799, 700)), ShellKind.phone);
      expect(ShellKind.of(const Size(800, 600)), ShellKind.sidebar);
      expect(ShellKind.of(const Size(1600, 900)), ShellKind.sidebar);
    });

    test('a tablet gets a sidebar when wide, a landscape phone does not', () {
      PlatformUtils.debugTvOverride = false;
      PlatformUtils.debugDesktopOverride = false;
      expect(ShellKind.of(const Size(1280, 800)), ShellKind.sidebar); // 10" tablet landscape
      expect(ShellKind.of(const Size(900, 412)), ShellKind.phone); // big phone landscape
    });
  });

  group('breadcrumb titles', () {
    test('derive a readable title from the screen type', () {
      expect(titleFromType(_AlbumDetailsScreen), 'Album Details');
      expect(titleFromType(_SongsPage), 'Songs');
    });
  });
}

class _AlbumDetailsScreen {}

class _SongsPage {}
