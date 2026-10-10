import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/hive_boxes.dart';
import '../models/album.dart';
import '../models/playlist.dart';

enum PinKind { album, playlist, artist }

/// Something pinned to the top of Library (iOS 26 Apple Music). Stores just
/// enough to draw the tile and open the page; device-local, never uploaded.
class Pin {
  final PinKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String coverArt;

  const Pin({required this.kind, required this.id, required this.title, this.subtitle = '', this.coverArt = ''});

  factory Pin.album(Album a) =>
      Pin(kind: PinKind.album, id: a.id, title: a.name, subtitle: a.artist, coverArt: a.coverArt);

  factory Pin.playlist(Playlist p) =>
      Pin(kind: PinKind.playlist, id: p.id, title: p.name, subtitle: 'Playlist', coverArt: p.coverArt ?? '');

  /// Artists are drawn from their portrait ('ar-' id), as Subsonic serves it.
  factory Pin.artist(String id, String name) =>
      Pin(kind: PinKind.artist, id: id, title: name, subtitle: 'Artist', coverArt: 'ar-$id');

  String get key => '${kind.name}:$id';

  Map<String, String> toMap() =>
      {'kind': kind.name, 'id': id, 'title': title, 'subtitle': subtitle, 'coverArt': coverArt};

  static Pin? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = PinKind.values.where((k) => k.name == raw['kind']).firstOrNull;
    final id = raw['id']?.toString() ?? '';
    if (kind == null || id.isEmpty) return null;
    return Pin(
      kind: kind,
      id: id,
      title: raw['title']?.toString() ?? '',
      subtitle: raw['subtitle']?.toString() ?? '',
      coverArt: raw['coverArt']?.toString() ?? '',
    );
  }
}

class PinsNotifier extends Notifier<List<Pin>> {
  /// Apple Music's limit, and what fits the Library grid without scrolling.
  static const max = 6;
  static const _hiveKey = 'library_pins';

  @override
  List<Pin> build() {
    final raw = HiveBoxes.prefs.get(_hiveKey);
    if (raw is! List) return const [];
    return [for (final r in raw) ?Pin.fromMap(r)];
  }

  bool isPinned(String key) => state.any((p) => p.key == key);

  /// Pins [pin], or unpins it if already pinned. Returns false when the
  /// library already holds [max] pins and nothing changed.
  bool toggle(Pin pin) {
    if (isPinned(pin.key)) {
      _save(state.where((p) => p.key != pin.key).toList());
      return true;
    }
    if (state.length >= max) return false;
    _save([pin, ...state]);
    return true;
  }

  void _save(List<Pin> pins) {
    state = pins;
    // Bookkeeping only: a failed write must not break the tap that caused it.
    HiveBoxes.prefs.put(_hiveKey, [for (final p in pins) p.toMap()]).ignore();
  }
}

final pinsProvider = NotifierProvider<PinsNotifier, List<Pin>>(PinsNotifier.new);
