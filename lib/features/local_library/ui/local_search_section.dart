import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/player_provider.dart';
import '../../../models/song.dart';
import '../../../widgets/song_tile.dart';
import '../../../widgets/ui/media.dart';

/// "On this device" matches in Search: songs from Settings > Local music
/// that the server does not have. Plays the matches as a queue.
class LocalSearchSection extends ConsumerWidget {
  final List<Song> songs;
  final VoidCallback onUsed;
  const LocalSearchSection({super.key, required this.songs, required this.onUsed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (songs.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverMainAxisGroup(slivers: [
      const SliverToBoxAdapter(child: SectionHeader(title: 'On This Device')),
      SliverFixedExtentList(
        itemExtent: SongTile.extent,
        delegate: SliverChildBuilderDelegate(
          (context, i) => SongTile(
            song: songs[i],
            onTap: () {
              onUsed();
              ref.read(playerProvider.notifier).setQueue(songs, i, playlistName: 'On this device');
            },
          ),
          childCount: songs.length,
        ),
      ),
    ]);
  }
}
