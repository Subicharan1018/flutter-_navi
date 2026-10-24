import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/desktop_dialogs.dart';
import '../../../widgets/ui/media.dart';
import '../../../widgets/ui/states.dart';
import '../data/fetch_models.dart';
import '../data/online_fetch_api.dart';
import '../logic/online_fetch_providers.dart';
import 'online_search_sheet.dart' show confirmFetchDownload;
import 'widgets/fetch_candidate_row.dart';

/// "Send a Playlist": paste a Deezer or Spotify playlist link, see its songs
/// (which you already have, which are new), and add the new ones in lossless
/// quality. The playlist then appears in your library under its own name,
/// owned and new songs together, in the playlist's order. Sending the same
/// link again later only adds what's new.
Future<void> showSendPlaylist(BuildContext context, {String? link}) => showPlatformSheet<void>(
      context: context,
      maxHeight: 720,
      builder: (_) => SendPlaylistSheet(link: link),
    );

/// The link sheet's own search (separate from Search online's, so opening
/// one over the other never mixes their results).
final sendPlaylistProvider =
    NotifierProvider.autoDispose<OnlineSearchController, OnlineSearchState>(OnlineSearchController.new);

class SendPlaylistSheet extends ConsumerStatefulWidget {
  final String? link;
  const SendPlaylistSheet({super.key, this.link});

  @override
  ConsumerState<SendPlaylistSheet> createState() => _SendPlaylistSheetState();
}

class _SendPlaylistSheetState extends ConsumerState<SendPlaylistSheet> {
  late final _field = TextEditingController(text: widget.link ?? '');

  /// The server refused the download (e.g. another link is still running).
  String? _startError;

  @override
  void initState() {
    super.initState();
    if ((widget.link ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(widget.link!));
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _send(String text) {
    if (text.trim().isEmpty) return;
    _field.text = text.trim();
    setState(() => _startError = null);
    unawaited(ref.read(sendPlaylistProvider.notifier).startLink(text));
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      setState(() => _startError = 'Nothing to paste. Copy the playlist’s link first.');
      return;
    }
    _send(text);
  }

  Future<void> _download(FetchSearch listed) async {
    final all = listed.candidates.length;
    final fresh = listed.candidates.where((c) => !c.inLibrary).length;
    final name = listed.title ?? 'Playlist';
    final ok = await confirmFetchDownload(
      context,
      title: fresh == 0 ? 'Make “$name”?' : 'Download “$name”?',
      count: fresh,
      note: 'It becomes the playlist “$name” in your library with all $all songs '
          '(${all - fresh} you already have).',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(fetchJobsProvider.notifier).downloadLink(listed);
    } on OnlineFetchException catch (e) {
      if (mounted) setState(() => _startError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = ref.watch(sendPlaylistProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xs),
          child: Text('Send a Playlist', style: t.title3),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xs, Space.gutter, 0),
          child: Text(
            'Paste a Deezer or Spotify playlist link. Songs you already have are kept; '
            'the rest are added in lossless quality, and it becomes a playlist in your library.',
            style: t.footnote,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.sm),
          child: CupertinoTextField(
            controller: _field,
            placeholder: 'https://open.spotify.com/playlist/…',
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.go,
            onSubmitted: _send,
            style: t.body.copyWith(color: t.textPrimary),
            placeholderStyle: t.body.copyWith(color: t.textMuted),
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm + 2),
            decoration: BoxDecoration(color: t.fill, borderRadius: BorderRadius.circular(Radii.control)),
            prefix: Padding(
              padding: const EdgeInsets.only(left: Space.md),
              child: Icon(CupertinoIcons.link, size: 18, color: t.textSecondary),
            ),
            suffix: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              minimumSize: const Size(44, 36),
              onPressed: _paste,
              child: Text('Paste', style: t.body.copyWith(color: t.accent, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        if (_startError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
            child: Text(_startError!, style: t.footnote.copyWith(color: t.danger)),
          ),
        _LinkBody(state: s, onRetry: () => _send(s.query), onDownload: _download),
        const SizedBox(height: Space.lg),
      ],
    );
  }
}

class _LinkBody extends ConsumerWidget {
  final OnlineSearchState state;
  final VoidCallback onRetry;
  final ValueChanged<FetchSearch> onDownload;
  const _LinkBody({required this.state, required this.onRetry, required this.onDownload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final s = state;
    final listed = s.search;
    if (s.query.isEmpty) return const SizedBox.shrink();
    if (s.error != null) {
      // A bad link: say why (retrying won't help). A good link that failed: retry.
      return playlistLinkProblem(s.query) == null
          ? MessageState.error(title: 'Can’t use this link', message: s.error!, onRetry: onRetry)
          : MessageState(icon: CupertinoIcons.link, title: 'Can’t use this link', message: s.error!);
    }
    if (s.isLoading || listed == null) return const LoadingState(label: 'Reading the playlist…');
    if (listed.status == FetchSearchStatus.failed) {
      return MessageState.error(
        title: 'Can’t use this link',
        message: listed.error ?? 'Try again in a moment.',
        onRetry: onRetry,
      );
    }
    if (listed.candidates.isEmpty) {
      return const MessageState(
        icon: CupertinoIcons.music_note_list,
        title: 'This playlist is empty',
        message: 'Add songs to it first, or try another link.',
      );
    }

    final songs = listed.candidates;
    final owned = songs.where((c) => c.inLibrary).length;
    final fresh = songs.length - owned;
    final batch = ref.watch(fetchJobsProvider.select((d) => d.batchFor(songs.first.id)));
    final started = batch != null && batch.status != FetchBatchStatus.failed;
    String n(int k) => k == 1 ? '1 song' : '$k songs';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
          child: Text(listed.title ?? 'Playlist', style: t.title2, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxs, Space.gutter, Space.md),
          child: Text(
            [n(songs.length), if (fresh > 0) '$fresh new', if (owned > 0) '$owned in your library'].join(' · '),
            style: t.subheadline,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
          child: TintedButton(
            icon: started ? null : CupertinoIcons.arrow_down,
            label: started
                ? fetchBatchStatus(batch)
                : (fresh == 0 ? 'Make Playlist' : 'Download ${fresh == 1 ? '1 New Song' : '$fresh New Songs'}'),
            filled: !started,
            onTap: started ? null : () => onDownload(listed),
          ),
        ),
        for (final (i, c) in songs.indexed)
          FetchCandidateRow(
            candidate: c,
            showSeparator: i < songs.length - 1,
            interactive: false,
            onDownload: () {},
            onPlayOwned: () {},
          ),
      ],
    );
  }
}
