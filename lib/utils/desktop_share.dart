import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Linux has no share sheet: share_plus can only open a mail draft there, and
/// throws for files. The text goes to the clipboard and a picture to the
/// Downloads folder. Returns the sentence to confirm with.
Future<String> shareByCopying(String text, {File? file, Future<Directory?> Function()? downloads}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (file == null) return 'Copied. Paste it into a message.';
  const failed = 'Text copied. The picture couldn’t be saved.';
  try {
    final dir = await (downloads ?? getDownloadsDirectory)();
    if (dir == null) return failed;
    await dir.create(recursive: true);
    await file.copy('${dir.path}${Platform.pathSeparator}${file.uri.pathSegments.last}');
    return 'Picture saved to Downloads, text copied.';
  } on FileSystemException {
    return failed;
  }
}
