import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

// =============================================================================
// device_utils.dart — Stable anonymous device identity
//
// Provides a per-device UUID that persists across app sessions.
// Used by ListeningLogService to attribute listening logs without linking to
// any personal identity — purely for aggregate per-device stats.
// =============================================================================

const _kDeviceIdKey = 'device_id';

/// Returns a stable anonymous device ID.
///
/// On first call a cryptographically secure UUID v4 is generated and stored
/// in SharedPreferences. Subsequent calls return the same value.
Future<String> getOrCreateDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_kDeviceIdKey);
  if (existing != null && existing.isNotEmpty) return existing;
  final newId = generateUuid();
  await prefs.setString(_kDeviceIdKey, newId);
  return newId;
}

/// Generates a RFC 4122 v4 (random) UUID using a cryptographically secure
/// random source.
///
/// This is the same algorithm used by [ListeningEventCollector._generateUuid]
/// — extracted here so it can be shared without circular imports.
String generateUuid() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  // Set version 4 bits (bits 12–15 of time_hi_and_version)
  b[6] = (b[6] & 0x0f) | 0x40;
  // Set variant bits (bits 6–7 of clock_seq_hi_and_reserved)
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}
