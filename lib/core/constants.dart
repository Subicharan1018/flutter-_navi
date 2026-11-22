import 'build_flavor.dart';

class Constants {
  static const String appName = 'NaviVibe';
  // No default server URL — users must configure their own Navidrome server
  // in the Settings screen. Hardcoded server addresses are a security risk (a build may prefill one via dart-define).
  static const String defaultServerUrl = '';

  /// Prefilled on the sign-in screen in non-public builds; the person can change it.
  /// Supplied with `--dart-define=NAVIVIBE_SUGGESTED_URL=...`, so no host lives in source.
  static const String suggestedServerUrl = kPublicBuild ? '' : String.fromEnvironment('NAVIVIBE_SUGGESTED_URL');
  static const String defaultUsername = '';
  static const String defaultClient = 'navivibe';
  static const String apiVersion = '1.16.1';
}
