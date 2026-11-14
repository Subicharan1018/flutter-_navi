import 'web_env.dart';

/// Not running in a browser.
BrowserInfo? readBrowserInfo() => null;

/// Reloads the page (browser only; a no-op elsewhere).
void reloadPage() {}

/// Calls [onReady] once a newer build of the web app is live (browser only).
void onWebUpdateReady(void Function() onReady) {}

/// Switches to the newer build (browser only).
void applyWebUpdate() {}
