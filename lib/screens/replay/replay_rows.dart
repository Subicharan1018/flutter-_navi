import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers/library_provider.dart';
import '../../providers/navivibe_replay_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/format.dart';
import '../../widgets/app_scaffold.dart' show navigateInApp;
import '../../widgets/art/navi_icons.dart';
import '../../widgets/cover_art.dart';
import '../../widgets/ui/action_sheet.dart';
import '../../widgets/ui/media.dart';
import '../artist_screen.dart';

/// A ranked song in Replay: rank, cover, title / artist, plays.
class ReplayTrackRow extends ConsumerWidget {
  final ReplayTrack track;
  final int rank;
  final VoidCallback? onTap;
  const ReplayTrackRow({super.key, required this.track, required this.rank, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final art = ref.watch(songCoverUrlProvider('${track.title}|${track.artist}')).asData?.value;
    return CupertinoClickable(
      onTap: onTap,
      scaleFactor: 0.99,
      semanticLabel: '$rank. ${track.title} by ${track.artist}, ${track.playCount} plays',
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '$rank',
                  style: t.callout.copyWith(
                    color: rank <= 3 ? t.textPrimary : t.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              CoverArt(url: art, size: 46, radius: Radii.thumb),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                    Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Text(
                track.playCount == 1 ? '1 play' : '${compactCount(track.playCount)} plays',
                style: t.footnote,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A top artist as a round portrait with their play count.
class ReplayArtistCard extends ConsumerWidget {
  final ReplayArtist artist;
  final double size;
  const ReplayArtistCard({super.key, required this.artist, required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final art = ref.watch(artistCoverUrlProvider(artist.artist)).asData?.value;
    return MediaCard(
      title: artist.artist,
      subtitle: '${compactCount(artist.playCount)} plays',
      artUrl: art,
      size: size,
      circular: true,
      placeholderIcon: NaviGlyph.person,
      onTap: () => openArtistByName(context, ref, artist.artist),
    );
  }
}

/// Opens an artist page from a name alone (stats and Replay only know
/// names): finds the artist's id with a search, then navigates.
Future<void> openArtistByName(BuildContext context, WidgetRef ref, String name) async {
  try {
    final results = await ref.read(subsonicServiceProvider).search(name);
    final match = results.artists.where((a) => a.name.toLowerCase() == name.toLowerCase()).firstOrNull ??
        results.artists.firstOrNull;
    if (!context.mounted) return;
    if (match == null) {
      showToast(context, '$name isn’t in your library');
      return;
    }
    navigateInApp(context, ArtistScreen(artistId: match.id, name: match.name));
  } catch (_) {
    if (context.mounted) showToast(context, 'Couldn’t open $name. Check your connection.');
  }
}
