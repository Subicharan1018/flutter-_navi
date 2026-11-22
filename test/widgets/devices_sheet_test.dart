// The "Playing on" sheet: who plays, where new music is sent, and moving playback.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/player/devices_sheet.dart';
import 'package:navivibe/providers/play_route.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/session_sync_provider.dart';
import 'package:navivibe/services/session_sync_service.dart';

class _Svc extends Fake implements SessionSyncService {
  @override
  String? get deviceId => 'phone';
  @override
  String? get deviceName => 'OnePlus phone';
  @override
  Future<void> connect() async {}
}

class _Player extends StateNotifier<PlayerState> implements PlayerNotifier {
  final moved = <String>[];
  _Player(SyncMode mode)
      : super(PlayerState(
          queue: const [],
          currentIndex: 0,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: const [],
          syncMode: mode,
        ));

  @override
  Future<void> transferTo(String deviceId) async => moved.add(deviceId);

  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

const _devices = [
  SyncDevice(id: 'phone', name: 'OnePlus phone', type: SyncDeviceType.phone),
  SyncDevice(id: 'pc', name: 'Windows PC', type: SyncDeviceType.desktop, active: true),
  SyncDevice(id: 'tv', name: 'Living room TV', type: SyncDeviceType.tv),
];

void main() {
  late _Player player;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, {SyncMode mode = SyncMode.passive, List<SyncDevice> devices = _devices}) async {
    tester.view.physicalSize = const Size(390, 800) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    player = _Player(mode);
    final tokens = AppThemeTokens.fallback;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionSyncServiceProvider.overrideWithValue(_Svc()),
        playerProvider.overrideWith((ref) => player),
        syncConnectionProvider.overrideWith((ref) => Stream.value(SyncConnection.online)),
        syncDevicesProvider.overrideWith((ref) => Stream.value(devices)),
      ],
      child: ThemeTokens(
        tokens: tokens,
        child: MaterialApp(theme: AppTheme.build(tokens), home: const Scaffold(body: SingleChildScrollView(child: DevicesSheet()))),
      ),
    ));
    await tester.pump();
    await tester.pump();
    container = ProviderScope.containerOf(tester.element(find.byType(DevicesSheet)));
  }

  testWidgets('lists every device and says which one plays', (tester) async {
    await pump(tester);
    expect(find.text('Windows PC'), findsNWidgets(2)); // its "send to" chip and its row
    expect(find.text('Living room TV'), findsNWidgets(2));
    expect(find.textContaining('Host · playing now'), findsOneWidget);
    expect(find.text('Host'), findsOneWidget);
  });

  testWidgets('new music goes to the playing device unless another is picked', (tester) async {
    await pump(tester);
    expect(find.text('Send new music to'), findsOneWidget);
    expect(container.read(playTargetProvider), isNull); // nothing picked: the playing device

    // The TV chip (the chips sit above the list, so the chip is the first "Living room TV").
    await tester.tap(find.text('Living room TV').first);
    await tester.pump();
    expect(container.read(playTargetProvider), 'tv');
    expect(player.moved, isEmpty); // choosing where new music goes does not move what plays now

    await tester.tap(find.text('This device'));
    await tester.pump();
    expect(container.read(playTargetProvider), 'phone');
  });

  testWidgets('tapping a device that is not playing moves playback to it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Living room TV').last); // the row, below the chips
    await tester.pump();
    expect(player.moved, ['tv']);
  });

  testWidgets('the device that plays is not a button, and this device can take playback', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Windows PC').last); // its row
    await tester.pump();
    expect(player.moved, isEmpty);
    await tester.tap(find.textContaining('Tap to play here'));
    await tester.pump();
    expect(player.moved, ['phone']);
  });

  testWidgets('with only this device there is nothing to send to', (tester) async {
    await pump(tester, mode: SyncMode.idle, devices: const [SyncDevice(id: 'phone', name: 'OnePlus phone', type: SyncDeviceType.phone)]);
    expect(find.text('Send new music to'), findsNothing);
    expect(find.textContaining('Open NaviVibe on another device'), findsOneWidget);
  });
}
