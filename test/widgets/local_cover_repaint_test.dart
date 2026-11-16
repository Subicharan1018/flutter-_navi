import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/local_library/logic/local_index.dart';
import 'package:navivibe/widgets/cover_art.dart';

void main() {
  tearDown(() => LocalLibraryIndex.instance.clear());

  testWidgets('a device cover repaints when the local index finishes loading', (tester) async {
    final dir = Directory.systemTemp.createTempSync('navi_cover_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}c.jpg')..writeAsBytesSync([1, 2, 3]);
    const id = 'local:abc';

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: CoverArt(url: pendingLocalCoverUrl(id), size: 48)),
    ));
    // Index not loaded: only the placeholder.
    expect(find.byType(Image), findsNothing);

    LocalLibraryIndex.instance.replace(paths: {id: '/x.mp3'}, covers: {id: file.path});
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).imageProvider, isA<FileImage>());
  });

  testWidgets('an unrelated index change does not rebuild a settled cover', (tester) async {
    var builds = 0;
    const id = 'local:abc';
    LocalLibraryIndex.instance.replace(paths: const {}, covers: const {});
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(builder: (c) {
          builds++;
          return CoverArt(url: pendingLocalCoverUrl(id), size: 48);
        }),
      ),
    ));
    LocalLibraryIndex.instance.replace(paths: const {'x': 'y'}, covers: const {'other': '/o.jpg'});
    await tester.pump();
    expect(builds, 1);
    expect(find.byType(Image), findsNothing);
  });
}
