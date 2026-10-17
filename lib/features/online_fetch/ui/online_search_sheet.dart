import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/add_to_playlist_dialog.dart';
import '../../../widgets/desktop_dialogs.dart';
import '../../../widgets/ui/controls.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/fetch_models.dart';
import '../data/online_fetch_api.dart';
import '../logic/online_fetch_providers.dart';
import 'widgets/fetch_candidate_row.dart';

/// "Search online": find a song that isn't in the library, confirm it's the
/// right one, and add it (lossless only). Songs already owned are never
/// fetched — the server says so and offers them instead.
Future<void> showOnlineSearch(BuildContext context, String query) => showPlatformSheet<void>(
      context: context,
      maxHeight: 720,
      builder: (_) => OnlineSearchSheet(query: query),
    );

class OnlineSearchSheet extends ConsumerStatefulWidget {
  final String query;
  const OnlineSearchSheet({super.key, required this.query});

  @override
  ConsumerState<OnlineSearchSheet> createState() => _OnlineSearchSheetState();
}

class _OnlineSearchSheetState extends ConsumerState<OnlineSearchSheet> {
  late final _field = TextEditingController(text: widget.query);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(widget.query));
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _search(String query) {
    final q = query.trim();
    if (q.length < 2) return;
    _field.text = q;
    unawaited(ref.read(onlineSearchProvider.notifier).start(q));
  }

  Future<void> _play(Future<Song> Function() load) async {
    try {
      final song = await load();
      if (!mounted) return;
      Navigator.of(context).pop();
      await ref.read(playerProvider.notifier).setQueue([song], 0, playlistName: 'Search');
    } on Exception catch (e) {
      _toast(e is OnlineFetchException ? e.message : 'Couldn’t start playback. Try again.');
    }
  }

  Future<void> _addToPlaylist(FetchJob job) async {
    try {
      final song = await ref.read(fetchJobsProvider.notifier).songFor(job);
      if (mounted) await showAddToPlaylist(context, song);
    } on Exception catch (e) {
      _toast(e is OnlineFetchException ? e.message : 'Couldn’t load the song. Try again.');
    }
  }

  void _toast(String message) {
    if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = ref.watch(onlineSearchProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xs),
          child: Text('Search online', style: t.title3),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, 0),
          child: Text('Finds songs that aren’t in your library and adds them in lossless quality.',
              style: t.footnote),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
          child: NaviSearchField(
            controller: _field,
            placeholder: 'Song, film or artist',
            onSubmitted: _search,
          ),
        ),
        _ActiveDownloads(onPlay: _play, onAddToPlaylist: _addToPlaylist),
        _Body(state: s, onSearch: _search, onPlay: _play, onAddToPlaylist: _addToPlaylist),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  final OnlineSearchState state;
  final ValueChanged<String> onSearch;
  final Future<void> Function(Future<Song> Function() load) onPlay;
  final ValueChanged<FetchJob> onAddToPlaylist;

  const _Body({required this.state, required this.onSearch, required this.onPlay, required this.onAddToPlaylist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final search = s.search;
    final svc = ref.read(subsonicServiceProvider);
    Future<Song> owned(String id) => svc.getSong(id);

    if (s.error != null) {
      return MessageState.error(title: 'Search didn’t work', message: s.error!, onRetry: () => onSearch(s.query));
    }
    if (s.isLoading || search == null) {
      return const LoadingState(label: 'Searching online…');
    }
    switch (search.status) {
      case FetchSearchStatus.inLibrary:
        final m = search.libraryMatches.first;
        return MessageState(
          icon: CupertinoIcons.checkmark_circle,
          title: 'Already in your library',
          message: '${m.title} — ${m.artist}',
          actionLabel: 'Play',
          onAction: () => onPlay(() => owned(m.songId)),
        );
      case FetchSearchStatus.failed:
        return MessageState.error(
          title: 'Search didn’t work',
          message: search.error ?? 'Try again in a moment.',
          onRetry: () => onSearch(s.query),
        );
      case FetchSearchStatus.noResults when search.candidates.isEmpty:
        return MessageState(
          icon: CupertinoIcons.search,
          title: 'No match for “${search.query}”',
          message: 'Check the spelling, or add the film or artist name.',
        );
      default:
        return _Results(search: search, onSearch: onSearch, onPlay: onPlay, owned: owned, onAddToPlaylist: onAddToPlaylist);
    }
  }
}

class _Results extends ConsumerWidget {
  final FetchSearch search;
  final ValueChanged<String> onSearch;
  final Future<void> Function(Future<Song> Function() load) onPlay;
  final Future<Song> Function(String id) owned;
  final ValueChanged<FetchJob> onAddToPlaylist;

  const _Results({
    required this.search,
    required this.onSearch,
    required this.onPlay,
    required this.owned,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final weak = search.status == FetchSearchStatus.noResults;
    final ids = {for (final c in search.candidates) c.id};
    // The finished download from this search, if any, for the actions below.
    final done = ref.watch(fetchJobsProvider.select((jobs) => jobs.values
        .where((j) => ids.contains(j.candidateId) && j.songId != null &&
            (j.phase == FetchJobPhase.ready || j.phase == FetchJobPhase.duplicate))
        .lastOrNull));
    final dym = search.didYouMean;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dym != null && dym.toLowerCase() != search.query.toLowerCase())
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
            child: Semantics(
              button: true,
              label: 'Did you mean $dym? Search for it',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onSearch(dym),
                child: Text.rich(
                  TextSpan(style: t.subheadline, children: [
                    const TextSpan(text: 'Did you mean '),
                    TextSpan(text: dym, style: t.subheadline.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
                    const TextSpan(text: '?'),
                  ]),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xs),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(weak ? 'No close match — nearest results' : 'Is this the song?', style: t.headline),
                ),
              ),
              if (search.aiPending) ...[
                const CupertinoActivityIndicator(radius: 7),
                const SizedBox(width: Space.xs),
                Text('Checking', style: t.footnote),
              ],
            ],
          ),
        ),
        for (final (i, c) in search.candidates.indexed)
          FetchCandidateRow(
            candidate: c,
            showSeparator: i < search.candidates.length - 1,
            onDownload: () => ref.read(fetchJobsProvider.notifier).download(c.id),
            onPlayOwned: () => onPlay(() async {
              // The exact title + artist is owned; find it through the library search.
              final songs = (await ref.read(subsonicServiceProvider).search(c.title)).songs;
              final match = songs.where((s) => s.artist == c.artist).firstOrNull ?? songs.firstOrNull;
              if (match == null) throw const OnlineFetchException('Couldn’t find it in your library.');
              return match;
            }),
          ),
        if (done != null) _DoneActions(job: done, onPlay: onPlay, onAddToPlaylist: onAddToPlaylist),
      ],
    );
  }
}

/// Shown once a picked song is in the library: play it now or file it away.
class _DoneActions extends ConsumerWidget {
  final FetchJob job;
  final Future<void> Function(Future<Song> Function() load) onPlay;
  final ValueChanged<FetchJob> onAddToPlaylist;

  const _DoneActions({required this.job, required this.onPlay, required this.onAddToPlaylist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.read(fetchJobsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
      child: Row(
        children: [
          Expanded(
            child: TintedButton(
              icon: CupertinoIcons.play_fill,
              label: 'Play',
              filled: true,
              onTap: () => onPlay(() => jobs.songFor(job)),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: TintedButton(
              icon: CupertinoIcons.text_badge_plus,
              label: 'Add to Playlist',
              onTap: () => onAddToPlaylist(job),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active-download banner — survives sheet close/reopen
// ─────────────────────────────────────────────────────────────────────────────

/// Downloads started earlier (this sheet or a previous one) that aren't among
/// the results on screen, so closing and reopening the sheet never hides one.
/// Running and finished jobs show; failed ones are retried from their result
/// row, and a job whose result is listed below shows its progress there.
class _ActiveDownloads extends ConsumerWidget {
  final Future<void> Function(Future<Song> Function() load) onPlay;
  final ValueChanged<FetchJob> onAddToPlaylist;

  const _ActiveDownloads({required this.onPlay, required this.onAddToPlaylist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final listed = ref.watch(onlineSearchProvider.select(
        (s) => {for (final c in s.search?.candidates ?? const <FetchCandidate>[]) c.id}));
    final active = ref.watch(fetchJobsProvider.select((jobs) => [
          for (final j in jobs.values)
            if (j.phase != FetchJobPhase.failed && j.phase != FetchJobPhase.rejected && !listed.contains(j.candidateId)) j,
        ]));
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final job in active)
          _ActiveDownloadRow(job: job, onPlay: onPlay, onAddToPlaylist: onAddToPlaylist),
        Container(height: 0.5, color: t.outline, margin: const EdgeInsets.only(bottom: Space.sm)),
      ],
    );
  }
}

class _ActiveDownloadRow extends ConsumerWidget {
  final FetchJob job;
  final Future<void> Function(Future<Song> Function() load) onPlay;
  final ValueChanged<FetchJob> onAddToPlaylist;

  const _ActiveDownloadRow({
    required this.job,
    required this.onPlay,
    required this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final j = job;
    // Play / Add to Playlist need the library song, which a finished job names.
    final isFinished = j.songId != null &&
        (j.phase == FetchJobPhase.ready || j.phase == FetchJobPhase.duplicate);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.md, Space.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  j.title ?? 'Downloading…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body,
                ),
                if (j.artist != null && j.artist!.isNotEmpty)
                  Text(j.artist!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subheadline),
                Text(fetchJobStatus(j), style: t.footnote.copyWith(color: t.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          if (isFinished) ...[
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () => onPlay(() => ref.read(fetchJobsProvider.notifier).songFor(j)),
              child: Icon(CupertinoIcons.play_circle, size: 28, color: t.accent, semanticLabel: 'Play'),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () => onAddToPlaylist(j),
              child: Icon(CupertinoIcons.text_badge_plus, size: 26, color: t.accent, semanticLabel: 'Add to Playlist'),
            ),
          ] else
            SizedBox(width: 28, height: 28, child: Center(child: FetchJobIndicator(job: j))),
        ],
      ),
    );
  }
}
