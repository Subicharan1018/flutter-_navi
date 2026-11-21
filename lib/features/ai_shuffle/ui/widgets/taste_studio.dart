import 'package:flutter/cupertino.dart';

import '../../../../core/theme.dart';
import '../../../../utils/platform_utils.dart';
import '../../../../widgets/art/navi_icons.dart';
import '../../../../widgets/ui/media.dart';
import 'energy_dial.dart';
import 'taste_field.dart';
import 'taste_math.dart';

/// "Why these songs": the taste field and the energy dial together. Tap a dot
/// to see the song; drag the dial to reshape the mix around an energy.
class TasteStudio extends StatefulWidget {
  final List<TastePoint> points;

  /// Null until the listener touches the dial.
  final double? dial;
  final ValueChanged<double> onDial;
  final VoidCallback onResetDial;
  final ValueChanged<String> onPlaySong;

  const TasteStudio({
    super.key,
    required this.points,
    required this.dial,
    required this.onDial,
    required this.onResetDial,
    required this.onPlaySong,
  });

  @override
  State<TasteStudio> createState() => _TasteStudioState();
}

class _TasteStudioState extends State<TasteStudio> {
  String? _selected;

  @override
  void didUpdateWidget(TasteStudio old) {
    super.didUpdateWidget(old);
    if (_selected != null && !widget.points.any((p) => p.id == _selected)) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final g = pageGutter(context);
    final desk = PlatformUtils.isDesktop;
    final picked = widget.points.where((p) => p.id == _selected).firstOrNull;
    final spread = hasEnergySpread(widget.points);
    final mean = meanEnergy(widget.points);

    final field = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TasteField(
          points: widget.points,
          dial: widget.dial,
          selectedId: _selected,
          onSelect: (id) => setState(() => _selected = id),
          height: desk ? 300 : 260,
        ),
        // Reserved height so a tap never moves the page.
        SizedBox(
          height: 44,
          child: picked == null
              ? Center(
                  child: Text(
                    widget.dial == null ? 'Nearer the centre, closer to this moment.' : 'Nearer the centre, closer to that energy.',
                    style: t.footnote,
                    textAlign: TextAlign.center,
                  ),
                )
              : CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => widget.onPlaySong(picked.id),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      NaviIcon(NaviGlyph.play, size: 14, color: t.textPrimary),
                      const SizedBox(width: Space.sm),
                      Flexible(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: picked.title, style: t.subheadline.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
                            TextSpan(text: '  ${picked.artist}', style: t.subheadline),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );

    final dial = spread
        ? EnergyDial(
            value: widget.dial ?? mean,
            active: widget.dial != null,
            onChanged: widget.onDial,
            onReset: widget.onResetDial,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Why These Songs'),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: desk ? 480 : double.infinity),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              field,
              if (dial != null) ...[const SizedBox(height: Space.sm), dial],
            ]),
          ),
        ),
        const SizedBox(height: Space.md),
      ],
    );
  }
}
