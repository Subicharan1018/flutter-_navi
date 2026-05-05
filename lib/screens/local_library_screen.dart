import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/local_library_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/song_tile.dart';
import '../core/theme.dart';

// =============================================================================
// LocalLibraryScreen
//
// Shown when the user is in Local (Offline) Mode.
// Displays:
//   • A scan button to trigger folder indexing.
//   • Progress indicator during the scan.
//   • The resulting list of locally found songs.
//   • A shortcut to open Settings for folder management.
// =============================================================================

class LocalLibraryScreen extends ConsumerWidget {
  const LocalLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localState = ref.watch(localLibraryProvider);
    final tokens = ThemeTokens.of(context);
    final folders = ref.watch(settingsProvider).localMusicFolders;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tokens.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: tokens.bgBase,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + 16,
                  16,
                  8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      color: tokens.accent,
                      size: 26,
                    ),
                    const SizedBox(width: 10),
                    Text('Local Music', style: tokens.headingMd),
                    const Spacer(),
                    // Scan button
                    Semantics(
                      button: true,
                      label: 'Scan local folders',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: localState.isScanning
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: tokens.accent,
                                  ),
                                )
                              : Icon(
                                  Icons.refresh_rounded,
                                  color: tokens.textPrimary,
                                  size: 24,
                                ),
                          onPressed: localState.isScanning
                              ? null
                              : () => ref
                                    .read(localLibraryProvider.notifier)
                                    .scan(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Info / folder count ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  folders.isEmpty
                      ? 'No folders configured — go to Settings → Local Music to add folders.'
                      : '${folders.length} folder${folders.length == 1 ? '' : 's'} configured'
                            '${localState.songs.isNotEmpty ? ' • ${localState.songs.length} songs found' : ''}',
                  style: TextStyle(color: tokens.textMuted, fontSize: 13),
                ),
              ),
            ),

            // ── Error banner ─────────────────────────────────────────────
            if (localState.error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      localState.error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),

            // ── Play All button ──────────────────────────────────────────
            if (localState.songs.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      _PlayAllButton(songs: localState.songs),
                      const SizedBox(width: 12),
                      _ShufflePlayButton(songs: localState.songs),
                    ],
                  ),
                ),
              ),

            // ── Song list ────────────────────────────────────────────────
            if (localState.songs.isEmpty && !localState.isScanning)
              SliverFillRemaining(
                child: _EmptyState(foldersConfigured: folders.isNotEmpty),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(top: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, index) => RepaintBoundary(
                      child:
                          SongTile(
                            song: localState.songs[index],
                            onTap: () => ref
                                .read(playerProvider.notifier)
                                .setQueue(localState.songs, index),
                          ).animate().fadeIn(
                            duration: 350.ms,
                            delay: (index * 15).clamp(0, 240).ms,
                          ),
                    ),
                    childCount: localState.songs.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
      ),
    );
  }
}

// ─── Play All button ──────────────────────────────────────────────────────────

class _PlayAllButton extends ConsumerWidget {
  final List songs;
  const _PlayAllButton({required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => ref
            .read(playerProvider.notifier)
            .playPlaylist(songs.cast(), shuffle: false),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: tokens.accent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                color: tokens.isLight ? Colors.white : Colors.black,
                size: 20,
              ),
              const SizedBox(width: 6),
              Text(
                'Play All',
                style: TextStyle(
                  color: tokens.isLight ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shuffle Play button ──────────────────────────────────────────────────────

class _ShufflePlayButton extends ConsumerWidget {
  final List songs;
  const _ShufflePlayButton({required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ThemeTokens.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => ref
            .read(playerProvider.notifier)
            .playPlaylist(songs.cast(), shuffle: true),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: tokens.bgElevated,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shuffle_rounded, color: tokens.accent, size: 18),
              const SizedBox(width: 6),
              Text(
                'Shuffle',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool foldersConfigured;
  const _EmptyState({required this.foldersConfigured});

  @override
  Widget build(BuildContext context) {
    final tokens = ThemeTokens.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            foldersConfigured
                ? Icons.find_in_page_rounded
                : Icons.folder_off_rounded,
            color: tokens.textMuted,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            foldersConfigured
                ? 'Tap the refresh button to scan for music'
                : 'Add music folders in Settings',
            style: TextStyle(color: tokens.textMuted, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
