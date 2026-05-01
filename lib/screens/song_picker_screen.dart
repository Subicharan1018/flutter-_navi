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
            content: Text('Added $added song${added == 1 ? '' : 's'} to ${widget.playlistName}'),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding songs: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSongsAsync = ref.watch(allSongsProvider);
    final service = ref.watch(subsonicServiceProvider);

    return Scaffold(
      backgroundColor: AppTheme.coreBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.coreBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Add to ${widget.playlistName}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
        leading: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: AppTheme.textPrimary, size: 24),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      // UX FIX: Floating Save button appears when songs are selected.
      floatingActionButton: _selectedSongIds.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.electricBlue,
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(
                _isSaving
                    ? 'Saving...'
                    : 'Save (${_selectedSongIds.length})',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
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
                color: AppTheme.surfaceLevel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.outlineColor),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                cursorColor: AppTheme.electricBlue,
                decoration: InputDecoration(
                  hintText: 'Search for songs...',
                  hintStyle: TextStyle(color: AppTheme.textMuted.withOpacity(0.5), fontSize: 15),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 22),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          Expanded(
            child: allSongsAsync.when(
              data: (songs) {
                final filteredSongs = songs.where((s) =>
                    s.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                    s.artist.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

                if (filteredSongs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, color: AppTheme.textMuted, size: 48),
                        SizedBox(height: 16),
                        Text('No songs found', style: TextStyle(color: AppTheme.textMuted, fontSize: 15)),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.outlineColor),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CachedNetworkImage(
                            imageUrl: service.getCoverArtUrl(song.coverArt),
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: AppTheme.surfaceLevel),
                            errorWidget: (_, __, ___) => Container(
                              color: AppTheme.surfaceLevel,
                              child: const Icon(Icons.music_note_rounded, color: AppTheme.textMuted, size: 24),
                            ),
                          ),
                        ),
                      ),
                      title: Text(song.title, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                      subtitle: Text(song.artist, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                      trailing: SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            isSelected
                              ? Icons.check_circle_rounded
                              : Icons.add_circle_outline_rounded,
                            color: isSelected ? AppTheme.electricBlue : AppTheme.textMuted,
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
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.electricBlue)),
              error: (e, st) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 12),
                    Text('Error: $e', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
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
