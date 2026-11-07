import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/utils/platform_utils.dart';

/// Every test starts as a phone, whatever the machine running it is. Desktop
/// tests say so themselves (`PlatformUtils.debugDesktopOverride = true`), so a
/// suite run on Windows and one run on Linux CI see the same app.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => PlatformUtils.debugDesktopOverride = false);
  await testMain();
}
