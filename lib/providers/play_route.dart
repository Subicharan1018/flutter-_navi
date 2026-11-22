// =============================================================================
// Play routing — which of your devices a tap on a song or "Play" starts music on
//
// With one device it is always this one. With several signed in, a play started
// by a person goes where music is playing now (the active device, which this
// device then controls), unless they chose another device in the devices sheet
// or pressed "Play here". Code that drives the player by itself (restore,
// autoplay, Jam) never gets here: it has no touch behind it.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../services/session_sync_service.dart';
import 'remote_queue_provider.dart';

/// Where a play goes.
sealed class PlayRoute {
  const PlayRoute();
}

/// This device plays it (it takes playback if another device holds it).
class PlayHere extends PlayRoute {
  const PlayHere();
}

/// The device that plays now (a remote command; it changes its own queue).
class PlayOnHost extends PlayRoute {
  final String deviceId;
  const PlayOnHost(this.deviceId);
}

/// A connected device that is not playing: it loads the queue, then takes over.
class PlayOnOther extends PlayRoute {
  final String deviceId;
  const PlayOnOther(this.deviceId);
}

/// The one rule. [person]: a touch or key started this (nothing automatic is
/// routed). [here]: "Play here" / a Jam / an explicit local start. [chosenId]:
/// the device picked in the devices sheet, if any.
PlayRoute resolvePlayRoute({
  required String? myId,
  required String? activeId,
  required String? chosenId,
  required bool person,
  required bool here,
}) {
  if (!person || here || myId == null) return const PlayHere();
  if (chosenId != null) {
    if (chosenId == myId) return const PlayHere();
    return chosenId == activeId ? PlayOnHost(chosenId) : PlayOnOther(chosenId);
  }
  if (activeId != null && activeId != myId) return PlayOnHost(activeId);
  return const PlayHere();
}

/// The device picked in the devices sheet for new music (null: wherever music
/// plays now). It lasts until playback changes hands, so a choice never
/// outlives the situation it was made in.
final playTargetProvider = NotifierProvider<PlayTargetNotifier, String?>(PlayTargetNotifier.new);

class PlayTargetNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void choose(String? deviceId) => state = deviceId;
}

/// A line about where a play went, or why it didn't. [seq] makes the same
/// text twice show twice; [canPlayHere] adds a "Play here" action to the toast.
class PlayNotice {
  final String? message;
  final int seq;
  final bool canPlayHere;
  const PlayNotice({this.message, this.seq = 0, this.canPlayHere = false});
}

final playNoticeProvider = NotifierProvider<PlayNoticeNotifier, PlayNotice>(PlayNoticeNotifier.new);

class PlayNoticeNotifier extends Notifier<PlayNotice> {
  @override
  PlayNotice build() => const PlayNotice();

  void say(String message, {bool canPlayHere = false}) =>
      state = PlayNotice(message: message, seq: state.seq + 1, canPlayHere: canPlayHere);
}

/// What the last routed play carried, so "Play here" can start the same thing.
typedef RoutedPlay = ({List<Song> songs, int index, String? name});

/// A name for [deviceId] in the toast.
String deviceNameFor(SessionSyncService sync, String deviceId, {String? fallback}) {
  for (final d in sync.currentDevices) {
    if (d.id == deviceId) return d.name;
  }
  return fallback ?? 'your other device';
}

/// Sends [songs] (from [index]) to [route]'s device. Returns false when it
/// could not be sent (no link, or a server without `playOn`); the caller says so.
bool sendPlay(Ref ref, SessionSyncService sync, PlayRoute route, List<Song> songs, int index) {
  final ids = [for (final s in songs) s.id];
  switch (route) {
    case PlayHere():
      return false;
    case PlayOnHost():
      // The host replaces its own queue; the remote queue view shows the new
      // one at once and settles when the host reports it.
      final id = sync.sendCommand('set_queue', queue: ids, index: index);
      if (id == null) return false;
      ref.read(remoteQueueProvider.notifier).replace(songs, index, id);
      return true;
    case PlayOnOther(:final deviceId):
      final s = songs[index.clamp(0, songs.length - 1)];
      final id = sync.playOn(deviceId, ids, index, meta: {
        'track_title': s.title,
        'artist': s.artist,
        'album': s.album,
        if (s.coverArt.isNotEmpty) 'cover_art_id': s.coverArt,
        'duration_s': s.duration,
      });
      return id != null;
  }
}
