import 'dart:io' show Platform;
import 'utils/user_activity.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/hive_boxes.dart';
import 'features/local_library/logic/local_library_providers.dart' show localLibraryBootstrapProvider;
import 'core/motion.dart';
import 'core/theme.dart';
import 'utils/platform_utils.dart';
import 'services/desktop_tray.dart';
import 'services/window_manager_service.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/shell/title_bar.dart';
import 'widgets/shell/tv_frame.dart';
import 'features/pairing/ui/tv_pair_screen.dart';
import 'screens/login_screen.dart';
import 'player/artwork.dart';
import 'player/artwork_field.dart';
import 'dart:async';
import 'providers/settings_provider.dart';
import 'offline_service.dart';
import 'services/navi_audio_handler.dart';
import 'services/android_integration.dart';
import 'services/auto/browse_tree.dart' show CarStyle;
import 'core/crash_log.dart';
import 'providers/player_provider.dart';

// ---------------------------------------------------------------------------
// globalAudioHandler — the single NaviAudioHandler instance shared across
// the entire app.  Initialised before runApp() so providers can read it.
// ---------------------------------------------------------------------------
late final NaviAudioHandler globalAudioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  UserActivity.install();
  CrashLog.install();

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
  await PlatformUtils.detectTelevision();
  // A TV remote is always "keys": without this the focus ring vanishes whenever
  // the system reports a non-key input (closing the on-screen keyboard, say).
  if (PlatformUtils.isTv) {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  }

  // BUG-FIX-2: Must initialize OfflineService before runApp() so that
  // DownloadStateNotifier.build() finds _prefs non-null on its very first
  // access.  Without this await, _prefs is null on cold start and
  // getDownloadedSongIds() returns [] — making all downloaded badges vanish.
  try {
    await OfflineService().initialize();
  } catch (e, st) {
    // Offline songs just won't show as downloaded; the app must still open.
    debugPrint('⚠️  OfflineService.initialize failed ($e)\n$st');
    CrashLog.record(e, st);
  }

  // ── Media kit: required on Linux / Windows for just_audio playback ─────────
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
    JustAudioMediaKit.ensureInitialized();
  }

  // ── Desktop window setup ───────────────────────────────────────────────────
  if (PlatformUtils.supportsWindowManager) {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      title: 'NaviVibe',
      size: Size(1280, 800),
      minimumSize: WindowManagerService.minimumSize,
      center: true,
      backgroundColor: Colors.transparent,
      // Windows draws its own title bar (NaviTitleBar) so the chrome matches.
      titleBarStyle: NaviTitleBar.enabled ? TitleBarStyle.hidden : TitleBarStyle.normal,
      windowButtonVisibility: !NaviTitleBar.enabled,
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
        transcodingService: container.read(transcodingProvider),
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.navivibe.audio',
        androidNotificationChannelName: 'NaviVibe',
        // ongoing=true: notification cannot be swiped away, preventing Android
        // from instantly killing the foreground service via notification dismiss.
        // audio_service requires: if ongoing=true then stopForegroundOnPause=true.
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        // Lets the car lay out folders as grids / lists (see CarStyle).
        androidBrowsableRootExtras: CarStyle.rootExtras,
      ),
    );
  } catch (e, st) {
    debugPrint('⚠️  AudioService.init failed ($e)\n$st');
    CrashLog.record(e, st);
    globalAudioHandler = NaviAudioHandler(
      container.read(subsonicServiceProvider),
      transcodingService: container.read(transcodingProvider),
    );
  }

  // Car / browse-tree playback goes through the same path as the UI.
  _wireCarControls(container, globalAudioHandler);
  AndroidIntegration.init(globalAudioHandler);

  // Songs from Settings > Local music: load the file index, match them to the
  // server library, and rescan quietly a few seconds after launch.
  container.read(localLibraryBootstrapProvider);

  // Compile the Now Playing artwork-field shader before it's first shown.
  unawaited(ArtworkField.precache());

  if (DesktopTray.supported) {
    final player = container.read(playerProvider.notifier);
    unawaited(DesktopTray.instance.init(PlaybackTransport(
      playPause: () {
        UserActivity.mark();
        player.togglePlay();
      },
      next: () {
        UserActivity.mark();
        player.playNext();
      },
      previous: () {
        UserActivity.mark();
        player.playPrev();
      },
      isPlaying: () => container.read(playerProvider).isPlaying,
    )));
    container.listen(playerProvider.select((s) => s.isPlaying), (_, _) => DesktopTray.instance.refreshMenu());
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyMusicPlayerApp(),
    ),
  );
}

/// Car and notification controls act through [PlayerNotifier], the same path
/// as the UI, and the handler's icons follow the player's state.
void _wireCarControls(ProviderContainer container, NaviAudioHandler handler) {
  PlayerNotifier player() => container.read(playerProvider.notifier);

  handler.onPlayRequest = (r) => r.shuffle
      ? player().playPlaylist(r.songs, shuffle: true, playlistName: r.name)
      : player().setQueue(r.songs, r.startIndex, playlistName: r.name);

  handler.onCarAction = (action) async {
    final p = player();
    switch (action) {
      case 'like':
        final id = container.read(playerProvider).currentSong?.id;
        if (id != null) await p.toggleStar(id);
      case 'shuffle':
        await p.toggleShuffle();
      case 'repeat':
        await p.cycleRepeat();
    }
  };

  handler.carState = () {
    final s = container.read(playerProvider);
    final song = s.currentSong;
    return (
      liked: song != null && (song.starred || s.starredIds.contains(song.id)),
      shuffle: s.shuffleMode,
      repeat: s.repeatMode,
    );
  };

  // Keep the car's heart / shuffle / repeat icons in step with the app.
  container.listen(
    playerProvider.select((s) => (s.shuffleMode, s.repeatMode, s.starredIds.length, s.currentSong?.id)),
    (_, _) => handler.refreshControls(),
  );
}

class MyMusicPlayerApp extends ConsumerWidget {
  const MyMusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One theme, tinted by the album that's playing.
    final palette = ref.watch(albumPaletteProvider);
    final tokens = AppThemeTokens.fromPalette(palette);
    final motion = ref.watch(settingsProvider.select((s) => s.motionLevel));

    // Reactively toggle image cache boundaries
    final cacheSettings = ref.watch(cacheSettingsNotifierProvider);
    if (!cacheSettings.imageCacheEnabled) {
      PaintingBinding.instance.imageCache.maximumSizeBytes = 0;
      PaintingBinding.instance.imageCache.maximumSize = 0;
      PaintingBinding.instance.imageCache.clear();
    } else {
      PaintingBinding.instance.imageCache.maximumSizeBytes = 25 * 1024 * 1024;
      PaintingBinding.instance.imageCache.maximumSize = 60;
    }

    // Route: show LoginScreen on first launch, AppScaffold if already logged in.
    final home = isLoggedIn()
        ? const AppScaffold()
        : PlatformUtils.isTv
            ? const TvPairScreen()
            : const LoginScreen();

    return ThemeTokens(
      tokens: tokens,
      child: MaterialApp(
        title: 'NaviVibe',
        theme: AppTheme.build(tokens),
        scrollBehavior: const NaviScrollBehavior(),
        themeAnimationDuration: const Duration(milliseconds: 450),
        themeAnimationCurve: Curves.easeOutCubic,
        builder: (context, child) => MotionScope.resolve(
          level: motion,
          systemReduced: MediaQuery.disableAnimationsOf(context),
          // TV: overscan margin and larger type. Windows: our own title bar.
          child: TvFrame(
            child: NaviTitleBar.enabled
                ? Column(children: [const NaviTitleBar(), Expanded(child: child!)])
                : child!,
          ),
        ),
        home: home,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
