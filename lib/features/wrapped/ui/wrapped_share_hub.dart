import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/navi_icons.dart';
import '../film/film.dart';
import '../film/film_export.dart';

/// Where a share goes.
enum WrappedTarget {
  instagram('Instagram', 'com.instagram.android'),
  whatsapp('WhatsApp', 'com.whatsapp'),
  snapchat('Snapchat', 'com.snapchat.android'),
  save('Save to gallery', null),
  more('More', null);

  final String label;
  final String? package;
  const WrappedTarget(this.label, this.package);
}

/// The scenes the share hub starts with: the one you were on, or the highlights when you came from the end.
Set<int> startingPicks(WrappedFilm film, int index) {
  if (film.scenes[index].id != 'finale') return {index};
  return {
    for (var i = 0; i < film.scenes.length; i++)
      if (const {'minutes', 'number-one', 'top5', 'artists', 'genres', 'personality', 'finale'}.contains(film.scenes[i].id)) i,
  };
}

/// The clips a set of picked scenes becomes: one scene at its own pace, several inside a minute.
List<FilmClip> clipsFor(WrappedFilm film, Iterable<int> picks) {
  final list = picks.toList()..sort();
  if (list.length == 1) return sceneClip(film, list.first);
  final each = math.min(4.4, 59 / list.length);
  return [for (final i in list) FilmClip(i, math.min(film.scenes[i].length, film.scenes[i].still + 0.5), each)];
}

/// Pick slides, watch the preview, choose moving or still and whether your name is on it, then send it straight to
/// Instagram, WhatsApp or Snapchat, save it to the gallery, or use the share sheet.
class WrappedShareHub extends StatefulWidget {
  final WrappedFilm film;
  final int index;
  final String? name;
  const WrappedShareHub({super.key, required this.film, required this.index, this.name});

  @override
  State<WrappedShareHub> createState() => WrappedShareHubState();
}

class WrappedShareHubState extends State<WrappedShareHub> {
  late final Set<int> picks = startingPicks(widget.film, widget.index);
  late bool video = AndroidFilm.available;
  bool named = false;
  bool square = false;
  double? progress;
  bool _cancel = false;
  String? problem;

  WrappedFilm get _film => widget.film;
  bool get _canSquare => !video && picks.length == 1 && _film.scenes[picks.first].id == 'finale';

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

  void _toggle(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      if (picks.contains(i)) {
        if (picks.length > 1) picks.remove(i);
      } else {
        picks.add(i);
      }
    });
  }

  Future<void> send(WrappedTarget target) async {
    if (progress != null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      progress = 0;
      _cancel = false;
      problem = null;
    });
    final name = named ? widget.name : null;
    final base = 'navivibe_wrapped_${_film.data.year}';
    final one = picks.length == 1 ? _film.scenes[picks.first] : null;
    final text = one?.share(_film.data) ?? 'My ${_film.data.year} Wrapped, on NaviVibe.';
    void step(double v) {
      if (mounted) setState(() => progress = v);
    }

    try {
      if (video) {
        final path = await renderVideo(
          _film,
          clipsFor(_film, picks),
          const AndroidFilm(),
          name: name,
          fileName: one == null ? base : '${base}_${one.id}',
          onProgress: step,
          cancelled: () => _cancel,
        );
        await _send(target, [path], 'video/mp4', text);
      } else {
        final pictures = <(String, Uint8List)>[];
        final list = picks.toList()..sort();
        for (final i in list) {
          if (_cancel) throw ExportCancelled();
          pictures.add(('${base}_${_film.scenes[i].id}', await renderStill(_film, i, name: name, square: square && _canSquare)));
          step(pictures.length / list.length);
        }
        if (AndroidFilm.available) {
          final paths = [for (final (n, b) in pictures) await AndroidFilm.keep(b, n)];
          await _send(target, paths, 'image/png', text);
        } else {
          await shareFiles([for (final (n, b) in pictures) XFile.fromData(b, mimeType: 'image/png', name: '$n.png')], text);
        }
      }
      if (mounted) {
        setState(() {
          progress = null;
          problem = target == WrappedTarget.save ? 'Saved to your gallery, in NaviVibe.' : null;
        });
      }
    } on ExportCancelled {
      if (mounted) setState(() => progress = null);
    } on _Problem catch (p) {
      if (mounted) {
        setState(() {
          progress = null;
          problem = p.text;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          progress = null;
          problem = video ? 'This phone couldn’t make the video. Try pictures instead.' : 'The pictures couldn’t be made. Try again.';
        });
      }
    }
  }

  Future<void> _send(WrappedTarget target, List<String> paths, String mime, String text) async {
    switch (target) {
      case WrappedTarget.save:
        if (!await AndroidFilm.save(paths, mime)) throw const _Problem('Saving needs Android 10 or newer. Use More instead.');
      case WrappedTarget.more:
        await shareFiles([for (final p in paths) XFile(p, mimeType: mime)], text);
      default:
        if (!await AndroidFilm.sendTo(target.package!, paths, mime)) throw _Problem('${target.label} isn’t on this phone. Use More instead.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final pad = MediaQuery.paddingOf(context);
    final busy = progress != null;
    final android = AndroidFilm.available;
    Widget pill(String label, bool on, VoidCallback tap) => Expanded(
      child: CupertinoClickable(
        onTap: busy ? null : tap,
        semanticLabel: label,
        child: Semantics(
          selected: on,
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? kInk : const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(Radii.capsule)),
            child: Text(label, style: t.headline.copyWith(color: on ? kBlack : kInk)),
          ),
        ),
      ),
    );
    Widget big(WrappedTarget target, Gradient fillColour, Color ink) => CupertinoClickable(
      onTap: busy ? null : () => send(target),
      semanticLabel: 'Share to ${target.label}',
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: fillColour, borderRadius: BorderRadius.circular(Radii.capsule)),
        child: Text(target.label, style: t.title3.copyWith(color: ink, fontWeight: FontWeight.w800)),
      ),
    );
    Widget small(WrappedTarget target) => Expanded(
      child: CupertinoClickable(
        onTap: busy ? null : () => send(target),
        semanticLabel: target.label,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(Radii.capsule)),
          child: Text(target == WrappedTarget.more && !android ? 'Share' : target.label, style: t.headline.copyWith(color: kInk)),
        ),
      ),
    );
    return Material(
      color: const Color(0xFF0A0A0C),
      child: DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Padding(
          padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    CupertinoClickable(
                      onTap: () => Navigator.of(context).maybePop(),
                      semanticLabel: 'Back to the film',
                      child: const SizedBox.square(
                        dimension: 48,
                        child: Center(child: NaviIcon(NaviGlyph.close, size: 20, color: kInk)),
                      ),
                    ),
                    Expanded(child: Text('Share your Wrapped', style: t.title2.copyWith(color: kInk))),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(width: Space.lg),
                    // the preview: exactly what will be sent, playing
                    AspectRatio(
                      aspectRatio: 9 / 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _Preview(film: _film, picks: picks, video: video, name: named ? widget.name : null),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${picks.length} of ${_film.scenes.length} scenes', style: t.footnote.copyWith(color: kDim)),
                          const SizedBox(height: Space.xs),
                          Expanded(
                            child: GridView.builder(
                              padding: EdgeInsets.zero,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 9 / 16),
                              itemCount: _film.scenes.length,
                              itemBuilder: (context, i) => _Thumb(film: _film, index: i, picked: picks.contains(i), onTap: busy ? null : () => _toggle(i)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.lg),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (android) ...[
                          pill('Video', video, () => setState(() => video = true)),
                          const SizedBox(width: Space.sm),
                          pill('Pictures', !video, () => setState(() => video = false)),
                          const SizedBox(width: Space.sm),
                        ],
                        pill('Highlights', false, () => setState(() => picks
                          ..clear()
                          ..addAll(startingPicks(_film, _film.scenes.length - 1)))),
                      ],
                    ),
                    if (_canSquare) ...[
                      const SizedBox(height: Space.sm),
                      Row(children: [pill('Tall 9:16', !square, () => setState(() => square = false)), const SizedBox(width: Space.sm), pill('Square', square, () => setState(() => square = true))]),
                    ],
                    if (widget.name?.isNotEmpty ?? false)
                      SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            Expanded(child: Text('Show my name', style: t.body.copyWith(color: kInk))),
                            CupertinoSwitch(value: named, activeTrackColor: Tone.coral, onChanged: busy ? null : (v) => setState(() => named = v)),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: Space.md),
                    if (busy) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          height: 6,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ColoredBox(color: Color(0xFF2C2C2E)),
                              FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: clamp01(progress!), child: const ColoredBox(color: Tone.coral)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            Expanded(child: Text(video ? 'Filming… ${(progress! * 100).round()}%' : 'Printing… ${(progress! * 100).round()}%', style: t.callout.copyWith(color: kDim))),
                            CupertinoClickable(
                              onTap: () => _cancel = true,
                              semanticLabel: 'Cancel',
                              child: SizedBox(
                                height: 44,
                                width: 80,
                                child: Center(child: Text('Cancel', style: t.headline.copyWith(color: kInk))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      if (android) ...[
                        big(WrappedTarget.instagram, const LinearGradient(colors: [Color(0xFFFEDA77), Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)]), kInk),
                        const SizedBox(height: Space.sm),
                        Row(
                          children: [
                            Expanded(child: big(WrappedTarget.whatsapp, const LinearGradient(colors: [Color(0xFF128C7E), Color(0xFF075E54)]), kInk)),
                            const SizedBox(width: Space.sm),
                            Expanded(child: big(WrappedTarget.snapchat, const LinearGradient(colors: [Color(0xFFFFFC00), Color(0xFFFFE600)]), kBlack)),
                          ],
                        ),
                        const SizedBox(height: Space.sm),
                      ],
                      Row(children: [if (android) ...[small(WrappedTarget.save), const SizedBox(width: Space.sm)], small(WrappedTarget.more)]),
                    ],
                    SizedBox(
                      height: 32,
                      child: problem == null ? null : Center(child: Text(problem!, style: t.footnote.copyWith(color: kInk))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Problem implements Exception {
  final String text;
  const _Problem(this.text);
}

/// A scene's still, small, with a tick when it is picked.
class _Thumb extends StatelessWidget {
  final WrappedFilm film;
  final int index;
  final bool picked;
  final VoidCallback? onTap;
  const _Thumb({required this.film, required this.index, required this.picked, this.onTap});

  @override
  Widget build(BuildContext context) => CupertinoClickable(
    onTap: onTap,
    semanticLabel: '${film.scenes[index].id}, ${picked ? 'picked' : 'not picked'}',
    child: Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: RepaintBoundary(child: CustomPaint(painter: _StillPainter(film, index))),
        ),
        DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: picked ? Tone.coral : const Color(0x33FFFFFF), width: picked ? 3 : 1)),
        ),
        if (picked)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(color: Tone.coral, shape: BoxShape.circle),
              child: const Center(child: NaviIcon(NaviGlyph.check, size: 13, color: kBlack)),
            ),
          ),
      ],
    ),
  );
}

class _StillPainter extends CustomPainter {
  final WrappedFilm film;
  final int index;
  _StillPainter(this.film, this.index);

  @override
  void paint(Canvas canvas, Size size) => film.paint(canvas, size, index: index, t: film.scenes[index].still);

  @override
  bool shouldRepaint(_StillPainter old) => old.index != index;
}

/// The picked scenes playing in turn, the way they will be filmed; stills cycle when the share is pictures.
class _Preview extends StatefulWidget {
  final WrappedFilm film;
  final Set<int> picks;
  final bool video;
  final String? name;
  const _Preview({required this.film, required this.picks, required this.video, this.name});

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((d) => _clock.value = d.inMicroseconds / 1e6)..start();
  final ValueNotifier<double> _clock = ValueNotifier(0);

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _PreviewPainter(widget.film, clipsFor(widget.film, widget.picks), widget.video, widget.name, _clock),
      size: Size.infinite,
    ),
  );
}

class _PreviewPainter extends CustomPainter {
  final WrappedFilm film;
  final List<FilmClip> clips;
  final bool video;
  final String? name;
  final ValueNotifier<double> clock;
  _PreviewPainter(this.film, this.clips, this.video, this.name, this.clock) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    final each = video ? null : 2.0;
    final total = clips.fold<double>(0, (a, c) => a + (each ?? c.seconds));
    var t = clock.value % math.max(0.1, total);
    for (var k = 0; k < clips.length; k++) {
      final c = clips[k];
      final len = each ?? c.seconds;
      if (t <= len || k == clips.length - 1) {
        final at = video ? c.until * clamp01(t / len) : film.scenes[c.index].still;
        film.paint(canvas, size, index: c.index, t: at, from: video && k > 0 ? clips[k - 1].index : null, fromT: k > 0 ? clips[k - 1].until : 0, name: name);
        return;
      }
      t -= len;
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.clips.length != clips.length || old.video != video || old.name != name;
}
