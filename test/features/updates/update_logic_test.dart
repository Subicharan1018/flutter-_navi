import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/updates/data/update_manifest.dart';
import 'package:navivibe/features/updates/logic/update_service.dart';
import 'package:navivibe/features/updates/logic/update_source.dart';

UpdateManifest _manifest({int build = 120, List<Map<String, Object?>> patches = const [], String assetBase = 'https://example.test/rel/'}) =>
    UpdateManifest.fromJson({
      'version': '1.0.0',
      'build': build,
      'notes': '- Faster search\n- Fixes',
      'assetBase': assetBase,
      'android': {
        'abis': {
          'arm64-v8a': {'name': 'NaviVibe-arm64-v8a.apk', 'size': 25000000, 'sha256': 'aa', 'patches': patches},
        },
      },
    });

Map<String, Object?> _patch(int from, String fromSha, int size) =>
    {'name': 'p$from.patch', 'size': size, 'sha256': 'bb', 'fromBuild': from, 'fromSha256': fromSha};

class _FakeNative extends UpdateNative {
  final String apk;
  const _FakeNative(this.apk);
  @override
  Future<InstalledApp?> installedApp() async => InstalledApp(baseApk: apk, abis: const ['arm64-v8a'], versionCode: 2118);
  @override
  Future<bool> install(String apkPath) async => true;
}

void main() {
  group('planAndroidUpdate', () {
    test('nothing to do when already on the newest build', () {
      expect(planAndroidUpdate(_manifest(), installedBuild: 120, abis: ['arm64-v8a']), isNull);
    });

    test('prefers the patch cut from exactly the installed APK', () {
      final m = _manifest(patches: [_patch(118, 'abc', 3000000), _patch(117, 'zzz', 4000000)]);
      final plan = planAndroidUpdate(m, installedBuild: 118, abis: ['arm64-v8a'], installedSha256: 'ABC')!;
      expect(plan.isDelta, isTrue);
      expect(plan.downloadSize, 3000000);
    });

    test('full APK when the installed file is not one a patch was made from', () {
      final m = _manifest(patches: [_patch(118, 'abc', 3000000)]);
      final plan = planAndroidUpdate(m, installedBuild: 118, abis: ['arm64-v8a'], installedSha256: 'other')!;
      expect(plan.isDelta, isFalse);
      expect(plan.downloadSize, 25000000);
    });

    test('full APK when far behind, even if a matching patch exists', () {
      final m = _manifest(build: 140, patches: [_patch(118, 'abc', 3000000)]);
      final plan = planAndroidUpdate(m, installedBuild: 118, abis: ['arm64-v8a'], installedSha256: 'abc')!;
      expect(plan.isDelta, isFalse);
    });

    test('picks the first ABI the device supports and skips unknown ones', () {
      final plan = planAndroidUpdate(_manifest(), installedBuild: 100, abis: ['riscv64', 'arm64-v8a'])!;
      expect(plan.full.name, 'NaviVibe-arm64-v8a.apk');
      expect(planAndroidUpdate(_manifest(), installedBuild: 100, abis: ['mips']), isNull);
    });
  });

  group('UpdateSource', () {
    test('empty means off', () => expect(UpdateSource.parse('  '), isNull));

    test('github shorthand and URL forms', () {
      for (final s in ['github:me/navi', 'https://github.com/me/navi', 'https://github.com/me/navi.git']) {
        final src = UpdateSource.parse(s, token: ' t ')!;
        expect(src.isGithub, isTrue, reason: s);
        expect('${src.owner}/${src.repo}', 'me/navi');
        expect(src.token, 't');
      }
    });

    test('direct manifest URLs; junk is rejected', () {
      final src = UpdateSource.parse('https://example.test/rel/latest.json')!;
      expect(src.isGithub, isFalse);
      expect(UpdateSource.parse('ftp://x/y'), isNull);
      expect(UpdateSource.parse('not a url'), isNull);
    });

    test('asset URLs come from the manifest base or sit next to latest.json; token stays on its host', () {
      final m = _manifest();
      final file = m.abis['arm64-v8a']!.full;
      final withBase = UpdateSource.parse('https://example.test/x/latest.json', token: 'tok')!;
      final t1 = withBase.targetFor(file, m, const {});
      expect(t1.url.toString(), 'https://example.test/rel/NaviVibe-arm64-v8a.apk');
      expect(t1.headers['Authorization'], 'Bearer tok');

      final otherHost = UpdateSource.parse('https://feed.test/latest.json', token: 'tok')!;
      expect(otherHost.targetFor(file, m, const {}).headers.containsKey('Authorization'), isFalse);

      final bare = UpdateManifest.fromJson({
        'version': '1', 'build': 5,
        'android': {'abis': {'arm64-v8a': {'name': 'a b.apk', 'size': 1, 'sha256': 'x'}}},
      });
      final t2 = UpdateSource.parse('https://example.test/x/latest.json')!
          .targetFor(bare.abis['arm64-v8a']!.full, bare, const {});
      expect(t2.url.toString(), 'https://example.test/x/a%20b.apk');
    });

    test('GitHub assets resolve through the API url', () {
      final m = _manifest();
      final src = UpdateSource.parse('github:me/navi', token: 'tok')!;
      final t = src.targetFor(m.abis['arm64-v8a']!.full, m, {'NaviVibe-arm64-v8a.apk': 'https://api.github.com/a/1'});
      expect(t.url.path, '/a/1');
      expect(t.headers['Accept'], 'application/octet-stream');
      expect(() => src.targetFor(m.abis['arm64-v8a']!.full, m, const {}), throwsStateError);
    });
  });

  group('UpdateService downloads', () {
    late HttpServer server;
    late Directory tmp;
    late Uint8List payload;
    var rangeRequests = 0;
    var serveRange = true;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('navi_dl');
      payload = Uint8List.fromList(List.generate(300000, (i) => (i * 31 + 7) & 0xff));
      rangeRequests = 0;
      serveRange = true;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final range = req.headers.value('range');
        if (range != null && serveRange) {
          rangeRequests++;
          final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
          req.response.statusCode = 206;
          req.response.add(payload.sublist(from));
        } else {
          req.response.add(payload);
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await tmp.delete(recursive: true);
    });

    UpdateFile fileFor(Uint8List b, {String? sha}) =>
        UpdateFile(name: 'f.bin', size: b.length, sha256: sha ?? sha256.convert(b).toString());

    UpdateService svc() => UpdateService(dio: Dio(), stagingDir: () async => tmp);
    DownloadTarget target() => DownloadTarget(Uri.parse('http://127.0.0.1:${server.port}/f.bin'), const {});

    test('downloads and verifies', () async {
      final f = await svc().download(target(), fileFor(payload), File('${tmp.path}/f.bin'));
      expect(f.readAsBytesSync(), payload);
    });

    test('resumes a partial file with a Range request', () async {
      File('${tmp.path}/f.bin.part').writeAsBytesSync(payload.sublist(0, 120000));
      final f = await svc().download(target(), fileFor(payload), File('${tmp.path}/f.bin'));
      expect(f.readAsBytesSync(), payload);
      expect(rangeRequests, 1);
    });

    test('restarts cleanly when the server ignores Range', () async {
      serveRange = false;
      File('${tmp.path}/f.bin.part').writeAsBytesSync(payload.sublist(0, 1000));
      final f = await svc().download(target(), fileFor(payload), File('${tmp.path}/f.bin'));
      expect(f.readAsBytesSync(), payload);
    });

    test('a wrong checksum throws and leaves nothing behind', () async {
      await expectLater(
        svc().download(target(), fileFor(payload, sha: '00' * 32), File('${tmp.path}/f.bin')),
        throwsA(isA<UpdateException>()),
      );
      expect(File('${tmp.path}/f.bin').existsSync(), isFalse);
      expect(File('${tmp.path}/f.bin.part').existsSync(), isFalse);
    });

    test('a corrupt patch falls back to the full APK', () async {
      final base = File('${tmp.path}/base.apk')..writeAsBytesSync(List.filled(100, 1));
      final bad = Uint8List.fromList(List.filled(80, 9)); // not a BSDIFF40 patch
      final full = fileFor(payload);
      final plan = UpdatePlan(
        manifest: _manifest(assetBase: ''),
        full: UpdateFile(name: 'f.bin', size: full.size, sha256: full.sha256),
        patch: UpdatePatch(
          name: 'p.patch',
          size: bad.length,
          sha256: sha256.convert(bad).toString(),
          fromBuild: 118,
          fromSha256: 'x',
        ),
      );
      final service = UpdateService(
        dio: Dio(),
        native: _FakeNative(base.path),
        stagingDir: () async => tmp,
      );
      // One server for both files: first request is the patch, then the full APK.
      var n = 0;
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.add(n++ == 0 ? bad : payload);
        await req.response.close();
      });
      final src = UpdateSource.parse('http://127.0.0.1:${server.port}/latest.json')!;
      final out = await service.prepareApk(plan, src, wifiOnly: false, onWifi: () async => true);
      expect(out.readAsBytesSync(), payload);
    });

    test('Wi-Fi only blocks before any download starts', () async {
      final plan = UpdatePlan(manifest: _manifest(assetBase: ''), full: fileFor(payload), patch: null);
      final src = UpdateSource.parse('http://127.0.0.1:${server.port}/latest.json')!;
      await expectLater(
        svc().prepareApk(plan, src, wifiOnly: true, onWifi: () async => false),
        throwsA(isA<UpdateException>().having((e) => e.needsWifi, 'needsWifi', isTrue)),
      );
    });
  });
}
