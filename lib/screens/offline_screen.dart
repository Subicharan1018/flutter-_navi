import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song.dart';
import '../offline_service.dart';
import '../providers/player_provider.dart';
import '../core/theme.dart';
import '../widgets/song_tile.dart';
import '../widgets/app_scaffold.dart';

class OfflineScreen extends ConsumerStatefulWidget {
  const OfflineScreen({super.key});

  @override
  ConsumerState<OfflineScreen> createState() => _OfflineScreenState();
}

class _OfflineScreenState extends ConsumerState<OfflineScreen> {
  List<Song> _songs = [];
  bool _isLoading = true;
  String _storageUsed = '';

  @override
  void initState() {
    super.initState();
    _loadOfflineData();
  }

  Future<void> _loadOfflineData() async {
    setState(() => _isLoading = true);
    try {
      final songs = await OfflineService().getDownloadedSongsMetadata();
      final sizeBytes = await OfflineService().getDownloadedSize();
      
      if (mounted) {
        setState(() {
          _songs = songs;
          _storageUsed = OfflineService().formatSize(sizeBytes);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _playAll({bool shuffle = false}) {
    if (_songs.isEmpty) return;
    final notifier = ref.read(playerProvider.notifier);
    
    // Create a mutable copy and optionally shuffle
    final queue = List<Song>.from(_songs);
    if (shuffle) {
      queue.shuffle();
    }
    
    notifier.setQueue(queue, 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeTokens.of(context).bgBase,
      appBar: AppBar(
        title: const Text('Offline Music'),
        backgroundColor: ThemeTokens.of(context).bgSurface,
        foregroundColor: ThemeTokens.of(context).textPrimary,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
              ? _buildEmptyState(context)
              : _buildContent(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded, size: 80, color: ThemeTokens.of(context).textMuted),
          const SizedBox(height: 16),
          Text(
            'No offline music',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: ThemeTokens.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Download songs from the options menu to play them without internet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: ThemeTokens.of(context).textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_songs.length} ${_songs.length == 1 ? 'song' : 'songs'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: ThemeTokens.of(context).textSecondary,
                    ),
                  ),
                  Text(
                    _storageUsed,
                    style: TextStyle(
                      fontSize: 14,
                      color: ThemeTokens.of(context).textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _playAll(shuffle: false),
                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                      label: const Text(
                        'Play All',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeTokens.of(context).textPrimary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _playAll(shuffle: true),
                      icon: Icon(Icons.shuffle_rounded, color: ThemeTokens.of(context).textPrimary),
                      label: Text(
                        'Shuffle',
                        style: TextStyle(
                          color: ThemeTokens.of(context).textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ThemeTokens.of(context).bgElevated,
                        foregroundColor: ThemeTokens.of(context).textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // List
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadOfflineData,
            color: ThemeTokens.of(context).accent,
            backgroundColor: ThemeTokens.of(context).bgSurface,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 100), // Player padding
              itemCount: _songs.length,
              itemBuilder: (context, index) {
                final song = _songs[index];
                return SongTile(
                  song: song,
                  onTap: () {
                    ref.read(playerProvider.notifier).setQueue(_songs, index);
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
