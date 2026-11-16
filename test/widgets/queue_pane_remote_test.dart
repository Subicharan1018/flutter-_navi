// The queue pane on a controller (another of your devices plays): it shows the
// playing device's queue and edits it like a local one, through the session link.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/now_playing_style.dart';
import 'package:navivibe/player/queue_pane.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/remote_queue_provider.dart';
import 'package:navivibe/providers/session_sync_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/session_sync_service.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';

import '../helpers/fake_queue_sync.dart';

Song _s(String id) => Song(id: id, title: 'Title $id', artist: 'Artist', album: 'Album', coverArt: '', duration: 200, track: 1, year: 2024);

/// This device is a remote: its own (paused, stale) queue must never be what the pane edits.
class _PassivePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  final localCalls = <String>[];
  final remote = <(String, int?, String?)>[];
  _PassivePlayer()
      : super(PlayerState(
          queue: [_s('local1'), _s('local2')],
          currentIndex: 0,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: true,
          repeatMode: LoopMode.off,
          starredIds: const [],
          history: [_s('h1')],
          syncMode: SyncMode.passive,
        ));

  @override
  void remoteControl(String action, {int? positionMs, double? volume, int? index, String? trackId, List<String>? queue}) =>
      remote.add((action, index, trackId));

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.isMethod) localCalls.add(i.memberName.toString());
    return i.isMethod ? Future<void>.value() : null;
  }
}

class _FakeSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _FakeSettings() : super(const SettingsState(serverUrl: 'https://x', username: 'u', password: 'p'));
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

  late FakeQueueSync sync;
  late _PassivePlayer player;

  Future<void> pumpPane(WidgetTester tester, {String? locked}) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    sync = FakeQueueSync(PlaybackState(
      activeDevice: 'host',
      queue: const ['a', 'b', 'c', 'd'],
      queueIndex: 1,
      epoch: 1,
      version: 1,
      queueLocked: locked,
    ));
    addTearDown(sync.close);
    player = _PassivePlayer();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        playerProvider.overrideWith((ref) => player),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
        sessionSyncServiceProvider.overrideWithValue(sync),
        remoteSongResolverProvider.overrideWithValue((ids) async => [for (final id in ids) _s(id)]),
      ],
      child: const MaterialApp(home: Scaffold(body: QueuePane(style: NowPlayingStyle.onArtwork, showCurrent: true))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("shows the playing device's queue, with the editing controls", (tester) async {
    await pumpPane(tester);
    expect(find.text('Title c'), findsOneWidget);
    expect(find.text('Title d'), findsOneWidget);
    expect(find.text('Title local2'), findsNothing);                     // not this device's own queue
    expect(find.text('2 songs'), findsOneWidget);
    expect(find.byTooltip('Remove from queue'), findsNWidgets(2));
    expect(find.widgetWithText(TextButton, 'Clear'), findsWidgets);
    expect(find.text('Repeat'), findsNothing);                            // local mode pills hidden
  });

  testWidgets('remove sends queue_remove and the row leaves at once', (tester) async {
    await pumpPane(tester);
    await tester.tap(find.byTooltip('Remove from queue').last);
    await tester.pump();
    expect(sync.sent.single.$1, QueueEditType.remove);
    expect(sync.sent.single.$2, {'index': 3, 'track_id': 'd'});
    expect(find.text('Title d'), findsNothing);
    expect(player.localCalls, isEmpty);                                   // nothing touched the local player
  });

  testWidgets('a refused remove comes back', (tester) async {
    await pumpPane(tester);
    await tester.tap(find.byTooltip('Remove from queue').last);
    await tester.pump();
    sync.answer('cmd-1', ok: false, reason: 'queue_changed');
    await tester.pump();
    expect(find.text('Title d'), findsOneWidget);
  });

  testWidgets('Clear removes the upcoming songs on the playing device', (tester) async {
    await pumpPane(tester);
    // The Playing Next header's Clear (History has its own, above).
    await tester.tap(find.widgetWithText(TextButton, 'Clear').last);
    await tester.pump();
    expect(sync.sent.single.$1, QueueEditType.clearUpcoming);
    expect(find.text('Title c'), findsNothing);
  });

  testWidgets('dragging a row reorders it there', (tester) async {
    await pumpPane(tester);
    final from = tester.getCenter(find.text('Title d'));
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveTo(from - const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveTo(tester.getCenter(find.text('Title c')) - const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 50));
    await g.up();
    await tester.pumpAndSettle();
    expect(sync.sent.single.$1, QueueEditType.move);
    expect(sync.sent.single.$2, {'from': 3, 'to': 2, 'track_id': 'd'});
    expect(
      tester.getCenter(find.text('Title d')).dy < tester.getCenter(find.text('Title c')).dy,
      isTrue,
    );
  });

  testWidgets('a History row dropped into the queue is inserted there', (tester) async {
    await pumpPane(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();
    final from = tester.getCenter(find.text('Title h1'));
    final target = tester.getRect(find.text('Title c')).center;
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await g.moveTo(from + const Offset(0, 20));
    await tester.pump();
    await g.moveTo(target + const Offset(0, 20));
    await tester.pump();
    await g.up();
    await tester.pump();
    expect(sync.sent.single.$1, QueueEditType.insert);
    expect(sync.sent.single.$2, {'track_ids': ['h1'], 'position': 3, 'after_id': 'c'});
    expect(find.text('Title h1'), findsNWidgets(2));                      // History keeps its copy
  });

  testWidgets('tapping a row plays it on the playing device', (tester) async {
    await pumpPane(tester);
    await tester.tap(find.text('Title c'));
    await tester.pump();
    expect(player.remote.single, ('play_track', 2, 'c'));
  });

  testWidgets('a queue that follows a Jam is shown but not editable', (tester) async {
    await pumpPane(tester, locked: 'jam');
    expect(find.text('Title c'), findsOneWidget);
    expect(find.text('Follows the Jam'), findsOneWidget);
    expect(find.byTooltip('Remove from queue'), findsNothing);
    await tester.tap(find.text('Title c'));
    await tester.pump();
    expect(player.remote, isEmpty);
    expect(sync.sent, isEmpty);
  });
}
