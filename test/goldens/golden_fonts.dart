import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the app's real fonts (Inter, Inter Display) and the icon fonts so
/// goldens render text and glyphs instead of boxes.
Future<void> loadGoldenFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await family('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/Inter-$w.ttf',
  ]);
  await family('InterDisplay', [
    for (final w in ['Medium', 'SemiBold', 'Bold', 'ExtraBold']) 'assets/fonts/InterDisplay-$w.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
  // Cupertino glyphs come from the cupertino_icons package in the pub cache.
  final pubCache = Platform.environment['PUB_CACHE'] ??
      (Platform.isWindows
          ? '${Platform.environment['LOCALAPPDATA']}/Pub/Cache'
          : '${Platform.environment['HOME']}/.pub-cache');
  final hosted = Directory('$pubCache/hosted/pub.dev');
  if (hosted.existsSync()) {
    final pkgs = hosted.listSync().whereType<Directory>().where((d) => d.path.contains('cupertino_icons-')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (pkgs.isNotEmpty) {
      await family('packages/cupertino_icons/CupertinoIcons', ['${pkgs.last.path}/assets/CupertinoIcons.ttf']);
    }
  }
}
