/// Per-song download status tracked by [DownloadStateNotifier].
///
/// Note: [OfflineService] has its own `DownloadState` for bulk-playlist
/// progress.  This model is a separate, Riverpod-managed per-song record.
enum SongDownloadStatus {
  /// Song has not been downloaded and is not queued.
  notDownloaded,

  /// Song is queued but the download has not started yet.
  queued,

  /// Song is actively being downloaded.
  downloading,

  /// Song file is present on disk.
  downloaded,

  /// The last download attempt failed.
  failed,
}

/// Immutable state record for a single song's download lifecycle.
class SongDownloadState {
  final String songId;
  final SongDownloadStatus status;

  /// Download progress in the range [0.0, 1.0].
  /// Only meaningful when [status] == [SongDownloadStatus.downloading].
  final double progress;

  /// Human-readable error message.  Non-null only when [status] == [SongDownloadStatus.failed].
  final String? errorMessage;

  const SongDownloadState({
    required this.songId,
    this.status = SongDownloadStatus.notDownloaded,
    this.progress = 0.0,
    this.errorMessage,
  });

  bool get isDownloaded => status == SongDownloadStatus.downloaded;

  /// True while a download is in progress (queued or downloading).
  bool get isActive =>
      status == SongDownloadStatus.queued ||
      status == SongDownloadStatus.downloading;

  SongDownloadState copyWith({
    SongDownloadStatus? status,
    double? progress,
    String? errorMessage,
  }) {
    return SongDownloadState(
      songId: songId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
