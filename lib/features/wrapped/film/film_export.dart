import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../utils/platform_utils.dart';
import 'film.dart';

/// A stretch of film: scene [index] from 0 to [until] seconds, played over [seconds] of video.
class FilmClip {
  final int index;
  final double until;
  final double seconds;
  const FilmClip(this.index, this.until, this.seconds);
}

/// One scene at its own pace.
List<FilmClip> sceneClip(WrappedFilm film, int index) => [FilmClip(index, film.scenes[index].length, film.scenes[index].length)];

/// The scenes that make the one-minute cut.
const _highlights = ['intro', 'minutes', 'number-one', 'top5', 'artists', 'genres', 'clock', 'journey', 'obsession', 'languages', 'era', 'streak', 'best-day', 'personality', 'finale'];

/// The film's highlights inside a minute, the longest an Instagram story runs.
List<FilmClip> wholeFilm(WrappedFilm film) {
  final picks = [
    for (var i = 0; i < film.scenes.length; i++)
      if (_highlights.contains(film.scenes[i].id)) i,
  ];
  final each = math.min(4.4, 59 / math.max(1, picks.length));
  return [for (final i in picks) FilmClip(i, math.min(film.scenes[i].length, film.scenes[i].still + 0.5), each)];
}

ui.Picture _record(WrappedFilm film, Size size, {required int index, required double t, int? from, double fromT = 0, String? name}) {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  film.paint(canvas, size, index: index, t: t, from: from, fromT: fromT, name: name);
  if (film.scenes[index].id != 'finale' && film.scenes[index].id != 'discovery') {
    // the sleeve and the receipt carry their own mark; every other scene gets the small one
    final u = size.width / 360;
    final mark = film.words('NaviVibe', 14 * u, weight: ui.FontWeight.w700);
    mark.paint(canvas, ui.Offset(size.width / 2 - mark.width / 2, size.height - 34 * u));
  }
  return rec.endRecording();
}

/// Scene [index] at its best moment as a PNG: 1080 x 1920, or 1080 x 1080 when [square].
Future<Uint8List> renderStill(WrappedFilm film, int index, {String? name, bool square = false}) async {
  final pic = _record(film, square ? const Size(1080, 1080) : const Size(1080, 1920), index: index, t: film.scenes[index].still, name: name);
  final image = await pic.toImage(1080, square ? 1080 : 1920);
  pic.dispose();
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Where frames go. The phone's own hardware encoder in the app; a list in a test.
abstract class FrameSink {
  Future<void> start(int width, int height, int fps, String name);
  Future<void> add(Uint8List rgba);
  Future<String> finish();
  Future<void> cancel();
}

class ExportCancelled implements Exception {}

const filmFps = 24;
const filmVideoSize = Size(720, 1280);

/// Frames drawn ahead of the encoder: drawing, reading back and encoding run side by side.
const _ahead = 3;

/// Renders [clips] frame by frame into [sink] and returns the file. Frame n always shows the same moment, however slow
/// the phone, and frames always arrive in order.
Future<String> renderVideo(
  WrappedFilm film,
  List<FilmClip> clips,
  FrameSink sink, {
  String? name,
  String fileName = 'navivibe_wrapped',
  void Function(double)? onProgress,
  bool Function()? cancelled,
  Size size = filmVideoSize,
}) async {
  final total = clips.fold<int>(0, (a, c) => a + (c.seconds * filmFps).round());
  final clock = Stopwatch()..start();
  final w = size.width.round(), h = size.height.round();
  var done = 0;

  Future<Uint8List> read(ui.Picture pic) async {
    final image = await pic.toImage(w, h);
    pic.dispose();
    try {
      return (await image.toByteData())!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  final reading = <Future<Uint8List>>[];
  Future<void>? sending;
  Object? failed;
  Future<void> send() async {
    final bytes = await reading.removeAt(0);
    await sending;
    if (failed != null) throw failed!;
    sending = sink
        .add(bytes)
        .then((_) {
          onProgress?.call(++done / total);
        })
        .catchError((Object e) {
          failed = e;
        });
  }

  try {
    await sink.start(w, h, filmFps, fileName);
    for (var k = 0; k < clips.length; k++) {
      final c = clips[k];
      final frames = (c.seconds * filmFps).round();
      for (var i = 0; i < frames; i++) {
        if (cancelled?.call() ?? false) throw ExportCancelled();
        final t = c.until * i / math.max(1, frames - 1);
        reading.add(read(_record(film, size, index: c.index, t: t, from: k == 0 ? null : clips[k - 1].index, fromT: k == 0 ? 0 : clips[k - 1].until, name: name)));
        if (reading.length >= _ahead) await send();
      }
    }
    while (reading.isNotEmpty) {
      await send();
    }
    await sending;
    if (failed != null) throw failed!;
    final path = await sink.finish();
    debugPrint('[Wrapped] video $total frames in ${clock.elapsedMilliseconds} ms (${(clock.elapsedMilliseconds / math.max(1, total)).toStringAsFixed(1)} ms a frame)');
    return path;
  } catch (_) {
    for (final r in reading) {
      unawaited(r.then((_) {}, onError: (_) {}));
    }
    await sending;
    await sink.cancel();
    rethrow;
  }
}

/// The Android side: the hardware H.264 encoder, the gallery, and sending straight to one app.
class AndroidFilm implements FrameSink {
  static const _channel = MethodChannel('com.navivibe/wrapped');
  const AndroidFilm();

  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && !PlatformUtils.isTv;

  @override
  Future<void> start(int width, int height, int fps, String name) => _channel.invokeMethod<void>('start', {'width': width, 'height': height, 'fps': fps, 'name': name});
  @override
  Future<void> add(Uint8List rgba) => _channel.invokeMethod<void>('frame', rgba);
  @override
  Future<String> finish() async => (await _channel.invokeMethod<String>('finish'))!;
  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on PlatformException {
      // nothing was running
    }
  }

  /// Puts a PNG where other apps may read it, and returns the file.
  static Future<String> keep(Uint8List png, String name) async => (await _channel.invokeMethod<String>('keep', {'bytes': png, 'name': name}))!;

  /// Opens [package]'s own share screen with [paths]; false when that app is not on the phone.
  static Future<bool> sendTo(String package, List<String> paths, String mime) async =>
      await _channel.invokeMethod<bool>('sendTo', {'package': package, 'paths': paths, 'mime': mime}) ?? false;

  /// Saves into the phone's gallery; false where the phone is too old to do it without asking for storage.
  static Future<bool> save(List<String> paths, String mime) async => await _channel.invokeMethod<bool>('save', {'paths': paths, 'mime': mime}) ?? false;
}

/// The system share sheet.
Future<void> shareFiles(List<XFile> files, String text) => SharePlus.instance.share(
  ShareParams(text: text, files: files, fileNameOverrides: [for (final f in files) f.name]),
);
