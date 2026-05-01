import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'core/hive_boxes.dart';
import 'core/theme.dart';
import 'widgets/app_scaffold.dart';

import 'providers/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveBoxes.init();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.mymusicplayer.audio',
    androidNotificationChannelName: 'My Music Player',
    // BUG-14: false allows the user to dismiss the notification, which
    // kills the foreground service so the app doesn't persist after swipe-kill.
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: true,
  );
  runApp(const ProviderScope(child: MyMusicPlayerApp()));
}

class MyMusicPlayerApp extends ConsumerWidget {
  const MyMusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
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
