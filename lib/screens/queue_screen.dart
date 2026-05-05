import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final service = ref.watch(subsonicServiceProvider);

    if (playerState.queue.isEmpty) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: BoxDecoration(
          color: ThemeTokens.of(context).bgSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.playlist_remove_rounded,
                color: ThemeTokens.of(context).textMuted,
                size: 48,
              ),
              SizedBox(height: 16),
              Text(
                'Queue is empty',
                style: TextStyle(
                  color: ThemeTokens.of(context).textMuted,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final currentSong = playerState.queue[playerState.currentIndex];

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(
        color: ThemeTokens.of(context).bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          SizedBox(height: 12),
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: ThemeTokens.of(context).textPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          SizedBox(height: 24),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // --- HISTORY SECTION ---
                if (playerState.historySongs.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'History',
                          style: TextStyle(
                            color: ThemeTokens.of(context).textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.read(playerProvider.notifier).clearHistory(),
                          child: Text(
                            'Clear',
                            style: TextStyle(
                              color: ThemeTokens.of(context).accent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...playerState.historySongs.asMap().entries.map((entry) {
                    final song = entry.value;
                    return _QueueTile(
                      key: ValueKey('hist_${song.id}_${entry.key}'),
                      song: song,
                      index: entry.key,
                      service: service,
                      isHistory: true,
                      onTap:
                          () {}, // History taps could jump back, but let's keep it simple
                      onRemove: () {},
                    );
                  }),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Divider(
                      color: ThemeTokens.of(context).outline,
                      thickness: 1,
                    ),
                  ),
                ],

                // --- NOW PLAYING SECTION ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'Now Playing',
                        style: TextStyle(
                          color: ThemeTokens.of(context).textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                            Icons.equalizer_rounded,
                            color: ThemeTokens.of(context).accent,
                            size: 20,
                          )
                          .animate(onPlay: (c) => c.repeat())
                          .shimmer(
                            duration: 1200.ms,
                            color: ThemeTokens.of(
                              context,
                            ).textPrimary.withOpacity(0.5),
                          ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ThemeTokens.of(
                      context,
                    ).textPrimary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ThemeTokens.of(context).outline),
                  ),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: ThemeTokens.of(context).outline,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CachedNetworkImage(
                            imageUrl: service.getCoverArtUrl(
                              currentSong.coverArt,
                            ),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentSong.title,
                              style: TextStyle(
                                color: ThemeTokens.of(context).textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 4),
                            Text(
                              currentSong.artist,
                              style: TextStyle(
                                color: ThemeTokens.of(context).textMuted,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 32),

                // --- UP NEXT SECTION ---
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Up Next',
                      style: TextStyle(
                        color: ThemeTokens.of(context).textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),

                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorder: (oldIndex, newIndex) {
                    ref
                        .read(playerProvider.notifier)
                        .reorderQueue(oldIndex, newIndex);
                  },
                  itemCount: playerState.queue.length,
                  itemBuilder: (context, index) {
                    final song = playerState.queue[index];
                    if (index <= playerState.currentIndex)
                      return SizedBox(key: ValueKey('spacer_$index'));

                    return _QueueTile(
                      key: ValueKey('next_${song.id}_$index'),
                      song: song,
                      index: index,
                      service: service,
                      onTap: () {
                        ref.read(playerProvider.notifier).jumpTo(index);
                        HapticFeedback.lightImpact();
                      },
                      onRemove: () {
                        ref
                            .read(playerProvider.notifier)
                            .removeFromQueue(index);
                        HapticFeedback.mediumImpact();
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  final dynamic song;
  final int index;
  final dynamic service;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool isHistory;

  const _QueueTile({
    super.key,
    required this.song,
    required this.index,
    required this.service,
    required this.onTap,
    required this.onRemove,
    this.isHistory = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Material(
      color: Colors.transparent,
      child: CupertinoClickable(
        onTap: isHistory ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: ThemeTokens.of(context).outline),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CachedNetworkImage(
                    imageUrl: service.getCoverArtUrl(song.coverArt),
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: TextStyle(
                        color: isHistory
                            ? ThemeTokens.of(context).textMuted
                            : ThemeTokens.of(context).textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      song.artist,
                      style: TextStyle(
                        color: ThemeTokens.of(context).textMuted,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isHistory) ...[
                SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      Icons.menu_rounded,
                      color: ThemeTokens.of(context).textMuted,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (isHistory) return content;

    return Slidable(
      key: ValueKey(song.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.2,
        children: [
          SlidableAction(
            onPressed: (_) => onRemove(),
            backgroundColor: Colors.redAccent,
            foregroundColor: ThemeTokens.of(context).textPrimary,
            icon: Icons.delete_outline_rounded,
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: content,
    );
  }
}
