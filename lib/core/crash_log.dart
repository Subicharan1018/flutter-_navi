import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps the last uncaught error on the device so it can be shown in
/// Settings > About when the app "closes unexpectedly" on someone's phone.
abstract final class CrashLog {
  static const _fileName = 'last_error.txt';
  static const _maxChars = 4000;

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  /// Chains onto the existing handlers; never throws.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack);
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      return true; // handled: don't take the process down for a stray async error
    };
  }

  static Future<void> record(Object error, StackTrace? stack) async {
    try {
      final file = await _file();
      if (file == null) return;
      var text = '${DateTime.now().toIso8601String()}\n$error\n${stack ?? ''}';
      if (text.length > _maxChars) text = text.substring(0, _maxChars);
      await file.writeAsString(text);
    } catch (_) {
      // Logging must never be the thing that crashes.
    }
  }

  static Future<String?> read() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return null;
      final text = await file.readAsString();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _file();
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }
}
