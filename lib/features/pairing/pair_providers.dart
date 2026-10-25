import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../ai_shuffle/data/services/shuffle_api_service.dart' show createShuffleDio;
import 'pair_relay.dart';

/// The pairing mailbox on the shuffle server. Signed-in calls (the phone's)
/// carry the saved credentials; before sign-in (the TV's) they're empty and no
/// auth header is sent, which is all the TV's two routes need.
final pairRelayProvider = Provider<PairRelay>((ref) {
  return HttpPairRelay(createShuffleDio(() {
    final s = ref.read(settingsProvider);
    return (s.username, s.password);
  }, logTag: 'Pair'));
});
