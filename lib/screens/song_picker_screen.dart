import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../core/theme.dart';

class SongPickerScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final String playlistName;

  const SongPickerScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
  });

  @override
  ConsumerState<SongPickerScreen> createState() => _SongPickerScreenState();
}

class _SongPickerScreenState extends ConsumerState<SongPickerScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // UX FIX: Local selection set — no network call until Save.
  final Set<String> _selectedSongIds = {};
  bool _isSaving = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // UX FIX: Toggle song selection locally.
  void _toggleSong(String songId) {
    setState(() {
      if (_selectedSongIds.contains(songId)) {
        _selectedSongIds.remove(songId);
      } else {
        _selectedSongIds.add(songId);
      }
    });
  }

  // UX FIX: Batch-save all selected songs.
  Future<void> _save() async {
    if (_selectedSongIds.isEmpty) return;
    setState(() => _isSaving = true);
    final service = ref.read(subsonicServiceProvider);
    int added = 0;
    try {
      for (final songId in _selectedSongIds) {
        await service.updatePlaylist(widget.playlistId, songIdToAdd: songId);
        added++;
      }
      ref.invalidate(songsInPlaylistProvider(widget.playlistId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added $added song${added == 1 ? '' : 's'} to ${widget.playlistName}',
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error adding songs: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSongsAsync = ref.watch(allSongsProvider);
    final service = ref.watch(subsonicServiceProvider);

    return Scaffold(
      backgroundColor: ThemeTokens.of(context).bgBase,
      appBar: AppBar(
        backgroundColor: ThemeTokens.of(context).bgBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Add to ${widget.playlistName}',
          style: TextStyle(
            color: ThemeTokens.of(context).textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: ThemeTokens.of(context).textPrimary,
              size: 24,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      // UX FIX: Floating Save button appears when songs are selected.
      floatingActionButton: _selectedSongIds.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: ThemeTokens.of(context).accent,
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ThemeTokens.of(context).bgBase,
                      ),
                    )
                  : Icon(
                      Icons.save_rounded,
                      color: ThemeTokens.of(context).bgBase,
                    ),
              label: Text(
                _isSaving ? 'Saving...' : 'Save (${_selectedSongIds.length})',
                style: TextStyle(
                  color: ThemeTokens.of(context).bgBase,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: ThemeTokens.of(context).bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ThemeTokens.of(context).outline),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: TextStyle(
                  color: ThemeTokens.of(context).textPrimary,
                  fontSize: 15,
                ),
                cursorColor: ThemeTokens.of(context).accent,
                decoration: InputDecoration(
                  hintText: 'Search for songs...',
                  hintStyle: TextStyle(
                    color: ThemeTokens.of(
                      context,
                    ).textMuted.withValues(alpha: 0.5),
                    fontSize: 15,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: ThemeTokens.of(context).textMuted,
                    size: 22,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          Expanded(
            child: allSongsAsync.when(
              data: (songs) {
                final filteredSongs = songs
                    .where(
                      (s) =>
                          s.title.toLowerCase().contains(
                            _searchQuery.toLowerCase(),
                          ) ||
                          s.artist.toLowerCase().contains(
                            _searchQuery.toLowerCase(),
                          ),
                    )
                    .toList();

                if (filteredSongs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          color: ThemeTokens.of(context).textMuted,
                          size: 48,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No songs found',
                          style: TextStyle(
                            color: ThemeTokens.of(context).textMuted,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80), // space for FAB
                  itemCount: filteredSongs.length,
                  itemBuilder: (context, index) {
                    final song = filteredSongs[index];
                    final isSelected = _selectedSongIds.contains(song.id);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: ThemeTokens.of(context).outline,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CachedNetworkImage(
                            imageUrl: service.getCoverArtUrl(song.coverArt),
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: ThemeTokens.of(context).bgSurface,
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: ThemeTokens.of(context).bgSurface,
                              child: Icon(
                                Icons.music_note_rounded,
                                color: ThemeTokens.of(context).textMuted,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        song.title,
                        style: TextStyle(
                          color: ThemeTokens.of(context).textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        song.artist,
                        style: TextStyle(
                          color: ThemeTokens.of(context).textMuted,
                          fontSize: 13,
                        ),
                      ),
                      trailing: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            color: isSelected
                                ? ThemeTokens.of(context).accent
                                : ThemeTokens.of(context).textMuted,
                            size: 24,
                          ),
                          // UX FIX: Toggle local selection — no network call.
                          onPressed: () => _toggleSong(song.id),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(
                  color: ThemeTokens.of(context).accent,
                ),
              ),
              error: (e, st) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Error: $e',
                      style: TextStyle(
                        color: ThemeTokens.of(context).textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
