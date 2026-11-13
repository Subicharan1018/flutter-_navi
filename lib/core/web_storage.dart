// =============================================================================
// web_storage.dart — the browser's sessionStorage / localStorage, for the web
// sign-in only. Native builds get a no-op stub (they keep credentials in the
// encrypted Hive box as before).
// =============================================================================

export 'web_storage_stub.dart' if (dart.library.js_interop) 'web_storage_web.dart';
