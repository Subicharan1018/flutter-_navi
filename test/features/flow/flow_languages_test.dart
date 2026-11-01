import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/focus/navi_focus.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/flow/logic/flow_prefs_provider.dart';
import 'package:navivibe/features/flow/ui/flow_settings.dart';
import 'package:navivibe/features/listen/data/listen_api.dart';
import 'package:navivibe/features/listen/data/listen_models.dart';
import 'package:navivibe/features/listen/logic/listen_providers.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';

const _available = [
  {'code': 'ta', 'name': 'Tamil', 'songs': 1690},
  {'code': 'ml', 'name': 'Malayalam', 'songs': 120},
  {'code': 'en', 'name': 'English', 'songs': 1},
];

/// A tiny stand-in for the server's `/flow/prefs`: remembers what was saved.
class _Server implements HttpClientAdapter {
  List<String> languages;
  bool explore;
  bool fail = false;
  final List<RequestOptions> seen = [];
  _Server({this.languages = const [], this.explore = true});

  Map<String, dynamic> get body => {'languages': languages, 'explore': explore, 'available': _available};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? requestBody, Future<void>? cancel) async {
    seen.add(o);
    if (fail && o.method == 'PUT') {
      return ResponseBody.fromString('{}', 503, headers: {'content-type': ['application/json']});
    }
    if (o.method == 'PUT') {
      final data = o.data as Map;
      if (data['languages'] is List) languages = [...(data['languages'] as List).cast<String>()];
      if (data['explore'] is bool) explore = data['explore'] as bool;
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {'content-type': ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

ListenApi _apiOver(_Server s) => ListenApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = s);

class _Prefs extends FlowPrefsNotifier {
  final FlowPrefs initial;
  _Prefs(this.initial);

  @override
  Future<FlowPrefs> build() async => initial;
}

FlowPrefs _prefs({List<String> languages = const [], bool explore = true}) =>
    FlowPrefs.fromJson({'languages': languages, 'explore': explore, 'available': _available});

void main() {
  tearDown(() {
    PlatformUtils.debugTvOverride = null;
    PlatformUtils.debugDesktopOverride = null;
  });

  group('the setting', () {
    test('reads the server reply and reads out well in Settings', () {
      final p = _prefs(languages: ['ta', 'ml']);
      expect(p.isAny, isFalse);
      expect(p.available.map((l) => (l.code, l.name, l.songs)).first, ('ta', 'Tamil', 1690));
      expect(p.summary, 'Tamil, Malayalam');
      expect(_prefs(languages: ['ta']).summary, 'Tamil');
      expect(_prefs().summary, 'Any');
      expect(_prefs(languages: ['ta', 'ml', 'en']).summary, '3 languages');
      expect(_prefs(languages: ['xx']).summary, 'XX');
    });

    test('defaults to any language with exploring on, whatever the server leaves out', () {
      final p = FlowPrefs.fromJson(const {});
      expect(p.isAny, isTrue);
      expect(p.explore, isTrue);
      expect(p.available, isEmpty);
      expect(FlowPrefs.fromJson({'explore': false, 'languages': ['ta', 5, '']}).languages, ['ta']);
      expect(FlowPrefs.fromJson({'explore': false}).explore, isFalse);
    });

    test('copyWith changes only what it is given and equality follows the choice', () {
      final p = _prefs(languages: ['ta']);
      expect(p.copyWith(explore: false).languages, ['ta']);
      expect(p.copyWith(languages: const []).explore, isTrue);
      expect(p, _prefs(languages: ['ta']));
      expect(p == _prefs(languages: ['ml']), isFalse);
      expect(p == _prefs(languages: ['ta'], explore: false), isFalse);
    });

    test('the API reads with GET and writes only the fields it is given', () async {
      final server = _Server();
      final api = _apiOver(server);
      expect((await api.flowPrefs()).available.length, 3);
      expect(server.seen.single.method, 'GET');
      expect(server.seen.single.path, '/flow/prefs');
      await api.saveFlowPrefs(explore: false);
      expect(server.seen.last.method, 'PUT');
      expect(server.seen.last.data, {'explore': false});
      await api.saveFlowPrefs(languages: ['ml']);
      expect(server.seen.last.data, {'languages': ['ml']});
      expect(server.languages, ['ml']);
      expect(server.explore, isFalse);
    });

    test('a server error reads as a message', () async {
      final server = _Server()..fail = true;
      await expectLater(_apiOver(server).saveFlowPrefs(explore: false), throwsA(isA<ListenException>()));
    });
  });

  group('the notifier', () {
    ProviderContainer container(_Server s, FlowPrefs initial) {
      final c = ProviderContainer(overrides: [
        listenApiProvider.overrideWithValue(_apiOver(s)),
        flowPrefsProvider.overrideWith(() => _Prefs(initial)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('saves a pick and keeps the server’s answer', () async {
      final s = _Server();
      final c = container(s, _prefs());
      await c.read(flowPrefsProvider.future);
      await c.read(flowPrefsProvider.notifier).setLanguages(['ta', 'ml']);
      expect(s.languages, ['ta', 'ml']);
      expect(c.read(flowPrefsProvider).value!.languages, ['ta', 'ml']);
      await c.read(flowPrefsProvider.notifier).setExplore(false);
      expect(s.explore, isFalse);
      expect(c.read(flowPrefsProvider).value!.explore, isFalse);
      expect(c.read(flowPrefsProvider).value!.languages, ['ta', 'ml']);
    });

    test('puts the old setting back when the server says no', () async {
      final s = _Server(languages: ['ta'])..fail = true;
      final c = container(s, _prefs(languages: ['ta']));
      await c.read(flowPrefsProvider.future);
      await expectLater(c.read(flowPrefsProvider.notifier).setLanguages(['ml']), throwsA(isA<ListenException>()));
      expect(c.read(flowPrefsProvider).value!.languages, ['ta']);
      await expectLater(c.read(flowPrefsProvider.notifier).setExplore(false), throwsA(isA<ListenException>()));
      expect(c.read(flowPrefsProvider).value!.explore, isTrue);
    });
  });

  group('screens', () {
    late _Server server;

    Future<void> show(WidgetTester tester, Widget page, {FlowPrefs? prefs, Size size = const Size(390, 844)}) async {
      server = _Server(languages: prefs?.languages ?? const [], explore: prefs?.explore ?? true);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final List<Override> overrides = [
        listenApiProvider.overrideWithValue(_apiOver(server)),
        flowPrefsProvider.overrideWith(() => _Prefs(prefs ?? _prefs())),
      ];
      await tester.pumpWidget(ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: ThemeTokens(tokens: AppThemeTokens.fallback, child: page)),
      ));
      await tester.pumpAndSettle();
    }

    int checks(WidgetTester tester) =>
        tester.widgetList<NaviIcon>(find.byType(NaviIcon)).where((i) => i.glyph == NaviGlyph.check).length;

    testWidgets('Any is chosen by default and the library’s languages show their song counts', (tester) async {
      await show(tester, const FlowLanguagesScreen());
      expect(find.text('Any (learn from me)'), findsOneWidget);
      expect(find.text('Tamil'), findsOneWidget);
      expect(find.text('1,690 songs'), findsOneWidget);
      expect(find.text('120 songs'), findsOneWidget);
      expect(find.text('1 song'), findsOneWidget);
      expect(checks(tester), 1);                                       // only Any
      expect(tester.takeException(), isNull);
    });

    testWidgets('picking languages selects them and takes Any off; unpicking the last goes back to Any', (tester) async {
      await show(tester, const FlowLanguagesScreen());
      await tester.tap(find.text('Tamil'));
      await tester.pumpAndSettle();
      expect(server.languages, ['ta']);
      expect(checks(tester), 1);
      await tester.tap(find.text('Malayalam'));
      await tester.pumpAndSettle();
      expect(server.languages, ['ta', 'ml']);
      expect(checks(tester), 2);
      await tester.tap(find.text('Tamil'));
      await tester.pumpAndSettle();
      expect(server.languages, ['ml']);
      await tester.tap(find.text('Malayalam'));
      await tester.pumpAndSettle();
      expect(server.languages, isEmpty);
      expect(checks(tester), 1);                                       // Any again
    });

    testWidgets('Any clears whatever was picked', (tester) async {
      await show(tester, const FlowLanguagesScreen(), prefs: _prefs(languages: ['ta', 'ml']));
      expect(checks(tester), 2);
      await tester.tap(find.text('Any (learn from me)'));
      await tester.pumpAndSettle();
      expect(server.languages, isEmpty);
      expect(checks(tester), 1);
    });

    testWidgets('a failed save snaps back and says so', (tester) async {
      await show(tester, const FlowLanguagesScreen());
      server.fail = true;
      await tester.tap(find.text('Tamil'));
      await tester.pumpAndSettle();
      expect(checks(tester), 1);                                       // still only Any
      expect(find.textContaining('server'), findsWidgets);             // the message (toast) names the problem
    });

    testWidgets('the Settings section shows the choice and Try new languages saves at once', (tester) async {
      await show(tester, const SingleChildScrollView(child: FlowSettingsSection()), prefs: _prefs(languages: ['ta', 'ml']));
      expect(find.text('Flow & Mixes'), findsOneWidget);
      expect(find.text('Languages'), findsOneWidget);
      expect(find.text('Tamil, Malayalam'), findsOneWidget);
      expect(find.text('Try new languages'), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsOneWidget);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(server.explore, isFalse);
      expect(find.textContaining('and nothing outside them'), findsOneWidget);
    });

    testWidgets('on a TV every choice can take focus from the D-pad and nothing overflows', (tester) async {
      PlatformUtils.debugTvOverride = true;
      await show(tester, const FlowLanguagesScreen(), size: const Size(1920, 1080));
      expect(find.byType(NaviFocusRing).evaluate().length, greaterThanOrEqualTo(4));   // Any + three languages
      expect(tester.takeException(), isNull);
      await show(tester, const SingleChildScrollView(child: FlowSettingsSection()), size: const Size(1920, 1080));
      expect(find.byType(NaviFocusRing).evaluate().length, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('on desktop the list is the same compact grouped list', (tester) async {
      PlatformUtils.debugDesktopOverride = true;
      await show(tester, const FlowLanguagesScreen(), size: const Size(1280, 720));
      expect(find.text('Any (learn from me)'), findsOneWidget);
      expect(find.text('Tamil'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Malayalam'));
      await tester.pumpAndSettle();
      expect(server.languages, ['ml']);
    });

    testWidgets('a narrow phone fits too', (tester) async {
      await show(tester, const FlowLanguagesScreen(), size: const Size(320, 568));
      expect(tester.takeException(), isNull);
      await show(tester, const SingleChildScrollView(child: FlowSettingsSection()), size: const Size(320, 568));
      expect(tester.takeException(), isNull);
    });
  });
}
