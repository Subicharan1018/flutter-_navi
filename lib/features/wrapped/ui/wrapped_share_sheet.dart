import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme.dart';
import '../film/film.dart';
import '../film/film_export.dart';

/// An opaque panel at the foot of the film.
class WrappedPanel extends StatelessWidget {
  final List<Widget> children;
  const WrappedPanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: DefaultTextStyle(
              style: const TextStyle(decoration: TextDecoration.none),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ),
      ),
    ),
  );
}

enum _Target {
  instagram('Instagram', 'com.instagram.android'),
  whatsapp('WhatsApp', 'com.whatsapp'),
  snapchat('Snapchat', 'com.snapchat.android'),
  more('More', null),
  save('Save', null);

  final String label;
  final String? package;
  const _Target(this.label, this.package);
}

/// What to send (this scene or the whole film, moving or still), whether your name is on it, and where to.
class WrappedShareSheet extends StatefulWidget {
  final WrappedFilm film;
  final int index;
  final String? name;
  const WrappedShareSheet({super.key, required this.film, required this.index, this.name});

  @override
  State<WrappedShareSheet> createState() => _WrappedShareSheetState();
}

class _WrappedShareSheetState extends State<WrappedShareSheet> {
  late bool _video = AndroidFilm.available;
  bool _whole = false;
  bool _square = false;
  bool _named = false;
  double? _progress;
  bool _cancel = false;
  String? _problem;

  bool get _canSquare => !_video && !_whole && widget.film.scenes[widget.index].id == 'finale';

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

  Future<void> _go(_Target target) async {
    if (_progress != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _progress = 0;
      _cancel = false;
      _problem = null;
    });
    final film = widget.film;
    final name = _named ? widget.name : null;
    final base = 'navivibe_wrapped_${film.data.year}';
    final text = _whole ? 'My ${film.data.year} Wrapped, on NaviVibe.' : film.scenes[widget.index].share(film.data);
    void step(double v) {
      if (mounted) setState(() => _progress = v);
    }

    try {
      if (_video) {
        final path = await renderVideo(
          film,
          _whole ? wholeFilm(film) : sceneClip(film, widget.index),
          const AndroidFilm(),
          name: name,
          fileName: _whole ? base : '${base}_${film.scenes[widget.index].id}',
          onProgress: step,
          cancelled: () => _cancel,
        );
        await _send(target, [path], 'video/mp4', text);
      } else {
        final pictures = <(String, Uint8List)>[];
        final which = _whole ? [for (var i = 0; i < film.scenes.length; i++) i] : [widget.index];
        for (final i in which) {
          if (_cancel) throw ExportCancelled();
          pictures.add(('${base}_${film.scenes[i].id}', await renderStill(film, i, name: name, square: _square && _canSquare)));
          step(pictures.length / which.length);
        }
        if (AndroidFilm.available) {
          final paths = [for (final (n, b) in pictures) await AndroidFilm.keep(b, n)];
          await _send(target, paths, 'image/png', text);
        } else {
          await shareFiles([for (final (n, b) in pictures) XFile.fromData(b, mimeType: 'image/png', name: '$n.png')], text);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } on ExportCancelled {
      if (mounted) setState(() => _progress = null);
    } on _Problem catch (p) {
      if (mounted) {
        setState(() {
          _progress = null;
          _problem = p.text;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _progress = null;
          _problem = _video ? 'This phone couldn’t make the video. Try a picture instead.' : 'The picture couldn’t be made. Try again.';
        });
      }
    }
  }

  Future<void> _send(_Target target, List<String> paths, String mime, String text) async {
    switch (target) {
      case _Target.save:
        if (!await AndroidFilm.save(paths, mime)) throw const _Problem('Saving needs Android 10 or newer. Use More instead.');
      case _Target.more:
        await shareFiles([for (final p in paths) XFile(p, mimeType: mime)], text);
      default:
        if (!await AndroidFilm.sendTo(target.package!, paths, mime)) throw _Problem('${target.label} isn’t on this phone.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final busy = _progress != null;
    Widget choice(String label, bool on, VoidCallback tap) => Expanded(
      child: CupertinoClickable(
        onTap: busy ? null : tap,
        semanticLabel: label,
        child: Semantics(
          selected: on,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: on ? kInk : const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(Radii.capsule)),
            child: Text(label, style: t.headline.copyWith(color: on ? const Color(0xFF000000) : kInk)),
          ),
        ),
      ),
    );
    final targets = AndroidFilm.available ? _Target.values : const [_Target.more];
    return WrappedPanel(
      children: [
        Text('Share', style: t.title2.copyWith(color: kInk)),
        const SizedBox(height: Space.lg),
        Row(
          children: [
            choice('This scene', !_whole, () => setState(() => _whole = false)),
            if (widget.film.settled) ...[
              const SizedBox(width: Space.sm),
              choice(_video ? 'The highlights' : 'All scenes', _whole, () => setState(() => _whole = true)),
            ],
          ],
        ),
        if (AndroidFilm.available) ...[
          const SizedBox(height: Space.sm),
          Row(
            children: [
              choice('Moving', _video, () => setState(() => _video = true)),
              const SizedBox(width: Space.sm),
              choice('Still', !_video, () => setState(() => _video = false)),
            ],
          ),
        ],
        if (_canSquare) ...[
          const SizedBox(height: Space.sm),
          Row(
            children: [
              choice('Tall', !_square, () => setState(() => _square = false)),
              const SizedBox(width: Space.sm),
              choice('Square', _square, () => setState(() => _square = true)),
            ],
          ),
        ],
        if (widget.name?.isNotEmpty ?? false)
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(child: Text('Show my name', style: t.body.copyWith(color: kInk))),
                CupertinoSwitch(value: _named, activeTrackColor: kInk, thumbColor: _named ? const Color(0xFF000000) : kInk, onChanged: busy ? null : (v) => setState(() => _named = v)),
              ],
            ),
          )
        else
          const SizedBox(height: Space.lg),
        if (busy) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF2C2C2E)),
                  FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: clamp01(_progress!), child: const ColoredBox(color: kInk)),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(child: Text('Filming… ${(_progress! * 100).round()}%', style: t.callout.copyWith(color: kDim))),
                CupertinoClickable(
                  onTap: () => _cancel = true,
                  semanticLabel: 'Cancel',
                  child: SizedBox(
                    height: 44,
                    width: 72,
                    child: Center(child: Text('Cancel', style: t.headline.copyWith(color: kInk))),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final target in targets)
                CupertinoClickable(
                  onTap: () => _go(target),
                  semanticLabel: target.label,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                    decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(Radii.capsule)),
                    child: Align(
                      widthFactor: 1,
                      child: Text(target == _Target.more && targets.length == 1 ? 'Share' : target.label, style: t.headline.copyWith(color: kInk)),
                    ),
                  ),
                ),
            ],
          ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.md),
              child: Text(_problem!, style: t.callout.copyWith(color: kInk)),
            ),
        ],
      ],
    );
  }
}

class _Problem implements Exception {
  final String text;
  const _Problem(this.text);
}
