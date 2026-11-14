import 'package:web/web.dart' as web;

/// Key-value storage scoped to the browser tab (sessionStorage, [persistent]
/// false) or the browser profile (localStorage, [persistent] true). Storage can
/// be blocked (private mode, site data off), so every call swallows errors.
class WebStorage {
  const WebStorage({this.persistent = false});
  final bool persistent;

  web.Storage get _store => persistent ? web.window.localStorage : web.window.sessionStorage;

  String? read(String key) {
    try {
      return _store.getItem(key);
    } catch (_) {
      return null;
    }
  }

  void write(String key, String value) {
    try {
      _store.setItem(key, value);
    } catch (_) {}
  }

  void remove(String key) {
    try {
      _store.removeItem(key);
    } catch (_) {}
  }
}
