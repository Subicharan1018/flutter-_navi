import 'package:flutter/widgets.dart';

import '../../core/hive_boxes.dart';
import '../art/empty_art.dart';
import 'microduck.dart';
import 'microduck_mesh.dart';
import 'microduck_pose.dart';
import 'microduck_strip.dart';

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

  static MicroduckSkin _skin() {
    try {
      return cleanMicroduckSkin(HiveBoxes.prefs.get(HiveBoxes.kMicroduckSkin)?.toString());
    } catch (_) {
      return MicroduckSkin.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    if (kind == EmptyArtKind.offline || !showDuckInEmptyState(seed, now) || !_enabled()) {
      return EmptyArt(kind, width: width);
    }
    final duck = SizedBox(
      width: width,
      height: width * 0.9,
      child: ClipRect(
        child: Center(
          child: Microduck(
            pose: resolveMicroduckPose(
              playing: false,
              now: now,
              reducedMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
            ),
            size: width * 0.9,
            skin: _skin(),
            interactive: true,
          ),
        ),
      ),
    );
    // One robot at a time: with the mini player's up, the drawing stays.
    return ValueListenableBuilder<bool>(
      valueListenable: microduckMiniVisible,
      builder: (context, mini, child) => mini ? EmptyArt(kind, width: width) : child!,
      child: duck,
    );
  }
}
