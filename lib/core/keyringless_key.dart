import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

/// The credentials-box key for a Linux desktop without a keyring: a random key
/// in a file only this user can read (mode 600). Weaker than a keyring (any
/// program run by this user can read it), the same protection as ssh keys
/// without a passphrase.
Future<List<int>> readOrCreateKeyFile(Directory dir) async {
  await dir.create(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}auth.key');
  if (await file.exists()) {
    try {
      final key = base64Url.decode((await file.readAsString()).trim());
      if (key.length == 32) return key;
    } on FormatException {
      // Damaged: replaced below. The user signs in again.
    }
  }
  await file.create();
  // Restrict first, then write: the key is never readable by others.
  if (!Platform.isWindows) await Process.run('chmod', ['600', file.path]);
  final key = Hive.generateSecureKey();
  await file.writeAsString(base64Url.encode(key), flush: true);
  return key;
}
