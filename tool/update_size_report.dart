// Prints how much smaller an update patch is than the full APK, and proves the
// patch rebuilds the new APK with the app's own Dart patcher.
//
//   dart run tool/update_size_report.dart                     # synthetic sample
//   dart run tool/update_size_report.dart old.apk new.apk     # two real builds
//   dart run tool/update_size_report.dart old.apk new.apk x.patch   # existing patch
//
// Patches are made with the same `bsdiff4` call CI uses (pip install bsdiff4).
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:navivibe/features/updates/logic/bspatch.dart';

String _mb(int b) => '${(b / 1048576).toStringAsFixed(2)} MB';

Future<void> main(List<String> args) async {
  final tmp = await Directory.systemTemp.createTemp('navi_size_report');
  try {
    late String oldPath, newPath, patchPath;
    if (args.length >= 2) {
      oldPath = args[0];
      newPath = args[1];
      patchPath = args.length > 2 ? args[2] : '${tmp.path}/x.patch';
      if (args.length <= 2) {
        final r = await Process.run('python', [
          '-c',
          'import sys,bsdiff4;bsdiff4.file_diff(sys.argv[1],sys.argv[2],sys.argv[3])',
          oldPath,
          newPath,
          patchPath,
        ]);
        if (r.exitCode != 0) {
          stderr.writeln('Could not make a patch (pip install bsdiff4):\n${r.stderr}');
          exit(2);
        }
      }
    } else {
      final r = await Process.run('python', ['tool/release/make_sample_patch.py', '--out', tmp.path, '--size', '8000000']);
      if (r.exitCode != 0) {
        stderr.writeln('Could not build the sample (pip install bsdiff4):\n${r.stderr}');
        exit(2);
      }
      oldPath = '${tmp.path}/old.apk';
      newPath = '${tmp.path}/new.apk';
      patchPath = '${tmp.path}/sample.patch';
    }

    final oldB = File(oldPath).readAsBytesSync();
    final newB = File(newPath).readAsBytesSync();
    final patchB = File(patchPath).readAsBytesSync();

    final sw = Stopwatch()..start();
    final out = bspatch(Uint8List.fromList(oldB), Uint8List.fromList(patchB));
    sw.stop();
    final ok = sha256.convert(out) == sha256.convert(newB);

    print('old APK        ${_mb(oldB.length).padLeft(10)}');
    print('new APK (full) ${_mb(newB.length).padLeft(10)}   <- what a full update downloads');
    print('patch          ${_mb(patchB.length).padLeft(10)}   <- what a delta update downloads');
    print('saving         ${(100 - patchB.length * 100 / newB.length).toStringAsFixed(1).padLeft(9)} %');
    print('applied in ${sw.elapsedMilliseconds} ms (Dart, this machine); result ${ok ? 'matches' : 'DIFFERS FROM'} the new APK');
    print('new sha256 ${sha256.convert(newB)}');
    if (!ok) exit(1);
  } finally {
    await tmp.delete(recursive: true);
  }
}
