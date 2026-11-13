import 'web_env.dart';

/// Not running in a browser.
BrowserInfo? readBrowserInfo() => null;

/// Reloads the page (browser only; a no-op elsewhere).
void reloadPage() {}
