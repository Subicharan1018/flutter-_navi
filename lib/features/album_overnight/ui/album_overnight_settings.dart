import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/app_scaffold.dart' show navigateInApp;
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/grouped_list.dart';
import '../../online_fetch/data/online_fetch_api.dart' show OnlineFetchException;
import '../logic/album_overnight_providers.dart';
import 'album_overnight_screen.dart';

String _nightLabel(int n) => '$n songs';
String _albumLabel(int n) => '$n tracks';

/// Settings › Album Overnight. Shown only to accounts that may download. Everything lives on the server (it
/// finds the albums and does the downloading); this only asks it.
class AlbumOvernightSettings extends ConsumerWidget {
  const AlbumOvernightSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(albumOvernightAvailableProvider)) return const SizedBox.shrink();
    final a = ref.watch(albumOvernightProvider).asData?.value;
    final c = ref.read(albumOvernightProvider.notifier);
    Future<void> run(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        if (context.mounted) {
          showToast(context, e is OnlineFetchException ? e.message : 'That didn’t work. Check your connection and try again.');
        }
      }
    }

    final enabled = a?.enabled ?? false;
    final waiting = a?.waiting ?? 0;
    return GroupedSection(
      header: 'Album Overnight',
      footer: 'When a song you fetch comes in, the rest of its film album that you don’t have is fetched at night, '
          'a few at a time. Only songs that arrive after you turn this on count.',
      children: [
        GroupedSwitchRow(
          title: 'Album Overnight',
          icon: NaviGlyph.downloadCircle,
          value: enabled,
          onChanged: a == null ? (_) {} : (v) => run(() => c.setEnabled(v)),
        ),
        if (enabled && a != null) ...[
          GroupedSwitchRow(
            title: 'Film Albums Only',
            icon: NaviGlyph.stack,
            value: a.filmOnly,
            onChanged: (v) => run(() => c.setFilmOnly(v)),
          ),
          GroupedRow(
            title: 'Songs a Night',
            icon: NaviGlyph.clock,
            value: _nightLabel(a.perNight),
            onTap: () async {
              final v = await showChoiceSheet<int>(
                context,
                title: 'Songs a Night',
                options: a.perNightChoices,
                selected: a.perNightChoices.contains(a.perNight) ? a.perNight : a.perNightChoices.first,
                label: _nightLabel,
              );
              if (v != null) await run(() => c.setPerNight(v));
            },
          ),
          GroupedRow(
            title: 'Most Per Album',
            icon: NaviGlyph.playlist,
            value: _albumLabel(a.maxPerAlbum),
            onTap: () async {
              final v = await showChoiceSheet<int>(
                context,
                title: 'Most Per Album',
                options: a.maxPerAlbumChoices,
                selected: a.maxPerAlbumChoices.contains(a.maxPerAlbum) ? a.maxPerAlbum : a.maxPerAlbumChoices.first,
                label: _albumLabel,
              );
              if (v != null) await run(() => c.setMaxPerAlbum(v));
            },
          ),
        ],
        if (enabled || (a?.albums.isNotEmpty ?? false))
          GroupedRow(
            title: 'Queue',
            icon: NaviGlyph.note,
            value: waiting == 0 ? null : '$waiting waiting',
            onTap: () => navigateInApp(context, const AlbumOvernightScreen(), title: 'Album Overnight'),
          ),
      ],
    );
  }
}
