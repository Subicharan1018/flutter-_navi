import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'core/theme.dart';
import 'widgets/app_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.mymusicplayer.audio',
    androidNotificationChannelName: 'My Music Player',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );
  runApp(const ProviderScope(child: MyMusicPlayerApp()));
}

class MyMusicPlayerApp extends StatelessWidget {
  const MyMusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Music Player',
      theme: AppTheme.darkTheme,
      home: const AppScaffold(),
      debugShowCheckedModeBanner: false,
    );
  }
}
