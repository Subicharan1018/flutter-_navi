import 'package:flutter/widgets.dart';

import '../../core/hive_boxes.dart';
import '../art/empty_art.dart';
import 'microduck.dart';
import 'microduck_pose.dart';

/// The empty-state picture: usually the drawing for [kind], but on some days
/// (see [showDuckInEmptyState]) Microduck stands in, asleep at night. [seed]
/// is the message's title so different messages vary independently.
///
/// Offline and connection errors keep their drawing: the duck is for the
/// quiet "nothing here yet" moments, not for failures.
class EmptyIllustration extends StatelessWidget {
  final EmptyArtKind kind;
  final String seed;
  final double width;

  const EmptyIllustration(this.kind, {super.key, required this.seed, this.width = 160});

  static bool _enabled() {
    try {
      return HiveBoxes.prefs.get(HiveBoxes.kMicroduckEnabled) != false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    if (kind == EmptyArtKind.offline || !showDuckInEmptyState(seed, now) || !_enabled()) {
      return EmptyArt(kind, width: width);
    }
    return SizedBox(
      width: width,
      height: width * 0.75,
      child: Center(
        child: Microduck(
          pose: resolveMicroduckPose(
            playing: false,
            now: now,
            reducedMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
          ),
          size: width * 0.62,
        ),
      ),
    );
  }
}
