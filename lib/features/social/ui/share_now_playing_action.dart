import 'package:flutter/cupertino.dart';

import '../../../models/song.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../logic/share_now_playing.dart';

/// Shares [song] as a text card (share sheet on Android, clipboard on Windows)
/// and confirms with a toast where the sheet itself isn't confirmation enough.
Future<void> runShareNowPlaying(BuildContext context, Song song) async {
  String? message;
  try {
    message = await shareNowPlaying(song);
  } catch (_) {
    message = 'Couldn’t share. Try again.';
  }
  if (message != null && context.mounted) showToast(context, message);
}
