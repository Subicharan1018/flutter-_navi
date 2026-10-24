import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../models/song.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../utils/queue_actions.dart';
import '../../../widgets/add_to_playlist_dialog.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/cover_art.dart';
import '../../../widgets/desktop_dialogs.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/media.dart';
import '../../online_fetch/logic/online_fetch_providers.dart';
import '../../online_fetch/ui/online_search_sheet.dart';
import '../data/recognize_models.dart';
import '../logic/recognize_controller.dart';

const _pad = EdgeInsets.symmetric(horizontal: Space.gutter);

/// "What's this song?": listens through the microphone for about eleven
/// seconds, asks the server, and offers what to do with the answer — play it
/// or queue it when it's in the library, fetch it when it isn't.
///
/// Actions run on [hostContext] (the screen that opened the sheet), because
/// the sheet itself is gone by the time they do.
Future<void> showRecognizeSheet(BuildContext hostContext) =>
    showPlatformSheet<void>(
      context: hostContext,
      maxHeight: 640,
      builder: (_) => RecognizeSheet(hostContext: hostContext),
    );

class RecognizeSheet extends ConsumerStatefulWidget {
  final BuildContext hostContext;
  const RecognizeSheet({super.key, required this.hostContext});

  @override
  ConsumerState<RecognizeSheet> createState() => _RecognizeSheetState();
}

class _RecognizeSheetState extends ConsumerState<RecognizeSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(recognizeProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recognizeProvider);
    final ctl = ref.read(recognizeProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Space.sm, 0, Space.xl),
      child: AnimatedSize(
        duration: Motion.fast,
        alignment: Alignment.topCenter,
        child: switch (state.phase) {
          RecognizePhase.idle => const SizedBox(height: 220),
          RecognizePhase.listening => _Listening(
            onCancel: () {
              ctl.cancel();
              Navigator.of(context).pop();
            },
          ),
          RecognizePhase.identifying => const _Identifying(),
          RecognizePhase.needsPermission => _Notice(
            title: 'Allow the microphone',
            message:
                'NaviVibe listens for about ten seconds to work out what’s playing. '
                'The recording is sent to your own server and deleted straight after.',
            actionLabel: 'Allow Microphone',
            onAction: ctl.start,
          ),
          RecognizePhase.blocked => _Notice(
            title: 'Microphone is off',
            message:
                'Turn on Microphone for NaviVibe in Settings to identify songs.',
            actionLabel: 'Open Settings',
            onAction: ctl.openSettings,
          ),
          RecognizePhase.notFound => _Notice(
            title: 'Couldn’t identify that',
            message:
                'Move closer to the music, turn it up a little and try again. '
                'Songs with a lot of talking or noise over them are hard to catch.',
            actionLabel: 'Try Again',
            onAction: ctl.start,
          ),
          RecognizePhase.failed => _Notice(
            title: 'Couldn’t identify songs right now',
            message: state.message ?? 'Try again in a moment.',
            actionLabel: 'Try Again',
            onAction: ctl.start,
          ),
          RecognizePhase.found => _Found(
            result: state.result!,
            hostContext: widget.hostContext,
            onAgain: ctl.start,
          ),
        },
      ),
    );
  }
}

/// The microphone is open: a quietly breathing disc around the mic glyph.
class _Listening extends StatefulWidget {
  final VoidCallback onCancel;
  const _Listening({required this.onCancel});

  @override
  State<_Listening> createState() => _ListeningState();
}

class _ListeningState extends State<_Listening>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    reduce ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: _pad,
      child: Semantics(
        liveRegion: true,
        label: 'Listening',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Space.md),
            SizedBox(
              width: 168,
              height: 168,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _RipplePainter(_c.value, t.textPrimary),
                  child: Center(
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.accent,
                      ),
                      child: Center(
                        child: NaviIcon(
                          NaviGlyph.mic,
                          size: 38,
                          color: t.onAccent,
                          filled: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text('Listening…', style: t.title3),
            const SizedBox(height: Space.xs),
            Text('Hold your phone near the music', style: t.subheadline),
            const SizedBox(height: Space.lg),
            TintedButton(label: 'Cancel', onTap: widget.onCancel),
          ],
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double t;
  final Color color;
  const _RipplePainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final radius = 42 + 42 * Curves.easeOut.transform(p);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.35 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t || old.color != color;
}

class _Identifying extends StatelessWidget {
  const _Identifying();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: _pad,
      child: SizedBox(
        height: 220,
        child: Semantics(
          liveRegion: true,
          label: 'Identifying',
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: Space.lg),
              Text('Identifying…', style: t.title3),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _Notice({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: _pad,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Space.lg),
          NaviIcon(NaviGlyph.mic, size: 36, color: t.textMuted),
          const SizedBox(height: Space.md),
          Text(title, style: t.title3, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          Text(message, style: t.subheadline, textAlign: TextAlign.center),
          const SizedBox(height: Space.xl),
          TintedButton(label: actionLabel, filled: true, onTap: onAction),
        ],
      ),
    );
  }
}

/// The answer: what it is, and what to do about it.
class _Found extends ConsumerWidget {
  final RecognizeResult result;
  final BuildContext hostContext;
  final VoidCallback onAgain;

  const _Found({
    required this.result,
    required this.hostContext,
    required this.onAgain,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final hit = result.library.firstOrNull;
    final song = hit == null
        ? null
        : ref.watch(recognizedSongProvider(hit.songId));
    final svc = ref.read(subsonicServiceProvider);
    final coverUrl = song?.asData?.value.coverArt.isNotEmpty == true
        ? svc.getCoverArtUrl(song!.asData!.value.coverArt)
        : null;
    final subtitle = [
      result.artist,
      result.album,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: _pad,
          child: Row(
            children: [
              if (hit != null) ...[
                CoverArt(url: coverUrl, size: 64, radius: Radii.cover),
                const SizedBox(width: Space.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Song identified', style: t.footnote),
                    const SizedBox(height: 2),
                    Text(
                      result.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.title3,
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.subheadline,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        if (hit != null)
          _LibraryActions(song: song!, hostContext: hostContext)
        else
          _NotInLibrary(result: result, hostContext: hostContext),
        const SizedBox(height: Space.xs),
        Center(
          child: TextButton(
            onPressed: onAgain,
            child: Text(
              'Identify another',
              style: t.body.copyWith(color: t.accent),
            ),
          ),
        ),
      ],
    );
  }
}

class _LibraryActions extends ConsumerWidget {
  final AsyncValue<Song> song;
  final BuildContext hostContext;
  const _LibraryActions({required this.song, required this.hostContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final s = song.asData?.value;
    if (song.hasError) {
      return Text(
        'It’s in your library, but couldn’t be loaded. Try again.',
        style: t.subheadline,
      );
    }
    Widget glyph(NaviGlyph g) => NaviIcon(g, size: 21, color: t.textPrimary);
    return SheetGroup(
      children: [
        SheetAction(
          label: 'Play Now',
          trailing: glyph(NaviGlyph.play),
          onTap: s == null
              ? null
              : () => ref
                    .read(playerProvider.notifier)
                    .setQueue([s], 0, playlistName: 'Identified song'),
        ),
        SheetAction(
          label: 'Play Next',
          trailing: glyph(NaviGlyph.queue),
          onTap: s == null ? null : () => _queue(ref, s, next: true),
        ),
        SheetAction(
          label: 'Play Last',
          trailing: glyph(NaviGlyph.queue),
          onTap: s == null ? null : () => _queue(ref, s, next: false),
        ),
        SheetAction(
          label: 'Add to Playlist…',
          trailing: glyph(NaviGlyph.addToPlaylist),
          onTap: s == null
              ? null
              : () {
                  if (hostContext.mounted) showAddToPlaylist(hostContext, s);
                },
        ),
      ],
    );
  }

  void _queue(WidgetRef ref, Song s, {required bool next}) {
    if (hostContext.mounted) queueSongs(hostContext, ref, [s], next: next);
  }
}

class _NotInLibrary extends ConsumerWidget {
  final RecognizeResult result;
  final BuildContext hostContext;
  const _NotInLibrary({required this.result, required this.hostContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final online = ref.watch(onlineFetchEnabledProvider).asData?.value ?? false;
    return Padding(
      padding: _pad,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            online
                ? 'It isn’t in your library yet.'
                : 'It isn’t in your library.',
            style: t.body,
            textAlign: TextAlign.center,
          ),
          if (online) ...[
            const SizedBox(height: Space.md),
            Center(
              child: TintedButton(
                label: 'Download',
                filled: true,
                onTap: () {
                  Navigator.of(context).pop();
                  if (hostContext.mounted) {
                    showOnlineSearch(hostContext, result.searchText);
                  }
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
