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
        decoration: const BoxDecoration(
          color: AppTheme.surfaceLevel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.playlist_remove_rounded, color: AppTheme.textMuted, size: 48),
              const SizedBox(height: 16),
              Text('Queue is empty', style: TextStyle(color: AppTheme.textMuted, fontSize: 15)),
            ],
          ),
        ),
      );
    }

    final currentSong = playerState.queue[playerState.currentIndex];

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceLevel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: AppTheme.textPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // --- HISTORY SECTION ---
                if (playerState.historySongs.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'History',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref.read(playerProvider.notifier).clearHistory(),
                          child: const Text('Clear', style: TextStyle(color: AppTheme.electricBlue, fontSize: 13)),
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
                      onTap: () {}, // History taps could jump back, but let's keep it simple
                      onRemove: () {},
                    );
                  }),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Divider(color: AppTheme.outlineColor, thickness: 1),
                  ),
                ],

                // --- NOW PLAYING SECTION ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text(
                        'Now Playing',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.equalizer_rounded, color: AppTheme.electricBlue, size: 20)
                          .animate(onPlay: (c) => c.repeat())
                          .shimmer(duration: 1200.ms, color: AppTheme.textPrimary.withOpacity(0.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.textPrimary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.outlineColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.outlineColor),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CachedNetworkImage(
                            imageUrl: service.getCoverArtUrl(currentSong.coverArt),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentSong.title,
                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentSong.artist,
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // --- UP NEXT SECTION ---
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Up Next',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorder: (oldIndex, newIndex) {
                    ref.read(playerProvider.notifier).reorderQueue(oldIndex, newIndex);
                  },
                  itemCount: playerState.queue.length,
                  itemBuilder: (context, index) {
                    final song = playerState.queue[index];
                    if (index <= playerState.currentIndex) return SizedBox(key: ValueKey('spacer_$index'));

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
                        ref.read(playerProvider.notifier).removeFromQueue(index);
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
                  border: Border.all(color: AppTheme.outlineColor),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: TextStyle(
                        color: isHistory ? AppTheme.textMuted : AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isHistory) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(
                      Icons.menu_rounded,
                      color: AppTheme.textMuted,
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
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: content,
    );
  }
}
