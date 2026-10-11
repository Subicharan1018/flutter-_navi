import 'package:flutter/widgets.dart';

/// Ionicons v7 glyphs (MIT, assets/ionicons/LICENSE.txt) used by the player
/// and Settings. Each is a white 192px PNG tinted at draw time, so one asset
/// serves every colour and size up to ~64pt.
enum Ion {
  play('play'),
  pause('pause'),
  playBack('play-back'),
  playForward('play-forward'),
  star('star'),
  starOutline('star-outline'),
  ellipsis('ellipsis-horizontal'),
  lyrics('chatbubble-ellipses-outline'),
  devices('headset-outline'),
  queue('list-outline'),
  volumeLow('volume-low'),
  volumeHigh('volume-high'),
  shuffle('shuffle-outline'),
  repeat('repeat-outline'),
  infinite('infinite-outline'),
  reshuffle('reload-outline'),
  dragHandle('reorder-three-outline'),
  remove('remove-circle-outline'),
  search('search'),
  globe('globe-outline'),
  person('person-outline'),
  lock('lock-closed-outline'),
  unlock('lock-open-outline'),
  palette('color-palette-outline'),
  options('options-outline'),
  convert('swap-horizontal-outline'),
  wifi('wifi-outline'),
  cellular('cellular-outline'),
  document('document-text-outline'),
  sync('sync-outline'),
  download('download-outline'),
  image('image-outline'),
  music('musical-notes-outline'),
  timer('timer-outline'),
  sparkles('sparkles-outline'),
  share('share-outline'),
  upload('cloud-upload-outline'),
  calendar('calendar-outline'),
  trash('trash-outline'),
  add('add-circle-outline'),
  folder('folder-outline'),
  link('link-outline'),
  moon('moon-outline');

  const Ion(this.file);
  final String file;

  String get asset => 'assets/ionicons/$file.png';
}

/// Draws an [Ion] like an [Icon]: [size] square, tinted [color] (falls back
/// to the ambient [IconTheme]).
class IonIcon extends StatelessWidget {
  final Ion glyph;
  final double size;
  final Color? color;
  final String? semanticLabel;

  const IonIcon(this.glyph, {super.key, this.size = 24, this.color, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? const Color(0xFFFFFFFF);
    final px = (size * (MediaQuery.maybeDevicePixelRatioOf(context) ?? 3)).round();
    return Image.asset(
      glyph.asset,
      width: size,
      height: size,
      cacheWidth: px,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
