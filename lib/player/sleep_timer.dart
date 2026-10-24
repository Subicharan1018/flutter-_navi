import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../widgets/art/navi_icons.dart';

/// Sleep timer state. Lives at app scope so closing Now Playing (or the
/// whole player route) never silently cancels a timer the listener set.
class SleepTimerState {
  final DateTime? endsAt; // fixed-duration timer
  final bool endOfSong; // stop when the current song finishes

  const SleepTimerState({this.endsAt, this.endOfSong = false});

  bool get active => endsAt != null || endOfSong;

  Duration? remaining(DateTime now) {
    final e = endsAt;
    if (e == null) return null;
    final r = e.difference(now);
    return r.isNegative ? Duration.zero : r;
  }
}

class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _timer;
  String? _songAtArm;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen<Song?>(playerProvider.select((s) => s.currentSong), (prev, next) {
      if (state.endOfSong && next?.id != _songAtArm) {
        _stopPlayback();
      }
    });
    return const SleepTimerState();
  }

  void setMinutes(int minutes) {
    _timer?.cancel();
    final ends = DateTime.now().add(Duration(minutes: minutes));
    _timer = Timer(Duration(minutes: minutes), _stopPlayback);
    state = SleepTimerState(endsAt: ends);
  }

  void setEndOfSong() {
    _timer?.cancel();
    _songAtArm = ref.read(playerProvider).currentSong?.id;
    state = const SleepTimerState(endOfSong: true);
  }

  void cancel() {
    _timer?.cancel();
    state = const SleepTimerState();
  }

  void _stopPlayback() {
    _timer?.cancel();
    ref.read(playerProvider.notifier).pause();
    state = const SleepTimerState();
  }
}

final sleepTimerProvider = NotifierProvider<SleepTimerNotifier, SleepTimerState>(SleepTimerNotifier.new);

/// "Sleep timer" row for the ⋯ sheet: shows the live countdown when armed.
class SleepTimerTile extends ConsumerStatefulWidget {
  const SleepTimerTile({super.key});

  @override
  ConsumerState<SleepTimerTile> createState() => _SleepTimerTileState();
}

class _SleepTimerTileState extends ConsumerState<SleepTimerTile> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(sleepTimerProvider).endsAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final st = ref.watch(sleepTimerProvider);
    final rem = st.remaining(DateTime.now());
    final subtitle = st.endOfSong
        ? 'Stops at the end of this song'
        : rem != null
            ? 'Stops in ${rem.inMinutes}:${(rem.inSeconds % 60).toString().padLeft(2, '0')}'
            : 'Off';
    return ListTile(
      leading: NaviIcon(NaviGlyph.moon, color: st.active ? t.accent : t.textSecondary),
      title: const Text('Sleep timer'),
      subtitle: Text(subtitle),
      trailing: NaviIcon(NaviGlyph.chevron, color: t.textMuted),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => const _SleepTimerSheet(),
      ),
    );
  }
}

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final st = ref.watch(sleepTimerProvider);
    final n = ref.read(sleepTimerProvider.notifier);
    void done() => Navigator.of(context).pop();
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Stop playing in', style: naviText(20, FontWeight.w700, t.textPrimary)),
          ),
          for (final m in const [5, 15, 30, 45, 60, 90])
            ListTile(
              title: Text(m < 60 ? '$m minutes' : (m == 60 ? '1 hour' : '1 hour 30 minutes')),
              onTap: () {
                n.setMinutes(m);
                done();
              },
            ),
          ListTile(
            title: const Text('End of this song'),
            trailing: st.endOfSong ? NaviIcon(NaviGlyph.check, color: t.accent) : null,
            onTap: () {
              n.setEndOfSong();
              done();
            },
          ),
          if (st.active)
            ListTile(
              title: Text('Turn off timer', style: TextStyle(color: t.danger)),
              onTap: () {
                n.cancel();
                done();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
