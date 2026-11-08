import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:navivibe/core/hive_boxes.dart';
import 'package:navivibe/services/global_hotkey.dart';
import 'package:navivibe/services/mini_player.dart';
import 'package:navivibe/services/window_manager_service.dart';
import 'package:navivibe/services/windows_startup.dart';

class _FakeWindow implements MiniWindow {
  Rect rect = const Rect.fromLTWH(100, 80, 1280, 800);
  bool maximized = false;
  bool onTop = false;
  bool resizable = true;
  Size min = WindowManagerService.minimumSize;
  bool failBounds = false;

  @override
  Future<Rect> bounds() async => rect;
  @override
  Future<bool> isMaximized() async => maximized;
  @override
  Future<void> setMaximized(bool m) async => maximized = m;
  @override
  Future<void> setBounds(Rect b) async {
    if (failBounds && b.size == MiniPlayer.size) throw StateError('no');
    rect = b;
  }

  @override
  Future<void> setMinimumSize(Size s) async => min = s;
  @override
  Future<void> setResizable(bool r) async => resizable = r;
  @override
  Future<void> setAlwaysOnTop(bool t) async => onTop = t;
  @override
  Future<void> show() async {}
}

class _FakeDriver implements HotkeyDriver {
  final registered = <HotkeyBinding>[];
  VoidCallback? press;
  Set<HotkeyBinding> taken = {};
  @override
  Future<void> register(HotkeyBinding b, VoidCallback onPressed) async {
    if (taken.contains(b)) throw StateError('in use');
    registered.add(b);
    press = onPressed;
  }

  @override
  Future<void> unregisterAll() async => registered.clear();
}

void main() {
  group('WindowsStartup', () {
    late List<List<String>> calls;
    late int exit;
    WindowsStartup make() => WindowsStartup(
          executable: r'C:\Apps\NaviVibe\NaviVibe.exe',
          run: (args) async {
            calls.add(args);
            return ProcessResult(0, exit, '', '');
          },
        );
    setUp(() {
      calls = [];
      exit = 0;
    });

    test('enabling writes the quoted exe with --minimized to the per-user Run key', () async {
      expect(await make().setEnabled(true), isTrue);
      final a = calls.single;
      expect(a.first, 'add');
      expect(a, contains(r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'));
      expect(a[a.indexOf('/d') + 1], r'"C:\Apps\NaviVibe\NaviVibe.exe" --minimized');
    });

    test('disabling deletes the value; a value that was never there counts as off', () async {
      expect(await make().setEnabled(false), isTrue);
      expect(calls.single.first, 'delete');
      exit = 1; // delete and query both fail: not registered
      expect(await make().setEnabled(false), isTrue);
    });

    test('a refused change reports false and a throwing reg is swallowed', () async {
      exit = 1;
      expect(await make().setEnabled(true), isFalse);
      final boom = WindowsStartup(run: (_) async => throw const ProcessException('reg', []));
      expect(await boom.setEnabled(true), isFalse);
      expect(await boom.isEnabled(), isFalse);
    });

    test('isEnabled follows the query exit code; the flag is recognised', () async {
      expect(await make().isEnabled(), isTrue);
      exit = 1;
      expect(await make().isEnabled(), isFalse);
      expect(WindowsStartup.startsMinimized(['--minimized']), isTrue);
      expect(WindowsStartup.startsMinimized(const []), isFalse);
    });
  });

  group('MiniPlayer', () {
    late _FakeWindow w;
    late MiniPlayer mini;
    setUp(() {
      w = _FakeWindow();
      mini = MiniPlayer(window: w);
    });
    tearDown(() => WindowManagerService.suspendSaving = false);

    test('enter shrinks, floats, keeps the top-right corner and stops saving window size', () async {
      await mini.enter();
      expect(mini.active.value, isTrue);
      expect(w.onTop, isTrue);
      expect(w.resizable, isFalse);
      expect(w.rect.size, MiniPlayer.size);
      expect(w.rect.right, 1380);
      expect(w.rect.top, 80);
      expect(WindowManagerService.suspendSaving, isTrue);
    });

    test('exit restores size, position, minimum, z-order and saving', () async {
      await mini.enter();
      await mini.exit();
      expect(mini.active.value, isFalse);
      expect(w.rect, const Rect.fromLTWH(100, 80, 1280, 800));
      expect(w.onTop, isFalse);
      expect(w.resizable, isTrue);
      expect(w.min, WindowManagerService.minimumSize);
      expect(WindowManagerService.suspendSaving, isFalse);
    });

    test('a maximized window is un-maximized for mini and maximized again after', () async {
      w.maximized = true;
      await mini.enter();
      expect(w.maximized, isFalse);
      await mini.exit();
      expect(w.maximized, isTrue);
    });

    test('toggle flips, and a failure while entering leaves the full window as it was', () async {
      await mini.toggle();
      expect(mini.active.value, isTrue);
      await mini.toggle();
      expect(mini.active.value, isFalse);
      w.failBounds = true;
      await mini.enter();
      expect(mini.active.value, isFalse);
      expect(w.onTop, isFalse);
      expect(w.rect, const Rect.fromLTWH(100, 80, 1280, 800));
      expect(WindowManagerService.suspendSaving, isFalse);
    });

    test('entering twice keeps the first remembered bounds', () async {
      await mini.enter();
      await mini.enter();
      await mini.exit();
      expect(w.rect, const Rect.fromLTWH(100, 80, 1280, 800));
    });
  });

  group('HotkeyBinding', () {
    test('default is Ctrl+Alt+Space and round-trips through storage', () {
      final d = HotkeyBinding.defaultBinding;
      expect(d.label, 'Ctrl+Alt+Space');
      expect(HotkeyBinding.decode(d.encode()), d);
      final f = HotkeyBinding(LogicalKeyboardKey.keyK, const {HotkeyModifierKey.shift, HotkeyModifierKey.meta});
      expect(f.label, 'Shift+Win+K');
      expect(HotkeyBinding.decode(f.encode()), f);
    });

    test('a shortcut needs a modifier and a real key; damaged storage decodes to null', () {
      expect(HotkeyBinding(LogicalKeyboardKey.keyK, const {}).isValid, isFalse);
      expect(HotkeyBinding(LogicalKeyboardKey.controlLeft, const {HotkeyModifierKey.alt}).isValid, isFalse);
      expect(HotkeyBinding.decode('nope'), isNull);
      expect(HotkeyBinding.decode(null), isNull);
      expect(HotkeyBinding.decode(HotkeyBinding(LogicalKeyboardKey.keyK, const {}).encode()), isNull);
    });
  });

  group('GlobalHotkey', () {
    late Directory dir;
    late _FakeDriver driver;
    late GlobalHotkey hk;
    late int presses;

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('hive_hotkey');
      Hive.init(dir.path);
      HiveBoxes.prefs = await Hive.openBox('prefs');
    });
    tearDownAll(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    setUp(() async {
      await HiveBoxes.prefs.clear();
      driver = _FakeDriver();
      hk = GlobalHotkey(driver: driver);
      presses = 0;
    });

    test('registers Ctrl+Alt+Space by default and calls back on a press', () async {
      expect(await hk.init(() => presses++), isTrue);
      expect(driver.registered, [HotkeyBinding.defaultBinding]);
      driver.press!();
      expect(presses, 1);
    });

    test('turned off: nothing is registered; turned on again: it is', () async {
      await hk.init(() {});
      await hk.setEnabled(false);
      expect(driver.registered, isEmpty);
      expect(GlobalHotkey.enabled, isFalse);
      await hk.setEnabled(true);
      expect(driver.registered, hasLength(1));
    });

    test('a new shortcut replaces the old one and is remembered', () async {
      await hk.init(() {});
      final b = HotkeyBinding(LogicalKeyboardKey.keyN, const {HotkeyModifierKey.control, HotkeyModifierKey.shift});
      expect(await hk.setBinding(b), isTrue);
      expect(driver.registered, [b]);
      expect(GlobalHotkey.binding, b);
    });

    test('a shortcut another app owns is refused and the previous one stays', () async {
      await hk.init(() {});
      final b = HotkeyBinding(LogicalKeyboardKey.keyN, const {HotkeyModifierKey.control});
      driver.taken = {b};
      expect(await hk.setBinding(b), isFalse);
      expect(GlobalHotkey.binding, HotkeyBinding.defaultBinding);
      expect(driver.registered, [HotkeyBinding.defaultBinding]);
    });

    test('a modifier-less shortcut is rejected before touching the system', () async {
      await hk.init(() {});
      expect(await hk.setBinding(HotkeyBinding(LogicalKeyboardKey.keyN, const {})), isFalse);
      expect(driver.registered, [HotkeyBinding.defaultBinding]);
    });
  });
}
