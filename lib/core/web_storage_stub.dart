/// Key-value storage scoped to the browser tab ([persistent] false) or the
/// browser profile ([persistent] true). Not a browser: stores nothing.
class WebStorage {
  const WebStorage({this.persistent = false});
  final bool persistent;

  String? read(String key) => null;
  void write(String key, String value) {}
  void remove(String key) {}
}
