/// Remote control and the "Playing on" sheet at phone size (390×844 @3x).
///
///   flutter test test/goldens/remote_test.dart --update-goldens
@Tags(['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/player/devices_sheet.dart';
import 'package:navivibe/player/remote_view.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/session_sync_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/session_sync_service.dart';
import 'package:navivibe/services/subsonic_service.dart';

import 'golden_fonts.dart';

class _Svc extends Fake implements SessionSyncService {
  @override
  Stream<CommandResult> get resultStream => const Stream.empty();
  @override
  String? get deviceId => 'aaaa1111';
  @override
  String? get deviceName => 'Android phone';
  @override
  Future<void> connect() async {}
}

class _Player extends StateNotifier<PlayerState> implements PlayerNotifier {
  _Player(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class _Settings extends StateNotifier<SettingsState> implements SettingsNotifier {
  _Settings() : super(const SettingsState(serverUrl: 'https://music.example', username: 'u', password: 'p'));
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Subsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

PlayerState _passive() => const PlayerState(
      queue: [],
      currentIndex: 0,
      isPlaying: false,
      shuffleMode: false,
      autoplayMode: false,
      repeatMode: LoopMode.off,
      starredIds: [],
      syncMode: SyncMode.passive,
    );

Widget _app(Widget home, {SyncConnection conn = SyncConnection.online, List<SyncDevice> devices = const [], SyncMode mode = SyncMode.passive}) {
  final tokens = AppThemeTokens.fallback;
  final stamp = DateTime.now().subtract(const Duration(seconds: 30));
  return ProviderScope(
    overrides: [
      sessionSyncServiceProvider.overrideWithValue(_Svc()),
      playerProvider.overrideWith((ref) => _Player(_passive().copyWith(syncMode: mode))),
      settingsProvider.overrideWith((ref) => _Settings()),
      subsonicServiceProvider.overrideWithValue(_Subsonic()),
      syncConnectionProvider.overrideWith((ref) => Stream.value(conn)),
      syncDevicesProvider.overrideWith((ref) => Stream.value(devices)),
      syncPlaybackProvider.overrideWith((ref) => Stream.value(PlaybackState(
            activeDevice: 'bbbb2222',
            activeDeviceName: 'Living room TV',
            trackId: 't1',
            trackTitle: 'Thaniye',
            artist: 'Anirudh Ravichander',
            durationS: 238,
            positionMs: 71000,
            isPlaying: true,
            updatedAt: stamp,
          ))),
    ],
    child: ThemeTokens(
      tokens: tokens,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: AppTheme.build(tokens), home: home),
    ),
  );
}

void main() {
  setUpAll(loadGoldenFonts);

  Future<void> phone(WidgetTester tester, {double height = 844, double width = 390}) async {
    tester.view.physicalSize = Size(width, height) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('remote control while another device plays', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const Scaffold(backgroundColor: Color(0xFF111111), body: SafeArea(child: RemoteControlView()))));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('remote/control.png'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote control with the link down, and at 320 wide', (tester) async {
    await phone(tester, width: 320, height: 640);
    await tester.pumpWidget(_app(
      const Scaffold(backgroundColor: Color(0xFF111111), body: SafeArea(child: RemoteControlView())),
      conn: SyncConnection.offline,
    ));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('remote/control_offline_small.png'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('playing-on sheet with three devices', (tester) async {
    await phone(tester, height: 560);
    await tester.pumpWidget(_app(
      const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: DevicesSheet())),
      devices: const [
        SyncDevice(id: 'aaaa1111', name: 'Android phone', type: SyncDeviceType.phone),
        SyncDevice(id: 'bbbb2222', name: 'Living room TV', type: SyncDeviceType.tv, active: true),
        SyncDevice(id: 'cccc3333', name: 'Windows PC', type: SyncDeviceType.desktop),
      ],
    ));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('remote/devices.png'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('playing-on sheet offline with only this device', (tester) async {
    await phone(tester, height: 420);
    await tester.pumpWidget(_app(
      const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: DevicesSheet())),
      conn: SyncConnection.offline,
      mode: SyncMode.idle,
    ));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('remote/devices_offline.png'));
    expect(tester.takeException(), isNull);
  });
}
