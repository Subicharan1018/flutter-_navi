import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/add_to_playlist_dialog.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/desktop_dialogs.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../data/fetch_models.dart';
import '../data/online_fetch_api.dart';
import '../logic/online_fetch_providers.dart';
import 'widgets/fetch_candidate_row.dart';

// =============================================================================
// Search online downloads, followed anywhere in the app:
//   FetchActivityRing   a thin progress ring around a control (the Search tab)
//                       while anything downloads
//   FetchFinishedBanner a brief pop-up on the dock when a song, album or
//                       playlist lands, with Play and Add to Playlist
//   showFetchDownloads  everything started this session, with progress
// =============================================================================

/// A thin ring around [child] showing overall progress while anything from
/// Search online is downloading; just [child] otherwise. Rebuilds only on
/// progress changes.
class FetchActivityRing extends ConsumerWidget {
  final Widget child;
  const FetchActivityRing({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (active, progress) = ref.watch(fetchJobsProvider.select((d) => (d.activeCount, d.progress)));
    if (active == 0) return child;
    final t = ThemeTokens.of(context);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: Semantics(
              label: active == 1 ? 'Downloading 1 item' : 'Downloading $active items',
              value: progress == null ? null : '${(progress * 100).round()}%',
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2,
                strokeCap: StrokeCap.round,
                color: t.accent,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Plays the given library songs, or adds them to a playlist — the actions
/// every finished download offers.
mixin FetchSongActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Future<List<Song>> _load(List<String> ids) async {
    final songs = await ref.read(fetchJobsProvider.notifier).songsFor(ids);
    if (songs.isEmpty) throw const OnlineFetchException('These songs aren’t in your library yet.');
    return songs;
  }

  Future<void> playSongs(List<String> ids, {String? name}) async {
    try {
      final songs = await _load(ids);
      await ref.read(playerProvider.notifier).setQueue(songs, 0, playlistName: name ?? 'Search');
    } on Exception catch (e) {
      if (mounted) showToast(context, e is OnlineFetchException ? e.message : 'Couldn’t start playback. Try again.');
    }
  }

  Future<void> addSongsToPlaylist(List<String> ids) async {
    try {
      final songs = await _load(ids);
      if (!mounted) return;
      if (songs.length == 1) {
        await showAddToPlaylist(context, songs.single);
      } else {
        await showAddSongsToPlaylist(context, songs);
      }
    } on Exception catch (e) {
      if (mounted) showToast(context, e is OnlineFetchException ? e.message : 'Couldn’t load the songs. Try again.');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Finish pop-up
// ─────────────────────────────────────────────────────────────────────────────

/// A brief, self-dismissing line on the dock when a download finishes:
/// "Album downloaded · 12 songs added, 2 already owned" with Play and Add to
/// Playlist. Sits on the dock band itself (no card), above the mini player.
/// Tap it for the Downloads list; swipe it away to dismiss.
///
/// Also picks up batches still running on the server when the app starts.
class FetchFinishedBanner extends ConsumerStatefulWidget {
  static const showFor = Duration(seconds: 6);
  const FetchFinishedBanner({super.key});

  @override
  ConsumerState<FetchFinishedBanner> createState() => _FetchFinishedBannerState();
}

class _FetchFinishedBannerState extends ConsumerState<FetchFinishedBanner> with FetchSongActions {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _timer?.cancel();
    ref.read(fetchFinishedProvider.notifier).dismiss();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(onlineFetchAvailableProvider)) return const SizedBox.shrink();
    ref.listen(onlineFetchEnabledProvider, (_, next) {
      if (next.asData?.value == true) ref.read(fetchJobsProvider.notifier).resume();
    });
    ref.listen(fetchFinishedProvider, (_, next) {
      _timer?.cancel();
      if (next == null) return;
      HapticFeedback.lightImpact();
      _timer = Timer(FetchFinishedBanner.showFor, _dismiss);
    });
    final t = ThemeTokens.of(context);
    final f = ref.watch(fetchFinishedProvider);

    return AnimatedSize(
      duration: Motion.standard,
      curve: Motion.ease,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: Motion.standard,
        child: f == null
            ? const SizedBox(width: double.infinity)
            : Dismissible(
                key: ValueKey(f.seq),
                direction: DismissDirection.vertical,
                onDismissed: (_) => _dismiss(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.sm, Space.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          liveRegion: true,
                          label: '${f.headline}. ${f.detail}',
                          hint: 'Shows your downloads',
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              _dismiss();
                              showFetchDownloads(context);
                            },
                            child: Row(
                              children: [
                                CoverArt(
                                  url: f.coverUrl,
                                  size: 36,
                                  radius: Radii.thumb,
                                  placeholderIcon: NaviGlyph.downloadCircle,
                                ),
                                const SizedBox(width: Space.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(f.headline,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
                                      if (f.detail.isNotEmpty)
                                        Text(f.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (f.songIds.isNotEmpty) ...[
                        _IconAction(
                          icon: NaviGlyph.play,
                          label: 'Play',
                          onTap: () {
                            _dismiss();
                            playSongs(f.songIds);
                          },
                        ),
                        _IconAction(
                          icon: NaviGlyph.addToPlaylist,
                          label: 'Add to Playlist',
                          onTap: () {
                            _dismiss();
                            addSongsToPlaylist(f.songIds);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final NaviGlyph icon;
  final String label;
  final VoidCallback onTap;
  const _IconAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onTap,
      child: NaviIcon(icon, size: 22, color: t.accent, semanticLabel: label),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Downloads list
// ─────────────────────────────────────────────────────────────────────────────

/// Everything downloading or downloaded from Search online this session.
Future<void> showFetchDownloads(BuildContext context) => showPlatformSheet<void>(
      context: context,
      builder: (_) => const FetchDownloadsSheet(),
    );

class FetchDownloadsSheet extends ConsumerWidget {
  const FetchDownloadsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final d = ref.watch(fetchJobsProvider);
    final anyFinished = d.jobs.values.any((j) => j.isFinished) || d.batches.values.any((b) => b.isFinished);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.sm, Space.sm),
          child: Row(
            children: [
              Expanded(child: Semantics(header: true, child: Text('Downloads', style: t.title3))),
              if (anyFinished)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                  minimumSize: const Size(44, 44),
                  onPressed: () => ref.read(fetchJobsProvider.notifier).clearFinished(),
                  child: Text('Clear', style: t.body.copyWith(color: t.accent)),
                ),
            ],
          ),
        ),
        if (d.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xxl),
            child: Text('Songs you add from Search online show up here while they download.',
                textAlign: TextAlign.center, style: t.footnote),
          )
        else
          FetchDownloadsList(downloads: d),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

/// The rows of [downloads], newest first. [hideCandidates] leaves out what's
/// already visible elsewhere (the search sheet's own result rows).
class FetchDownloadsList extends StatelessWidget {
  final FetchDownloads downloads;
  final Set<int> hideCandidates;
  const FetchDownloadsList({super.key, required this.downloads, this.hideCandidates = const {}});

  @override
  Widget build(BuildContext context) {
    final batches = [
      for (final b in downloads.batches.values.toList().reversed)
        if (!b.candidateIds.every(hideCandidates.contains)) b,
    ];
    final jobs = [
      for (final j in downloads.jobs.values.toList().reversed)
        if (!hideCandidates.contains(j.candidateId)) j,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in batches) FetchDownloadRow.batch(b),
        for (final j in jobs) FetchDownloadRow.job(j),
      ],
    );
  }
}

/// One download: a song or a batch, its status, and Play / Add to Playlist
/// once it's in the library.
class FetchDownloadRow extends ConsumerStatefulWidget {
  final FetchJob? job;
  final FetchBatch? batch;
  const FetchDownloadRow.job(FetchJob this.job, {super.key}) : batch = null;
  const FetchDownloadRow.batch(FetchBatch this.batch, {super.key}) : job = null;

  @override
  ConsumerState<FetchDownloadRow> createState() => _FetchDownloadRowState();
}

class _FetchDownloadRowState extends ConsumerState<FetchDownloadRow> with FetchSongActions {
  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final j = widget.job;
    final b = widget.batch;
    final title = b?.title ?? j?.title ?? 'Downloading…';
    final subtitle = b != null ? b.artist : (j?.artist ?? '');
    final status = b != null ? fetchBatchStatus(b) : fetchJobStatus(j!);
    final cover = b?.coverUrl ?? ref.read(fetchJobsProvider.notifier).coverFor(j!.candidateId);
    final songIds = b != null
        ? (b.isFinished ? b.songIds : const <String>[])
        : (j!.songId != null && (j.phase == FetchJobPhase.ready || j.phase == FetchJobPhase.duplicate)
            ? [j.songId!]
            : const <String>[]);
    final finished = b?.isFinished ?? j!.isFinished;
    final failed = b?.status == FetchBatchStatus.failed ||
        j?.phase == FetchJobPhase.failed ||
        j?.phase == FetchJobPhase.rejected;

    return Semantics(
      label: [title, subtitle, status].where((s) => s.isNotEmpty).join(', '),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.sm, Space.sm),
        child: Row(
          children: [
            CoverArt(
              url: cover,
              size: 44,
              radius: Radii.thumb,
              placeholderIcon: b == null ? NaviGlyph.note : NaviGlyph.library,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                    Text(status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.footnote.copyWith(color: failed ? t.danger : t.textMuted)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            if (songIds.isNotEmpty) ...[
              _IconAction(
                icon: NaviGlyph.playCircle,
                label: 'Play',
                onTap: () async {
                  await playSongs(songIds, name: b?.title);
                  if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
                },
              ),
              _IconAction(icon: NaviGlyph.addToPlaylist, label: 'Add to Playlist', onTap: () => addSongsToPlaylist(songIds)),
            ] else
              SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: finished && !failed
                      ? NaviIcon(NaviGlyph.checkCircle, size: 24, color: t.positive, filled: true)
                      : (b != null ? FetchBatchIndicator(batch: b) : FetchJobIndicator(job: j)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add several songs to a playlist
// ─────────────────────────────────────────────────────────────────────────────

/// Adds all of [songs] to a playlist the user picks (or a new one).
Future<void> showAddSongsToPlaylist(BuildContext context, List<Song> songs) => showPlatformSheet<void>(
      context: context,
      title: songs.length == 1 ? 'Add to Playlist' : 'Add ${songs.length} Songs to Playlist',
      builder: (_) => _AddSongsSheet(songs: songs),
    );

class _AddSongsSheet extends ConsumerStatefulWidget {
  final List<Song> songs;
  const _AddSongsSheet({required this.songs});

  @override
  ConsumerState<_AddSongsSheet> createState() => _AddSongsSheetState();
}

class _AddSongsSheetState extends ConsumerState<_AddSongsSheet> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addTo(String playlistId, String playlistName) async {
    setState(() => _busy = true);
    final svc = ref.read(subsonicServiceProvider);
    try {
      for (final s in widget.songs) {
        await svc.updatePlaylist(playlistId, songIdToAdd: s.id);
      }
      ref.invalidate(songsInPlaylistProvider(playlistId));
      ref.invalidate(playlistsProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text('Added ${widget.songs.length} songs to $playlistName')));
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, 'Couldn’t add the songs. Try again.');
      }
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final p = await ref.read(playlistControllerProvider).create(name);
      await _addTo(p.id, p.name);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, 'Couldn’t create the playlist. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final playlists = ref.watch(playlistsProvider).asData?.value ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
          child: CupertinoTextField(
            controller: _name,
            enabled: !_busy,
            placeholder: 'New Playlist',
            style: t.body.copyWith(color: t.textPrimary),
            placeholderStyle: t.body.copyWith(color: t.textMuted),
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm + 2),
            decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.control)),
            suffix: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              minimumSize: const Size(44, 36),
              onPressed: _busy ? null : _create,
              child: Text('Create', style: t.body.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
            ),
            onSubmitted: (_) => _create(),
          ),
        ),
        for (final p in playlists)
          InkWell(
            onTap: _busy ? null : () => _addTo(p.id, p.name),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.md),
              child: Row(
                children: [
                  NaviIcon(NaviGlyph.playlist, size: 20, color: t.textSecondary),
                  const SizedBox(width: Space.md),
                  Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body)),
                ],
              ),
            ),
          ),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}
