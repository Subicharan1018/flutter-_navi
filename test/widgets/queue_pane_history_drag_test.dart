import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/now_playing_style.dart';
import 'package:navivibe/player/queue_pane.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';

Song _s(String id) => Song(
  id: id,
  title: 'Title $id',
  artist: 'Artist',
  album: 'Album',
  coverArt: '',
  duration: 200,
  track: 1,
  year: 2024,
);

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  final inserts = <(List<Song>, int?)>[];
  _FakePlayer()
    : super(
        PlayerState(
          queue: [_s('q0'), _s('q1'), _s('q2')],
          currentIndex: 0,
          isPlaying: true,
          shuffleMode: false,
          autoplayMode: true,
          repeatMode: LoopMode.off,
          starredIds: const [],
          history: [_s('h1'), _s('h2')],
          syncMode: SyncMode.activeHere,
        ),
      );

  @override
  Future<void> insertAllNext(List<Song> songs, {int? atIndex}) async {
    inserts.add((songs, atIndex));
    // Mirror the real notifier so the pane re-renders with the copy in place.
    final q = [...state.queue]..insertAll(atIndex ?? 1, songs);
    state = state.copyWith(queue: q);
  }

  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class _FakeSettings extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  _FakeSettings()
    : super(const SettingsState(serverUrl: 'https://x', username: 'u', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

void main() {
  setUp(() => PlatformUtils.debugDesktopOverride = true);
  tearDown(() => PlatformUtils.debugDesktopOverride = null);

  testWidgets('dropping a History row inserts a copy; History is unchanged', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = _FakePlayer();
    final overrides = <Override>[
      playerProvider.overrideWith((ref) => fake),
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(
            body: QueuePane(style: NowPlayingStyle.onArtwork),
          ),
        ),
      ),
    );
    await tester.pump();
    // History sits above the anchor: scroll up so both lists are on screen.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();

    final from = tester.getCenter(find.text('Title h1'));
    // Drop on the lower half of the first Up Next row ("q1") → after it.
    final target = tester.getRect(find.text('Title q1')).center;

    final g = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await g.moveTo(from + const Offset(0, 20));
    await tester.pump();
    await g.moveTo(target + const Offset(0, 20));
    await tester.pump();
    expect(find.byKey(const ValueKey('queue_drop_line')), findsOneWidget);
    await g.up();
    await tester.pump();

    expect(fake.inserts.length, 1);
    expect(fake.inserts.single.$1.single.id, 'h1');
    expect(fake.inserts.single.$2, 2); // q1 sits at queue index 1 → after it
    expect(fake.state.queue.map((s) => s.id), ['q0', 'q1', 'h1', 'q2']);
    expect(fake.state.history.map((s) => s.id), ['h1', 'h2']);
    expect(find.byKey(const ValueKey('queue_drop_line')), findsNothing);
  });
}
