import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../utils/format.dart';
import '../../widgets/desktop_dialogs.dart';
import 'song_trim.dart';
import 'song_trim_providers.dart';

/// "Start and end…" in the song menu: two handles over the song's length (R9).
Future<void> showSongTrimSheet(BuildContext context, Song song) =>
    showPlatformSheet(context: context, title: 'Start and End', builder: (_) => SongTrimSheet(song: song));

class SongTrimSheet extends ConsumerStatefulWidget {
  const SongTrimSheet({super.key, required this.song});
  final Song song;

  @override
  ConsumerState<SongTrimSheet> createState() => _SongTrimSheetState();
}

class _SongTrimSheetState extends ConsumerState<SongTrimSheet> {
  late double _start;
  late double _end; // seconds; == duration when there is no end point

  int get _dur => widget.song.duration;

  @override
  void initState() {
    super.initState();
    final t = ref.read(songTrimsProvider).of(widget.song.id);
    _start = t.startMs / 1000;
    _end = t.hasEnd ? t.endMs / 1000 : _dur.toDouble();
  }

  SongTrim get _trim => SongTrim(
    startMs: (_start * 1000).round(),
    endMs: _end >= _dur - 1 ? 0 : (_end * 1000).round(),
  ).normalized(_dur * 1000);

  Future<void> _save() async {
    await ref.read(songTrimsProvider.notifier).set(widget.song.id, _trim, durationSec: _dur);
    ref.read(playerProvider.notifier).trimChanged();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await ref.read(songTrimsProvider.notifier).clear(widget.song.id);
    ref.read(playerProvider.notifier).trimChanged();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    if (_dur < 10) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('This song is too short to trim.', textAlign: TextAlign.center),
      );
    }
    final isPlayingThis = ref.watch(playerProvider.select((s) => s.currentSong?.id == widget.song.id));
    final trim = _trim;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.song.title, style: t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: Space.md),
          RangeSlider(
            values: RangeValues(_start.clamp(0, _dur.toDouble()), _end.clamp(0, _dur.toDouble())),
            max: _dur.toDouble(),
            onChanged: (v) => setState(() {
              _start = v.start;
              _end = v.end;
            }),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(trim.hasStart ? 'Starts ${formatTrackDuration(trim.startMs ~/ 1000)}' : 'Starts at the beginning', style: t.footnote),
              Text(trim.hasEnd ? 'Ends ${formatTrackDuration(trim.endMs ~/ 1000)}' : 'Plays to the end', style: t.footnote),
            ],
          ),
          if (isPlayingThis) ...[
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, children: [
              TextButton(
                onPressed: () => setState(() {
                  _start = (ref.read(playerProvider.notifier).positionMs / 1000).floorToDouble().clamp(0, _end - 5);
                }),
                child: const Text('Start here'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _end = (ref.read(playerProvider.notifier).positionMs / 1000).floorToDouble().clamp(_start + 5, _dur.toDouble());
                }),
                child: const Text('End here'),
              ),
            ]),
          ],
          const SizedBox(height: Space.md),
          Row(
            children: [
              TextButton(onPressed: _reset, child: Text('Reset', style: t.body.copyWith(color: t.danger))),
              const Spacer(),
              TextButton(onPressed: _save, child: Text('Done', style: t.headline.copyWith(color: t.accent))),
            ],
          ),
        ],
      ),
    );
  }
}
