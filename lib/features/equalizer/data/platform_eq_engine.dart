import 'package:just_audio/just_audio.dart';

import '../../../utils/platform_utils.dart';
import 'eq_engine.dart';

/// The equalizer for this platform, or null where there is none: browsers (and
/// the Apple builds, which are not shipped).
EqEngine? platformEqEngine(AudioPlayer player) {
  if (PlatformUtils.isAndroid) return AndroidEqEngine(player);
  if (PlatformUtils.isLinux || PlatformUtils.isWindows) return MpvEqEngine();
  return null;
}
