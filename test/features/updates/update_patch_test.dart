import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/updates/logic/bspatch.dart';
import 'package:navivibe/features/updates/logic/update_files.dart';

String _sha(List<int> b) => sha256.convert(b).toString();

void main() {
  const dir = 'test/features/updates/fixtures';
  final oldBytes = File('$dir/old.apk').readAsBytesSync();
  final newBytes = File('$dir/new.apk').readAsBytesSync();
  final patch = File('$dir/sample.patch').readAsBytesSync();

  test('bspatch rebuilds the new APK byte for byte from a patch made by CI\'s tool', () {
    final out = bspatch(oldBytes, patch);
    expect(out.length, newBytes.length);
    expect(out, newBytes);
    expect(_sha(out), _sha(newBytes));
    expect(patch.length, lessThan(newBytes.length ~/ 5), reason: 'the patch should be far smaller than the APK');
  });

  test('rejects things that are not a patch', () {
    expect(() => bspatch(oldBytes, Uint8List(10)), throwsA(isA<PatchException>()));
    final wrong = Uint8List.fromList(patch)..[0] = 0x41;
    expect(() => bspatch(oldBytes, wrong), throwsA(isA<PatchException>()));
  });

  test('a patch applied to the wrong base file does not produce the new file', () {
    final other = Uint8List.fromList(oldBytes)..fillRange(1000, 5000, 7);
    final out = bspatch(other, patch);
    expect(_sha(out), isNot(_sha(newBytes)));
  });

  test('a truncated patch throws instead of returning a short file', () {
    final cut = patch.sublist(0, patch.length - 40);
    expect(() => bspatch(oldBytes, Uint8List.fromList(cut)), throwsA(isA<PatchException>()));
  });

  test('applyPatchFiles works on disk in an isolate and reports the sha256', () async {
    final tmp = await Directory.systemTemp.createTemp('navi_patch');
    addTearDown(() => tmp.delete(recursive: true));
    final sha = await applyPatchFiles(
      oldPath: '$dir/old.apk',
      patchPath: '$dir/sample.patch',
      outPath: '${tmp.path}/out.apk',
    );
    expect(File('${tmp.path}/out.apk').readAsBytesSync(), newBytes);
    expect(sha, _sha(newBytes));
    expect(await sha256OfFile(File('${tmp.path}/out.apk')), sha);
  });

  test('larger generated pair (needs python + bsdiff4; skipped otherwise)', () async {
    final tmp = await Directory.systemTemp.createTemp('navi_patch_big');
    addTearDown(() => tmp.delete(recursive: true));
    ProcessResult r;
    try {
      r = await Process.run('python', ['tool/release/make_sample_patch.py', '--out', tmp.path, '--size', '3000000']);
    } on ProcessException {
      markTestSkipped('python not available');
      return;
    }
    if (r.exitCode != 0) {
      markTestSkipped('bsdiff4 not installed');
      return;
    }
    final o = File('${tmp.path}/old.apk').readAsBytesSync();
    final n = File('${tmp.path}/new.apk').readAsBytesSync();
    final p = File('${tmp.path}/sample.patch').readAsBytesSync();
    final out = bspatch(o, p);
    expect(_sha(out), _sha(n));
    expect(p.length, lessThan(n.length ~/ 20));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
