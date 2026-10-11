import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../core/album_palette.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';

/// A cover reduced to what the player surfaces need: a 64px texture for the
/// artwork field shader and the derived [AlbumPalette].
class ArtworkData {
  final String key;
  final ui.Image image;
  final AlbumPalette palette;

  const ArtworkData({required this.key, required this.image, required this.palette});
}

/// Cache key shared with every `CachedNetworkImage` showing this cover, so the
/// thumbnail decode reuses the bytes the list/mini player already downloaded.
String coverCacheKey(Song song) =>
    'cover_${song.coverArt.isNotEmpty ? song.coverArt : song.id}';

/// Test seam: when set, every player surface resolves covers through this
/// instead of the network cache (golden tests point it at local files).
@visibleForTesting
ImageProvider Function(String url, String cacheKey)? debugCoverImageOverride;

/// [debugCoverImageOverride] for widgets outside this library (list covers).
ImageProvider? testCoverOverride(String url) => debugCoverImageOverride?.call(url, url);

/// The one way player surfaces load a cover: disk-cached network image,
/// decoded at [cacheWidth] px wide so a 3000px cover never sits in RAM at
/// full size.
ImageProvider coverImage(String url, String cacheKey, {int? cacheWidth}) {
  final base = debugCoverImageOverride?.call(url, cacheKey) ??
      CachedNetworkImageProvider(url, cacheKey: cacheKey);
  return cacheWidth == null ? base : ResizeImage(base, width: cacheWidth, policy: ResizeImagePolicy.fit);
}

/// A cover with a quiet placeholder, a short fade on first decode, and no
/// flicker when the song changes (gapless).
class CoverImage extends StatelessWidget {
  final String url;
  final String cacheKey;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final Color placeholderColor;

  const CoverImage({
    super.key,
    required this.url,
    required this.cacheKey,
    this.width,
    this.height,
    this.cacheWidth,
    this.placeholderColor = const Color(0x22FFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    final cw = cacheWidth ?? (width != null ? (width! * dpr).round() : null);
    return Image(
      image: coverImage(url, cacheKey, cacheWidth: cw),
      width: width,
      height: height,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 180),
          child: Container(color: placeholderColor, width: width, height: height, child: child),
        );
      },
      errorBuilder: (context, _, _) => Container(
        width: width,
        height: height,
        color: placeholderColor,
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          color: const Color(0x99FFFFFF),
          size: ((width ?? 48) * 0.36).clamp(14.0, 96.0),
        ),
      ),
    );
  }
}

/// Decodes covers once at 64×64, extracts their palette off the UI isolate,
/// and keeps the most recent results (LRU). Everything that colours itself by
/// the album goes through here, so a cover is never decoded twice.
class ArtworkRepository {
  ArtworkRepository._();
  static final ArtworkRepository instance = ArtworkRepository._();

  static const int _capacity = 40;
  static const int _texSize = 64;

  final LinkedHashMap<String, ArtworkData> _cache = LinkedHashMap();
  final Map<String, Future<ArtworkData?>> _inFlight = {};

  ArtworkData? peek(String key) {
    final hit = _cache.remove(key);
    if (hit != null) _cache[key] = hit; // promote
    return hit;
  }

  Future<ArtworkData?> load(String key, String url) {
    final hit = peek(key);
    if (hit != null) return SynchronousFuture(hit);
    // Block body on purpose: `=> _inFlight.remove(key)` would return the
    // in-flight future itself, and whenComplete waits on a returned future —
    // so every load waited on itself and never completed (an empty player
    // background and no album colours, with no error and no timeout).
    return _inFlight[key] ??= _load(key, url).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<ArtworkData?> _load(String key, String url) async {
    try {
      final data = debugCoverImageOverride != null ? await _loadViaGpu(key, url) : await _loadViaServer(key, url);
      _cache[key] = data;
      // Evicted entries are dropped, not disposed: an evicted image may still
      // be on screen (the playing song's field and cover after browsing 40
      // other covers), and disposing it blanked Now Playing until the next
      // song. 64×64 images are tiny; they are freed once nothing holds them.
      while (_cache.length > _capacity) {
        _cache.remove(_cache.keys.first);
      }
      return data;
    } catch (e) {
      debugPrint('[Artwork] $key failed: $e');
      return null;
    }
  }

  static const Duration _stepTimeout = Duration(seconds: 15);

  /// The device path: the server resizes the cover to [_texSize] px (a few
  /// KB instead of the full cover), it is cached on disk, decoded to RGBA on
  /// a background isolate, and uploaded to the GPU as the shader texture.
  /// No GPU pixel readback anywhere: `Image.toByteData` hangs forever on
  /// some Impeller (Vulkan) devices, which left the field empty.
  Future<ArtworkData> _loadViaServer(String key, String url) async {
    final thumbUrl = _thumbUrl(url);
    final file = await DefaultCacheManager()
        .getSingleFile(thumbUrl, key: '${key}_$_texSize')
        .timeout(_stepTimeout);
    final encoded = await file.readAsBytes();
    // One background job decodes and reads the palette, so the pixels never
    // make a second trip between isolates after they're handed to the GPU.
    final (rgba, ints) = await compute(_decodeThumb, encoded).timeout(_stepTimeout);
    final image = await _imageFromPixels(rgba).timeout(_stepTimeout);
    return ArtworkData(key: key, image: image, palette: albumPaletteFromInts(ints));
  }

  /// Asks Subsonic's getCoverArt for a server-side resize.
  static String _thumbUrl(String url) {
    final uri = Uri.parse(url);
    if (!uri.path.contains('getCoverArt')) return url;
    return uri.replace(queryParameters: {...uri.queryParameters, 'size': '$_texSize'}).toString();
  }

  static Future<ui.Image> _imageFromPixels(Uint8List rgba) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, _texSize, _texSize, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  /// Test path (golden fixtures supply covers through an ImageProvider; the
  /// software renderer used in tests reads pixels back without trouble).
  Future<ArtworkData> _loadViaGpu(String key, String url) async {
    final provider = ResizeImage(
      debugCoverImageOverride!.call(url, key),
      width: _texSize,
      height: _texSize,
      policy: ResizeImagePolicy.exact,
    );
    final image = await _resolve(provider);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba).timeout(_stepTimeout);
    final ints = await compute(extractAlbumPalette, bytes!.buffer.asUint8List());
    return ArtworkData(key: key, image: image, palette: albumPaletteFromInts(ints));
  }

  Future<ui.Image> _resolve(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        // Clone: the stream may dispose its handle once we stop listening.
        if (!completer.isCompleted) completer.complete(info.image.clone());
        info.dispose();
        stream.removeListener(listener);
      },
      onError: (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 20));
  }
}

/// Background-isolate decode of the (already small) cover into exactly
/// 64×64 RGBA, the size the shader samples, plus its palette, in one job.
(Uint8List, List<int>) _decodeThumb(Uint8List encoded) {
  const size = ArtworkRepository._texSize;
  final decoded = img.decodeImage(encoded);
  if (decoded == null) throw const FormatException('cover is not a decodable image');
  final square = img.copyResize(decoded, width: size, height: size, interpolation: img.Interpolation.average);
  final rgba = Uint8List.fromList(square.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba));
  return (rgba, extractAlbumPalette(rgba));
}

/// The artwork of the song that is playing now. Holds on to the previous
/// song's artwork until the next one is decoded, so surfaces never flash to
/// the fallback between tracks.
class NowPlayingArtworkNotifier extends Notifier<ArtworkData?> {
  String? _requestedKey;

  @override
  ArtworkData? build() {
    ref.listen<Song?>(
      playerProvider.select((s) => s.currentSong),
      (_, song) => _sync(song),
      fireImmediately: true,
    );
    return null;
  }

  void _sync(Song? song) {
    if (song == null) return;
    final key = coverCacheKey(song);
    if (key == _requestedKey) return;
    _requestedKey = key;
    final cached = ArtworkRepository.instance.peek(key);
    if (cached != null) {
      // build() may still be running on the first sync — defer the write.
      scheduleMicrotask(() {
        if (_requestedKey == key) state = cached;
      });
      return;
    }
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    _load(key, url, retriesLeft: _retries);
  }

  static const int _retries = 2;
  static const Duration _retryDelay = Duration(seconds: 2);

  /// A failed load (network busy while a new mix starts) is retried, and if
  /// it still fails the key is forgotten so the next sync tries again —
  /// previously the song stayed on the old artwork until a skip.
  void _load(String key, String url, {required int retriesLeft}) {
    ArtworkRepository.instance.load(key, url).then((data) {
      if (_requestedKey != key) return;
      if (data != null) {
        state = data;
      } else if (retriesLeft > 0) {
        Future.delayed(_retryDelay, () {
          if (_requestedKey == key) _load(key, url, retriesLeft: retriesLeft - 1);
        });
      } else {
        _requestedKey = null;
      }
    });
  }
}

final nowPlayingArtworkProvider =
    NotifierProvider<NowPlayingArtworkNotifier, ArtworkData?>(NowPlayingArtworkNotifier.new);

/// The palette the whole app is tinted with right now.
final albumPaletteProvider = Provider<AlbumPalette>(
  (ref) => ref.watch(nowPlayingArtworkProvider.select((a) => a?.palette)) ?? AlbumPalette.fallback,
);

/// Palette for any cover (album pages, playlist headers), keyed by the
/// Subsonic coverArt id. Loads lazily, shares the repository cache.
final coverPaletteProvider = FutureProvider.family<AlbumPalette, String>((ref, coverArt) async {
  final url = ref.read(subsonicServiceProvider).getCoverArtUrl(coverArt);
  final data = await ArtworkRepository.instance.load('cover_$coverArt', url);
  return data?.palette ?? AlbumPalette.fallback;
});
