/// Every external host the app talks to, with its `--dart-define` override, in
/// one place. The user's own Navidrome server is configured at sign-in and is
/// not listed here.
class Endpoints {
  Endpoints._();

  /// Smart Shuffle / stats server. `--dart-define=NAVIVIBE_SHUFFLE_URL=...`
  /// points a build (a local web test, say) at another server.
  static const String shuffle =
      String.fromEnvironment('NAVIVIBE_SHUFFLE_URL', defaultValue: 'https://shuffle.subimusic.me');

  /// Session sync server. `--dart-define=NAVIVIBE_SESSION_URL=...` overrides it;
  /// the websocket URL follows.
  static const String session =
      String.fromEnvironment('NAVIVIBE_SESSION_URL', defaultValue: 'https://session.subimusic.me');

  /// Synced-lyrics lookup (LRCLIB). `--dart-define=NAVIVIBE_LRCLIB_URL=...`.
  static const String lrclibGet =
      String.fromEnvironment('NAVIVIBE_LRCLIB_URL', defaultValue: 'https://lrclib.net/api/get');
}
