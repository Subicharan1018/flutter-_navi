import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/desktop_dialogs.dart';
import '../../../widgets/ui/controls.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/fetch_models.dart';
import '../data/online_fetch_api.dart';
import '../logic/online_fetch_providers.dart';
import 'fetch_activity.dart';
import 'widgets/fetch_candidate_row.dart';

/// "Search online": find songs, albums, artists or playlists that aren't in
/// the library, confirm it's the right one, and add it (lossless only).
/// Songs already owned are never fetched — the server says so and offers
/// them instead. Several songs can be picked and downloaded together;
/// downloads carry on (and are followed app-wide) after the sheet closes.
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
  FetchSearchType _type = FetchSearchType.song;

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
    unawaited(ref.read(onlineSearchProvider.notifier).start(q, type: _type));
  }

  void _setType(FetchSearchType type) {
    setState(() => _type = type);
    _search(_field.text);
  }

  Future<void> _play(Future<Song> Function() load) async {
    try {
      final song = await load();
      if (!mounted) return;
      Navigator.of(context).pop();
      await ref.read(playerProvider.notifier).setQueue([song], 0, playlistName: 'Search');
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(e is OnlineFetchException ? e.message : 'Couldn’t start playback. Try again.'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = ref.watch(onlineSearchProvider);
    final inArtist = s.artist != null;

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
          child: Text('Finds music that isn’t in your library and adds it in lossless quality.', style: t.footnote),
        ),
        if (!inArtist) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
            child: NaviSearchField(
              controller: _field,
              placeholder: _type.placeholder,
              onSubmitted: _search,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
            child: NaviSegmented<FetchSearchType>(
              segments: {for (final ty in FetchSearchType.values) ty: ty.label},
              value: _type,
              onChanged: _setType,
            ),
          ),
        ] else
          _ArtistHeader(state: s),
        const _ActiveDownloads(),
        _Body(state: s, onSearch: _search, onPlay: _play),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

/// "‹ Artists" back to the artist results, the artist's name, and a button
/// for all of their top songs at once.
class _ArtistHeader extends ConsumerWidget {
  final OnlineSearchState state;
  const _ArtistHeader({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final artist = state.artist!;
    final batch = ref.watch(fetchJobsProvider.select((d) => d.batchFor(artist.id)));
    final songs = state.search?.candidates ?? const <FetchCandidate>[];
    final busy = batch != null && batch.status != FetchBatchStatus.failed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.gutter, Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              minimumSize: const Size(44, 44),
              onPressed: () => ref.read(onlineSearchProvider.notifier).back(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.chevron_left, size: 20, color: t.accent),
                  const SizedBox(width: 2),
                  Text('Artists', style: t.body.copyWith(color: t.accent)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: Space.sm),
            child: Text(artist.title, style: t.title2, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          if (songs.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Padding(
              padding: const EdgeInsets.only(left: Space.sm),
              child: TintedButton(
                icon: busy ? null : CupertinoIcons.arrow_down,
                label: busy ? fetchBatchStatus(batch) : 'Download Top Songs',
                filled: !busy,
                onTap: busy ? null : () => ref.read(fetchJobsProvider.notifier).downloadAll([artist]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final OnlineSearchState state;
  final ValueChanged<String> onSearch;
  final Future<void> Function(Future<Song> Function() load) onPlay;

  const _Body({required this.state, required this.onSearch, required this.onPlay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final search = s.search;
    final svc = ref.read(subsonicServiceProvider);

    if (s.error != null) {
      return MessageState.error(title: 'Search didn’t work', message: s.error!, onRetry: () => onSearch(s.query));
    }
    if (s.isLoading || search == null) {
      return LoadingState(label: s.artist != null ? 'Getting ${s.artist!.title}’s songs…' : 'Searching online…');
    }
    switch (search.status) {
      case FetchSearchStatus.inLibrary:
        final m = search.libraryMatches.first;
        return MessageState(
          icon: CupertinoIcons.checkmark_circle,
          title: 'Already in your library',
          message: '${m.title} — ${m.artist}',
          actionLabel: 'Play',
          onAction: () => onPlay(() => svc.getSong(m.songId)),
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
          message: s.type == FetchSearchType.song
              ? 'Check the spelling, or add the film or artist name.'
              : 'Check the spelling, or try Songs.',
        );
      default:
        return _Results(state: s, onSearch: onSearch, onPlay: onPlay);
    }
  }
}

class _Results extends ConsumerStatefulWidget {
  final OnlineSearchState state;
  final ValueChanged<String> onSearch;
  final Future<void> Function(Future<Song> Function() load) onPlay;

  const _Results({required this.state, required this.onSearch, required this.onPlay});

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  /// Non-null while picking several songs.
  Set<int>? _picked;

  @override
  void didUpdateWidget(_Results old) {
    super.didUpdateWidget(old);
    // A new search (or the artist view) starts out of select mode.
    if (old.state.search?.id != widget.state.search?.id) _picked = null;
  }

  FetchSearch get _search => widget.state.search!;

  void _toggle(FetchCandidate c) {
    HapticFeedback.selectionClick();
    setState(() => _picked!.contains(c.id) ? _picked!.remove(c.id) : _picked!.add(c.id));
  }

  void _downloadPicked() {
    final picks = [for (final c in _search.candidates) if (_picked!.contains(c.id)) c];
    ref.read(fetchJobsProvider.notifier).downloadAll(picks);
    setState(() => _picked = null);
  }

  Future<void> _downloadCollection(FetchCandidate c) async {
    final n = c.trackCount;
    if (n != null && n > 1) {
      final kind = c.type == FetchSearchType.playlist ? 'playlist' : 'album';
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final t = ThemeTokens.of(ctx);
          return AlertDialog(
            title: Text('Download ${c.title}?', textAlign: TextAlign.center),
            content: Text(
              'Adds the $kind’s $n songs in lossless quality. Songs you already have are skipped.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: t.body.copyWith(color: t.accent)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Download', style: t.headline.copyWith(color: t.accent)),
              ),
            ],
          );
        },
      );
      if (ok != true) return;
    }
    await ref.read(fetchJobsProvider.notifier).downloadAll([c]);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = widget.state;
    final search = _search;
    final weak = search.status == FetchSearchStatus.noResults;
    final songs = s.listsSongs;
    final picked = _picked;
    // Songs that can still be picked: not owned, not already on their way.
    final downloads = ref.watch(fetchJobsProvider);
    final pickable = [
      for (final c in search.candidates)
        if (c.isSong && !c.inLibrary && (downloads.jobFor(c.id)?.phase ?? FetchJobPhase.failed) == FetchJobPhase.failed) c.id,
    ];
    final dym = search.didYouMean;
    final heading = switch (s.type) {
      _ when s.artist != null => 'Top songs',
      _ when weak => 'No close match — nearest results',
      FetchSearchType.song => 'Is this the song?',
      FetchSearchType.album => 'Albums',
      FetchSearchType.artist => 'Artists',
      FetchSearchType.playlist => 'Playlists',
    };

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
                onTap: () => widget.onSearch(dym),
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
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.sm, Space.xs),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    picked == null ? heading : (picked.isEmpty ? 'Select songs' : '${picked.length} selected'),
                    style: t.headline,
                  ),
                ),
              ),
              if (search.aiPending && picked == null) ...[
                const CupertinoActivityIndicator(radius: 7),
                const SizedBox(width: Space.xs),
                Text('Checking', style: t.footnote),
              ],
              if (songs && pickable.length > 1)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                  minimumSize: const Size(44, 44),
                  onPressed: () => setState(() => _picked = picked == null ? <int>{} : null),
                  child: Text(picked == null ? 'Select' : 'Cancel', style: t.body.copyWith(color: t.accent)),
                ),
            ],
          ),
        ),
        if (picked != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: TintedButton(
                    label: picked.length == pickable.length ? 'Select None' : 'Select All',
                    onTap: () => setState(() => _picked = picked.length == pickable.length ? <int>{} : {...pickable}),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: TintedButton(
                    icon: CupertinoIcons.arrow_down,
                    label: picked.isEmpty ? 'Download' : 'Download ${picked.length == 1 ? '1 Song' : '${picked.length} Songs'}',
                    filled: true,
                    onTap: picked.isEmpty ? null : _downloadPicked,
                  ),
                ),
              ],
            ),
          ),
        for (final (i, c) in search.candidates.indexed)
          FetchCandidateRow(
            candidate: c,
            showSeparator: i < search.candidates.length - 1,
            selected: picked == null || !c.isSong ? null : picked.contains(c.id),
            onDownload: () {
              if (picked != null) {
                _toggle(c);
              } else if (c.isSong) {
                ref.read(fetchJobsProvider.notifier).download(c.id, coverUrl: c.coverUrl);
              } else if (c.type == FetchSearchType.artist) {
                ref.read(onlineSearchProvider.notifier).openArtist(c);
              } else {
                _downloadCollection(c);
              }
            },
            onPlayOwned: () => widget.onPlay(() async {
              // The exact title + artist is owned; find it through the library search.
              final songs = (await ref.read(subsonicServiceProvider).search(c.title)).songs;
              final match = songs.where((s) => s.artist == c.artist).firstOrNull ?? songs.firstOrNull;
              if (match == null) throw const OnlineFetchException('Couldn’t find it in your library.');
              return match;
            }),
          ),
        _DoneActions(listed: [for (final c in search.candidates) c.id]),
      ],
    );
  }
}

/// Once a picked song or album from these results is in the library: play it
/// now or file it away. (The app-wide pop-up sits behind this sheet.)
class _DoneActions extends ConsumerStatefulWidget {
  final List<int> listed;
  const _DoneActions({required this.listed});

  @override
  ConsumerState<_DoneActions> createState() => _DoneActionsState();
}

class _DoneActionsState extends ConsumerState<_DoneActions> with FetchSongActions {
  @override
  Widget build(BuildContext context) {
    final ids = ref.watch(fetchJobsProvider.select((d) {
      // The newest finished download among the listed results.
      for (final b in d.batches.values.toList().reversed) {
        if (b.status == FetchBatchStatus.done && b.songIds.isNotEmpty && b.candidateIds.any(widget.listed.contains)) {
          return (b.songIds, b.title);
        }
      }
      final job = d.jobs.values
          .where((j) =>
              widget.listed.contains(j.candidateId) &&
              j.songId != null &&
              (j.phase == FetchJobPhase.ready || j.phase == FetchJobPhase.duplicate))
          .lastOrNull;
      return job == null ? null : ([job.songId!], null);
    }));
    if (ids == null) return const SizedBox.shrink();
    final (songIds, name) = ids;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
      child: Row(
        children: [
          Expanded(
            child: TintedButton(
              icon: CupertinoIcons.play_fill,
              label: 'Play',
              filled: true,
              onTap: () async {
                await playSongs(songIds, name: name);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: TintedButton(
              icon: CupertinoIcons.text_badge_plus,
              label: 'Add to Playlist',
              onTap: () => addSongsToPlaylist(songIds),
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
/// A download whose result is listed below shows its progress there instead.
class _ActiveDownloads extends ConsumerWidget {
  const _ActiveDownloads();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final listed = ref.watch(onlineSearchProvider.select(
        (s) => {for (final c in s.search?.candidates ?? const <FetchCandidate>[]) c.id, ?s.artist?.id}));
    final d = ref.watch(fetchJobsProvider);
    // Failed single songs are retried from their result row; keep them out.
    final shown = FetchDownloads(
      jobs: {
        for (final e in d.jobs.entries)
          if (e.value.phase != FetchJobPhase.failed && e.value.phase != FetchJobPhase.rejected) e.key: e.value,
      },
      batches: d.batches,
    );
    final list = FetchDownloadsList(downloads: shown, hideCandidates: listed);
    final anything = shown.jobs.keys.any((id) => !listed.contains(id)) ||
        shown.batches.values.any((b) => !b.candidateIds.every(listed.contains));
    if (!anything) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        list,
        Container(height: 0.5, color: t.outline, margin: const EdgeInsets.only(bottom: Space.sm)),
      ],
    );
  }
}
