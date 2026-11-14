import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/utils/web_env.dart';
import 'package:navivibe/utils/web_form_factor.dart';
import 'package:navivibe/widgets/shell/web_form_factor_scope.dart';

const _chromeWindows = BrowserInfo(
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Safari/537.36',
);
const _chromeAndroid = BrowserInfo(
  userAgent: 'Mozilla/5.0 (Linux; Android 14; CPH2581) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/131.0.0.0 Mobile Safari/537.36',
  maxTouchPoints: 5,
  finePointer: false,
);
const _iPhone = BrowserInfo(
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1',
  maxTouchPoints: 5,
  finePointer: false,
);
// iPadOS Safari asks for desktop sites and reports a Mac.
const _iPadDesktopUa = BrowserInfo(
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/18.1 Safari/605.1.15',
  maxTouchPoints: 5,
  finePointer: false,
);
const _macSafari = BrowserInfo(
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/18.1 Safari/605.1.15',
);

FormFactor _decide(BrowserInfo info, double width, [FormFactor? previous]) =>
    WebFormFactor.decide(info: info, viewportWidth: width, previous: previous);

void main() {
  tearDown(() => WebFormFactor.debugReset());

  group('WebFormFactor.decide', () {
    test('a desktop browser with a wide window gets the desktop UI', () {
      expect(_decide(_chromeWindows, 1280), FormFactor.desktop);
      expect(_decide(_macSafari, 1440), FormFactor.desktop);
    });

    test('a desktop browser narrowed below the breakpoint gets the phone UI', () {
      expect(_decide(_chromeWindows, 600), FormFactor.phone);
      expect(_decide(_chromeWindows, WebFormFactor.desktopMinWidth - 1), FormFactor.phone);
      expect(_decide(_chromeWindows, WebFormFactor.desktopMinWidth), FormFactor.desktop);
    });

    test('phone browsers get the phone UI at any width, even landscape', () {
      expect(_decide(_chromeAndroid, 375), FormFactor.phone);
      expect(_decide(_chromeAndroid, 915), FormFactor.phone);
      expect(_decide(_iPhone, 932), FormFactor.phone);
    });

    test('iPadOS asking for the desktop site still counts as a touch device', () {
      expect(WebFormFactor.isMobileBrowser(_iPadDesktopUa), isTrue);
      expect(_decide(_iPadDesktopUa, 1366), FormFactor.phone);
      expect(WebFormFactor.isMobileBrowser(_macSafari), isFalse);
    });

    test('a touch-only machine with a desktop user agent gets the phone UI', () {
      const chromebookTablet = BrowserInfo(
        userAgent: 'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36',
        maxTouchPoints: 10,
        finePointer: false,
      );
      expect(_decide(chromebookTablet, 1200), FormFactor.phone);
    });

    test('a touch laptop with a mouse keeps the desktop UI', () {
      const touchLaptop = BrowserInfo(userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131', maxTouchPoints: 10);
      expect(_decide(touchLaptop, 1280), FormFactor.desktop);
    });

    test('hysteresis: once desktop, a window just under the breakpoint stays desktop', () {
      expect(_decide(_chromeWindows, 780, FormFactor.desktop), FormFactor.desktop);
      expect(_decide(_chromeWindows, 780, FormFactor.phone), FormFactor.phone);
      expect(_decide(_chromeWindows, WebFormFactor.desktopExitWidth - 1, FormFactor.desktop), FormFactor.phone);
    });
  });

  group('WebFormFactor.refresh (live switching)', () {
    test('resizing across the breakpoint flips the current form factor', () {
      WebFormFactor.debugReset(info: _chromeWindows);
      final seen = <FormFactor>[];
      void listener() => seen.add(WebFormFactor.current.value);
      WebFormFactor.current.addListener(listener);
      addTearDown(() => WebFormFactor.current.removeListener(listener));

      WebFormFactor.refresh(1280);
      expect(WebFormFactor.current.value, FormFactor.desktop);
      WebFormFactor.refresh(500);
      expect(WebFormFactor.current.value, FormFactor.phone);
      WebFormFactor.refresh(1024);
      expect(WebFormFactor.current.value, FormFactor.desktop);
      expect(seen, [FormFactor.phone, FormFactor.desktop]);
    });

    test('the first decision has no hysteresis', () {
      WebFormFactor.debugReset(info: _chromeWindows); // starts at "desktop"
      WebFormFactor.refresh(780);
      expect(WebFormFactor.current.value, FormFactor.phone);
    });

    test('a phone browser never switches to desktop on rotation', () {
      WebFormFactor.debugReset(info: _chromeAndroid);
      WebFormFactor.refresh(412);
      WebFormFactor.refresh(915);
      expect(WebFormFactor.current.value, FormFactor.phone);
      expect(WebFormFactor.touchPrimary, isTrue);
    });
  });

  group('PlatformUtils on a native host', () {
    // The test host is a native desktop OS (Windows/Linux CI): the browser
    // form factor must not leak into native behaviour.
    test('desktop layout follows the OS, not the web form factor', () {
      PlatformUtils.debugDesktopOverride = null; // flutter_test_config pins "phone"
      WebFormFactor.debugReset(info: _chromeAndroid, initial: FormFactor.phone);
      expect(PlatformUtils.isWeb, isFalse);
      expect(PlatformUtils.isDesktop, PlatformUtils.isNativeDesktop);
      expect(PlatformUtils.isTouchWeb, isFalse);
    });

    test('native capabilities stay on', () {
      expect(PlatformUtils.supportsOfflineFiles, isTrue);
      expect(PlatformUtils.supportsSongRecognition, isTrue);
      expect(PlatformUtils.supportsWindowManager, PlatformUtils.isNativeDesktop);
    });

    test('the debug override still wins', () {
      PlatformUtils.debugDesktopOverride = false;
      addTearDown(() => PlatformUtils.debugDesktopOverride = null);
      expect(PlatformUtils.isDesktop, isFalse);
    });
  });

  testWidgets('WebFormFactorScope is a pass-through on native builds', (tester) async {
    const child = SizedBox(key: Key('app'));
    await tester.pumpWidget(const WebFormFactorScope(child: child));
    expect(find.byKey(const Key('app')), findsOneWidget);
    expect(find.byType(KeyedSubtree), findsNothing);
  });

  test('readBrowserInfo is null outside a browser (stub)', () {
    expect(readBrowserInfo(), isNull);
  });
}
