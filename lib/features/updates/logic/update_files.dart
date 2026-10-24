import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'bspatch.dart';

/// Lowercase hex SHA-256 of a file, streamed so a 25 MB APK is never held twice.
Future<String> sha256OfFile(File f) async {
  final digest = await sha256.bind(f.openRead()).first;
  return digest.toString();
}

/// Builds the new APK from the installed one plus a patch, entirely off the UI
/// isolate, and writes it to [outPath]. Returns the SHA-256 of the result so
/// the caller can compare it with the manifest.
Future<String> applyPatchFiles({
  required String oldPath,
  required String patchPath,
  required String outPath,
}) {
  return Isolate.run(() {
    final old = File(oldPath).readAsBytesSync();
    final patch = File(patchPath).readAsBytesSync();
    final out = bspatch(Uint8List.fromList(old), Uint8List.fromList(patch));
    File(outPath).writeAsBytesSync(out, flush: true);
    return sha256.convert(out).toString();
  });
}
