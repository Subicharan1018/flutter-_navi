import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'core/hive_boxes.dart';
import 'core/theme.dart';
import 'widgets/app_scaffold.dart';
import 'fluid_background.dart';
import 'dart:async';
import 'providers/settings_provider.dart';
import 'offline_service.dart';
import 'services/navi_audio_handler.dart';
import 'services/subsonic_service.dart';
import 'services/replay_gain_service.dart';
import 'providers/player_provider.dart';
import 'services/subsonic_service.dart';
import 'services/replay_gain_service.dart';
import 'providers/player_provider.dart';

late final NaviAudioHandler globalAudioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveBoxes.init();

  // BUG-FIX-2: Must initialize OfflineService before runApp() so that
  // DownloadStateNotifier.build() finds _prefs non-null on its very first
  // access.  Without this await, _prefs is null on cold start and
  // getDownloadedSongIds() returns [] — making all downloaded badges vanish.
  await OfflineService().initialize();

  if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
    JustAudioMediaKit.ensureInitialized();
  }

  final container = ProviderContainer();

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    globalAudioHandler = await AudioService.init<NaviAudioHandler>(
      builder: () => NaviAudioHandler(
        container.read(subsonicServiceProvider),
        replayGainService: container.read(replayGainProvider),
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.mymusicplayer.audio',
        androidNotificationChannelName: 'My Music Player',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
  } else {
    globalAudioHandler = NaviAudioHandler(
      container.read(subsonicServiceProvider),
      replayGainService: container.read(replayGainProvider),
    );
  }

  // PERF-15: Pre-load the fluid background shader so NowPlayingScreen
  // background is ready on first frame (prevents theme-switch flicker).
  unawaited(FluidShaderLoader.instance.load());

  runApp(UncontrolledProviderScope(
    container: container,
    child: const MyMusicPlayerApp(),
  ));
}

class MyMusicPlayerApp extends ConsumerWidget {
  const MyMusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode   = ref.watch(themeModeProvider);
    final tokens = ThemeVariants.of(mode);

    return ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        title: 'NaviVibe',
        theme: AppTheme.buildTheme(mode),
        home: const AppScaffold(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}