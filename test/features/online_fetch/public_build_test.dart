import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/build_flavor.dart';
import 'package:navivibe/core/constants.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/online_fetch/ui/fetch_activity.dart';
import 'package:navivibe/features/online_fetch/ui/search_online_row.dart';

/// Public builds (PUBLIC_BUILD=true) must not offer any online download; the
/// default personal build keeps all of it. The compile-time flag feeds
/// [onlineFetchAvailableProvider], which these tests override for both states.
void main() {
  Widget host(Widget child, {required bool available, bool? serverAllows}) => ProviderScope(
        key: UniqueKey(),
        overrides: [
          onlineFetchAvailableProvider.overrideWithValue(available),
          // Only set when the server's answer matters; in a public build the
          // real provider must say "no" without asking the server at all.
          if (serverAllows != null) onlineFetchEnabledProvider.overrideWith((ref) async => serverAllows),
        ],
        child: MaterialApp(
          home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: child)),
        ),
      );

  test('the flag is off by default, so personal builds keep everything', () {
    expect(kPublicBuild, isFalse);
    expect(Constants.suggestedServerUrl, isNotEmpty);
  });

  group('public build (feature unavailable)', () {
    testWidgets('no-results page offers no online search or playlist link', (tester) async {
      await tester.pumpWidget(host(const NoLibraryResults(query: 'kaavaalaa'), available: false));
      await tester.pump();
      expect(find.text('No results for “kaavaalaa”'), findsOneWidget);
      expect(find.text('Search Online'), findsNothing);
      expect(find.text('Send a playlist link'), findsNothing);
    });

    testWidgets('the row under results is empty', (tester) async {
      await tester.pumpWidget(host(const SearchOnlineRow(query: 'abc'), available: false));
      await tester.pump();
      expect(find.textContaining('Search online'), findsNothing);
      expect(find.textContaining('playlist link'), findsNothing);
    });

    test('the real provider answers no without asking the server', () async {
      final c = ProviderContainer(overrides: [onlineFetchAvailableProvider.overrideWithValue(false)]);
      addTearDown(c.dispose);
      final sub = c.listen(onlineFetchEnabledProvider, (_, _) {});
      expect(await c.read(onlineFetchEnabledProvider.future), isFalse);
      sub.close();
    });

    testWidgets('the finished-download banner never appears', (tester) async {
      await tester.pumpWidget(host(const FetchFinishedBanner(), available: false));
      final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
      c.read(fetchFinishedProvider.notifier).announce(headline: 'Album downloaded', detail: 'x', songIds: ['a']);
      await tester.pumpAndSettle();
      expect(find.text('Album downloaded'), findsNothing);
    });
  });

  group('personal build (feature available)', () {
    testWidgets('no-results page offers Search Online and Send a playlist link', (tester) async {
      await tester.pumpWidget(host(const NoLibraryResults(query: 'kaavaalaa'), available: true, serverAllows: true));
      await tester.pump();
      expect(find.text('Search Online'), findsOneWidget);
      expect(find.text('Send a playlist link'), findsOneWidget);
    });

    testWidgets('the row under results is shown', (tester) async {
      await tester.pumpWidget(host(const SearchOnlineRow(query: 'abc'), available: true, serverAllows: true));
      await tester.pump();
      expect(find.textContaining('Search online'), findsOneWidget);
    });
  });
}
