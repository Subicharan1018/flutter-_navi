import 'package:flutter_riverpod/flutter_riverpod.dart';

/// R3: "Don't count this". While on, music plays as usual but nothing about
/// it is recorded: no entry in the play log (so not in History, Replay,
/// Recap or stats), no Navidrome scrobble (play count, "recently played"),
/// and no feedback to the shuffle server (Flow, Smart Shuffle). For guests,
/// kids' songs and parties.
///
/// A session switch, not a setting: it is off again after the app restarts,
/// so a forgotten switch cannot silently hide a week of listening.
class DontCountNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool on) => state = on;
  void toggle() => state = !state;
}

final dontCountProvider = NotifierProvider<DontCountNotifier, bool>(DontCountNotifier.new);
