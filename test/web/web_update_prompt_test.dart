import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/widgets/shell/web_update_prompt.dart';

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer(bool playing)
      : super(PlayerState(
          queue: const [],
          currentIndex: 0,
          isPlaying: playing,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: const [],
          syncMode: SyncMode.activeHere,
        ));

  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

void main() {
  late int applied;

  Widget app({bool enabled = true, bool playing = false}) {
    final tokens = AppThemeTokens.fallback;
    return ProviderScope(
      overrides: [playerProvider.overrideWith((ref) => _FakePlayer(playing))],
      child: ThemeTokens(
        tokens: tokens,
        child: MaterialApp(
          theme: AppTheme.build(tokens),
          builder: (context, child) => WebUpdatePrompt(enabled: enabled, apply: () => applied++, child: child!),
          home: const Scaffold(body: Text('app')),
        ),
      ),
    );
  }

  setUp(() {
    applied = 0;
    webUpdateReady.value = false;
  });

  testWidgets('nothing shows until a newer build is live', (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('New version available'), findsNothing);
    webUpdateReady.value = true;
    await tester.pump();
    expect(find.text('New version available'), findsOneWidget);
  });

  testWidgets('Reload switches to the new build', (tester) async {
    webUpdateReady.value = true;
    await tester.pumpWidget(app());
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(applied, 1);
  });

  testWidgets('Later hides the prompt without reloading', (tester) async {
    webUpdateReady.value = true;
    await tester.pumpWidget(app());
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('New version available'), findsNothing);
    expect(applied, 0);
  });

  testWidgets('a hidden, idle page updates itself; a playing one never does', (tester) async {
    webUpdateReady.value = true;
    await tester.pumpWidget(app());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(applied, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(playing: true));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(applied, 1, reason: 'music must not stop for an update');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('native builds never show it', (tester) async {
    webUpdateReady.value = true;
    await tester.pumpWidget(app(enabled: false));
    expect(find.text('New version available'), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });
}
