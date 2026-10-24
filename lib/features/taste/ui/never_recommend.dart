import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart' show SheetAction, SheetGroup, showToast;
import '../../listen/data/listen_models.dart';
import '../logic/taste_providers.dart';

/// "this song", "the artist Anirudh", "the composer Anirudh": how the choice reads.
String neverLabel(TasteExclusion e) => switch (e.kind) {
      TasteKind.song => 'This song',
      TasteKind.artist => 'Artist: ${e.label}',
      TasteKind.composer => 'Composer: ${e.label}',
    };

/// Asks what to stop recommending for [song] (the song, its artist or its
/// composer), tells the server, and offers Undo.
Future<void> showNeverRecommend(BuildContext context, ProviderContainer ref, Song song) {
  final options = neverOptionsFor(song);
  return showPlatformSheet<void>(
    context: context,
    title: 'Never recommend',
    builder: (ctx) {
      final t = ThemeTokens.of(ctx);
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: SheetGroup(children: [
          for (final o in options)
            SheetAction(
              label: neverLabel(o),
              trailing: NaviIcon(NaviGlyph.block, size: 21, color: t.textPrimary),
              onTap: () => addNeverRecommend(context, ref, o),
            ),
        ]),
      );
    },
  );
}

/// Adds [e]; the confirmation carries Undo. Failures say so.
Future<void> addNeverRecommend(BuildContext context, ProviderContainer ref, TasteExclusion e) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final notifier = ref.read(tasteExclusionsProvider.notifier);
  try {
    await notifier.add(e);
  } catch (_) {
    if (context.mounted) showToast(context, 'Couldn’t save that. Check your connection and try again.');
    return;
  }
  messenger
    ?..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text('Won’t recommend ${e.kind == TasteKind.song ? 'this song' : e.label} again'),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: 'Undo', onPressed: () => notifier.remove(e)),
    ));
}
