import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:navivibe/utils/platform_utils.dart';

import 'anti_alias_comparator.dart';

/// Applies to every test under test/goldens/: compare goldens ignoring only
/// anti-aliasing, so goldens recorded on one machine pass on another while
/// any real visual change still fails. See [AntiAliasTolerantComparator].
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final current = goldenFileComparator;
  if (current is LocalFileComparator) {
    goldenFileComparator = AntiAliasTolerantComparator(current.basedir.resolve('golden_test.dart'));
  }
  // Phone unless a golden says desktop (see ../flutter_test_config.dart).
  setUp(() => PlatformUtils.debugDesktopOverride = false);
  await testMain();
}
