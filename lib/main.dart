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
import 'fluid_background.dart';
import 'dart:async';
import 'providers/settings_provider.dart';
import 'offline_service.dart';
import 'services/navi_audio_handler.dart';
import 'services/subsonic_service.dart';
import 'services/replay_gain_service.dart';
import 'providers/player_provider.dart';

// ---------------------------------------------------------------------------
// globalAudioHandler — the single NaviAudioHandler instance shared across
// the entire app.  Initialised before runApp() so providers can read it.
// ---------------------------------------------------------------------------
late final NaviAudioHandler globalAudioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  // window_manager must be initialized before the Flutter window is shown so
  // that size/title changes take effect on the very first frame.
  if (PlatformUtils.supportsWindowManager) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title:           'NaviVibe',
      size:            Size(1280, 800),
      minimumSize:     Size(900, 600),
      center:          true,
      backgroundColor: Colors.transparent,
      titleBarStyle:   TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final container = ProviderContainer();

  // ── Audio service / MPRIS initialisation ──────────────────────────────────
  // Initialisation order matters for MPRIS: AudioService.init() wraps the
  // handler with a D-Bus proxy BEFORE the handler is returned.  Constructing
  // NaviAudioHandler outside of the builder would bypass the proxy and leave
  // media controls silently unresponsive.
  //
  // Linux  → AudioService with MPRIS platform interface
  // Mobile / macOS → AudioService with OS notification controls
  // Other  → raw NaviAudioHandler (no OS integration)

  // ── MPRIS registration (Linux only) ──────────────────────────────────────
  // AudioServiceMpris.registerWith() sets AudioServicePlatform.instance to
  // the D-Bus MPRIS implementation BEFORE AudioService.init() wraps it.
  // This is a pure Dart platform registration — no C++ plugin entry needed.
  if (PlatformUtils.isLinux) {
    AudioServiceMpris.registerWith();
  }

  // ── AudioService init ──────────────────────────────────────────────────────
  // Single init path for all platforms — the platform implementation registered
  // above determines whether MPRIS / Android notifications / nothing is used.
  try {
    globalAudioHandler = await AudioService.init<NaviAudioHandler>(
      builder: () => NaviAudioHandler(
        container.read(subsonicServiceProvider),
        replayGainService: container.read(replayGainProvider),
      ),
      config: const AudioServiceConfig(
        // Used as D-Bus service name suffix on Linux (MPRIS), notification
        // channel ID on Android.
        androidNotificationChannelId:   'com.navivibe.audio',
        androidNotificationChannelName: 'NaviVibe',
        androidNotificationOngoing:     false,
        androidStopForegroundOnPause:   false,
      ),
    );
  } catch (e, st) {
    // D-Bus session unavailable (headless CI / Wayland without XDG_RUNTIME_DIR).
    // Fall back to a raw handler — audio plays, MPRIS controls are absent.
    debugPrint('⚠️  AudioService.init failed ($e)\n$st');
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