import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/intent_response.dart';
import '../data/repositories/shuffle_exception.dart';
import 'shuffle_providers.dart';

/// "Describe a mix" on the Smart Shuffle screen.
class MixIntentState {
  final IntentResponse? result;
  final bool busy;
  final String? error;
  const MixIntentState({this.result, this.busy = false, this.error});

  bool get active => result != null;
}

/// Asks the server which library songs fit a sentence, then loads a preview
/// batch from /next restricted to them — so the queue is still ranked by your
/// own listening. Keep-alive: the preview batches live in the keep-alive
/// shuffle queue, and the "Tuned for …" line must stay with them.
class MixIntentController extends Notifier<MixIntentState> {
  @override
  MixIntentState build() => const MixIntentState();

  Future<void> apply(String text) async {
    final t = text.trim();
    if (t.length < 3 || state.busy) return;
    state = MixIntentState(result: state.result, busy: true);
    try {
      final res = await ref.read(shuffleRepositoryProvider).interpretIntent(t);
      if (!ref.mounted) return;
      if (!res.understood) {
        state = MixIntentState(
          result: state.result,
          error: 'Try a language, genre, artist, film or mood, like “calm Tamil melodies”.',
        );
        return;
      }
      if (res.candidates.isEmpty) {
        state = MixIntentState(result: state.result, error: 'Nothing in your library fits “$t” yet.');
        return;
      }
      final shuffle = ref.read(shuffleQueueProvider.notifier);
      shuffle.clearPreview();
      await shuffle.fetchNext(source: 'candidates', candidates: res.candidates, count: 16);
      if (ref.mounted) state = MixIntentState(result: res);
    } on ShuffleException catch (e) {
      if (ref.mounted) state = MixIntentState(result: state.result, error: e.message);
    } catch (_) {
      if (ref.mounted) {
        state = MixIntentState(result: state.result, error: 'Couldn’t build that mix. Try again.');
      }
    }
  }

  void reset() {
    if (state.active || state.error != null) state = const MixIntentState();
  }
}

final mixIntentProvider = NotifierProvider<MixIntentController, MixIntentState>(MixIntentController.new);
