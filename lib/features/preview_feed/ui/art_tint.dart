import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// A quiet, dark colour for a song with no readable cover (or before the cover has loaded): the key picks a hue, the
/// lightness is fixed, so the same song always gets the same page.
Color fallbackTint(String key) {
  var h = 0;
  for (final u in key.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.28, 0.2).toColor();
}

/// The average colour of the cover, pulled to a dark, muted tone so white text stays readable on it.
@visibleForTesting
Color darkTone(Color avg) {
  final hsl = HSLColor.fromColor(avg);
  return hsl
      .withSaturation((hsl.saturation * 0.8).clamp(0.12, 0.5))
      .withLightness(0.2)
      .toColor();
}

final Map<String, Color> _sampled = {};

/// Tests swap this for a sampler that needs no network or image cache.
@visibleForTesting
Future<Color?> Function(String url)? debugTintSampler;

/// Reads a cover at 8 x 8 pixels (a few hundred bytes, never the full image) and returns its dark tone. Null when it cannot
/// be loaded: the caller keeps its fallback.
Future<Color?> sampleTint(String url) async {
  final hit = _sampled[url];
  if (hit != null) return hit;
  final done = Completer<Color?>();
  final stream = ResizeImage(
    CachedNetworkImageProvider(url),
    width: 8,
    height: 8,
  ).resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  l = ImageStreamListener(
    (info, _) async {
      stream.removeListener(l);
      try {
        final bytes = await info.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (bytes == null) return done.complete(null);
        var r = 0, g = 0, b = 0, n = 0;
        for (var i = 0; i + 3 < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint8(i + 3) < 200) continue;
          r += bytes.getUint8(i);
          g += bytes.getUint8(i + 1);
          b += bytes.getUint8(i + 2);
          n++;
        }
        if (n == 0) return done.complete(null);
        done.complete(darkTone(Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n)));
      } catch (_) {
        done.complete(null);
      }
    },
    onError: (_, _) {
      stream.removeListener(l);
      if (!done.isCompleted) done.complete(null);
    },
  );
  stream.addListener(l);
  final c = await done.future.timeout(
    const Duration(seconds: 6),
    onTimeout: () => null,
  );
  if (c != null) _sampled[url] = c;
  return c;
}

/// The page's ground: black at the bottom, the song's tone at the top. One gradient per page (no blur layer); the tone eases in
/// when the cover's colour is known.
class TintedBackdrop extends StatefulWidget {
  final String keyName;
  final String? artUrl;
  final Widget child;
  const TintedBackdrop({
    super.key,
    required this.keyName,
    required this.artUrl,
    required this.child,
  });

  @override
  State<TintedBackdrop> createState() => _TintedBackdropState();
}

class _TintedBackdropState extends State<TintedBackdrop> {
  late Color _tone =
      (widget.artUrl == null ? null : _sampled[widget.artUrl]) ??
      fallbackTint(widget.keyName);

  @override
  void initState() {
    super.initState();
    final url = widget.artUrl;
    if (url != null && !_sampled.containsKey(url)) {
      (debugTintSampler ?? sampleTint)(url).then((c) {
        if (c != null && mounted) setState(() => _tone = c);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _tone),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 500),
      builder: (context, tone, child) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tone ?? _tone, const Color(0xFF000000)],
            stops: const [0, 0.85],
          ),
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
