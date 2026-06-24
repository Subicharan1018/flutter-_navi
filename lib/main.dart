import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/hive_boxes.dart';
import 'core/theme.dart';
import 'utils/platform_utils.dart';
import 'widgets/app_scaffold.dart';
import 'screens/login_screen.dart';
import 'fluid_background.dart';
import 'dart:async';
import 'providers/settings_provider.dart';
import 'offline_service.dart';
import 'services/navi_audio_handler.dart';

// ---------------------------------------------------------------------------
// globalAudioHandler — the single NaviAudioHandler instance shared across
// the entire app.  Initialised before runApp() so providers can read it.
// ---------------------------------------------------------------------------
late final NaviAudioHandler globalAudioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // MEM-OPT: Reduced from 40 MB / 100 items. Flutter's image cache holds
  // decoded RGBA bitmaps. At 60 items × ~100 KB average = ~6 MB retained.
  // 25 MB is the hard ceiling before eviction starts.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 25 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 60;

  // MEM-OPT: Configure CachedNetworkImage's separate cache manager.
  // Without this, it uses DefaultCacheManager which has no object count limit
  // and can accumulate hundreds of decoded images during a long listening session.
  // Note: flutter_cache_manager's DefaultCacheManager is already transitive.

  await HiveBoxes.init();

  // BUG-FIX-2: Must initialize OfflineService before runApp() so that
  // DownloadStateNotifier.build() finds _prefs non-null on its very first
  // access.  Without this await, _prefs is null on cold start and
  // getDownloadedSongIds() returns [] — making all downloaded badges vanish.
  await OfflineService().initialize();

  // ── Media kit: required on Linux / Windows for just_audio playback ─────────
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
    JustAudioMediaKit.ensureInitialized();
  }

  // ── Desktop window setup ───────────────────────────────────────────────────
  if (PlatformUtils.supportsWindowManager) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: 'NaviVibe',
      size: Size(1280, 800),
      minimumSize: Size(900, 600),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final container = ProviderContainer();

  // ── MPRIS registration (Linux only) ──────────────────────────────────────
  if (PlatformUtils.isLinux) {
    AudioServiceMpris.registerWith();
  }

  // ── AudioService init ──────────────────────────────────────────────────────
  try {
    globalAudioHandler = await AudioService.init<NaviAudioHandler>(
      builder: () => NaviAudioHandler(
        container.read(subsonicServiceProvider),
        replayGainService: container.read(replayGainProvider),
        transcodingService: container.read(transcodingProvider),
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.navivibe.audio',
        androidNotificationChannelName: 'NaviVibe',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e, st) {
    debugPrint('⚠️  AudioService.init failed ($e)\n$st');
    globalAudioHandler = NaviAudioHandler(
      container.read(subsonicServiceProvider),
      replayGainService: container.read(replayGainProvider),
      transcodingService: container.read(transcodingProvider),
    );
  }

  // PERF-15: Pre-load the fluid background shader.
  unawaited(FluidShaderLoader.instance.load());

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyMusicPlayerApp(),
    ),
  );
}

class MyMusicPlayerApp extends ConsumerWidget {
  const MyMusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final tokens = ThemeVariants.of(mode);

    // Route: show LoginScreen on first launch, AppScaffold if already logged in.
    final home = isLoggedIn() ? const AppScaffold() : const LoginScreen();

    return ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        title: 'NaviVibe',
        theme: AppTheme.buildTheme(mode),
        home: home,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
