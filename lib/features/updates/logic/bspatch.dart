import 'dart:typed_data';

import 'package:archive/archive.dart' show BZip2Decoder;

/// Raised when a patch is damaged or does not belong to the file it is applied to.
class PatchException implements Exception {
  final String message;
  const PatchException(this.message);
  @override
  String toString() => 'PatchException: $message';
}

/// Applies a BSDIFF40 patch (the format of Colin Percival's `bsdiff` and of the
/// Python `bsdiff4` package CI uses) to [oldBytes] and returns the new file.
///
/// Pure Dart so it runs in an isolate on every platform without native code.
Uint8List bspatch(Uint8List oldBytes, Uint8List patch) {
  if (patch.length < 32 || String.fromCharCodes(patch.sublist(0, 8)) != 'BSDIFF40') {
    throw const PatchException('Not a BSDIFF40 patch');
  }
  final head = ByteData.sublistView(patch);
  final ctrlLen = _offtin(head, 8);
  final diffLen = _offtin(head, 16);
  final newSize = _offtin(head, 24);
  if (ctrlLen < 0 || diffLen < 0 || newSize < 0 || 32 + ctrlLen + diffLen > patch.length) {
    throw const PatchException('Corrupt patch header');
  }

  final decoder = BZip2Decoder();
  final ctrl = _decode(decoder, patch, 32, 32 + ctrlLen);
  final diff = _decode(decoder, patch, 32 + ctrlLen, 32 + ctrlLen + diffLen);
  final extra = _decode(decoder, patch, 32 + ctrlLen + diffLen, patch.length);
  final ctrlView = ByteData.sublistView(ctrl);

  final out = Uint8List(newSize);
  var oldPos = 0, newPos = 0, diffPos = 0, extraPos = 0;
  for (var c = 0; c + 24 <= ctrl.length; c += 24) {
    final addLen = _offtin(ctrlView, c);
    final copyLen = _offtin(ctrlView, c + 8);
    final seek = _offtin(ctrlView, c + 16);

    if (addLen < 0 || copyLen < 0 || newPos + addLen > newSize || diffPos + addLen > diff.length) {
      throw const PatchException('Corrupt patch (add block)');
    }
    for (var i = 0; i < addLen; i++) {
      final o = oldPos + i;
      out[newPos + i] = diff[diffPos + i] + (o >= 0 && o < oldBytes.length ? oldBytes[o] : 0);
    }
    newPos += addLen;
    diffPos += addLen;
    oldPos += addLen;

    if (newPos + copyLen > newSize || extraPos + copyLen > extra.length) {
      throw const PatchException('Corrupt patch (copy block)');
    }
    out.setRange(newPos, newPos + copyLen, extra, extraPos);
    newPos += copyLen;
    extraPos += copyLen;
    oldPos += seek;
  }
  if (newPos != newSize) throw const PatchException('Patch produced the wrong length');
  return out;
}

Uint8List _decode(BZip2Decoder d, Uint8List patch, int start, int end) {
  if (end == start) return Uint8List(0);
  try {
    return d.decodeBytes(Uint8List.sublistView(patch, start, end));
  } catch (e) {
    throw PatchException('Cannot decompress patch: $e');
  }
}

/// bsdiff's sign-magnitude little-endian 64-bit integer.
int _offtin(ByteData d, int at) {
  var y = d.getUint32(at + 4, Endian.little);
  final negative = (y & 0x80000000) != 0;
  y &= 0x7fffffff;
  final v = (y * 0x100000000) + d.getUint32(at, Endian.little);
  return negative ? -v : v;
}
