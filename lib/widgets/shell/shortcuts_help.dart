import 'package:flutter/material.dart';

import '../../core/focus/navi_focus.dart';
import '../../core/theme.dart';
import '../ui/navi_icon_button.dart';
import '../art/navi_icons.dart';

// =============================================================================
// shortcuts_help.dart — the keyboard shortcuts, listed (Ctrl+/ or the bar's
// keyboard button). One list, so it cannot drift from the bindings it names
// without somebody seeing both.
// =============================================================================

const List<(String, List<(String, String)>)> kShortcutGroups = [
  ('Playback', [
    ('Space', 'Play or pause'),
    ('Ctrl + →', 'Next song'),
    ('Ctrl + ←', 'Previous song'),
    ('→  /  ←', 'Seek 5 seconds'),
    ('↑  /  ↓', 'Volume up or down'),
    ('M', 'Mute or unmute'),
    ('S', 'Shuffle'),
    ('R', 'Repeat'),
    ('L', 'Favorite the song'),
  ]),
  ('Navigate', [
    ('Ctrl + K', 'Search'),
    ('Ctrl + F', 'Find in this list'),
    ('Alt + ←  /  Alt + →', 'Back, forward'),
    ('Ctrl + 1 … 6', 'Home, Shuffle, Jam, Stats, Library, Search'),
    ('Ctrl + ,', 'Settings'),
    ('F6  /  Shift + F6', 'Move between the library, the page, Now Playing and the player bar'),
    ('Esc', 'Close a panel, or go back'),
  ]),
  ('In a song list', [
    ('Click', 'Select'),
    ('Ctrl / Shift + click', 'Add to the selection, select a range'),
    ('Double-click  /  Enter', 'Play'),
    ('Ctrl + A', 'Select all'),
    ('Delete', 'Remove from the playlist'),
    ('Right-click', 'Menu'),
  ]),
  ('Help', [
    ('Ctrl + /', 'This list'),
  ]),
];

Future<void> showShortcutsHelp(BuildContext context) {
  final t = ThemeTokens.of(context);
  return showDialog<void>(
    context: context,
    // Opaque chrome: no dimming and no shadow; the dialog is a tonal step with a hairline.
    barrierColor: Colors.transparent,
    builder: (ctx) => Dialog(
      elevation: 0,
      backgroundColor: t.bgElevated,
      insetPadding: const EdgeInsets.all(Space.xxl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sheet),
        side: BorderSide(color: t.separatorOpaque, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.sm, Space.sm),
              child: Row(
                children: [
                  Expanded(child: Text('Keyboard shortcuts', style: t.title2)),
                  NaviIconButton(glyph: NaviGlyph.close, tooltip: 'Close (Esc)', onTap: () => Navigator.of(ctx).pop(), size: 16),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
                shrinkWrap: true,
                children: [
                  for (final (group, rows) in kShortcutGroups) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xs),
                      child: Text(group, style: t.footnote.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    for (final (keys, what) in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(child: Text(what, style: t.subheadline.copyWith(color: t.textPrimary))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
                              decoration: BoxDecoration(
                                color: t.fill,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: t.outline, width: 0.5),
                              ),
                              child: Text(keys, style: t.caption1.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The keyboard glyph in the player bar.
class KeyboardHelpButton extends StatelessWidget {
  const KeyboardHelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Semantics(
      button: true,
      label: 'Keyboard shortcuts',
      child: Tooltip(
        message: 'Keyboard shortcuts (Ctrl+/)',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: NaviPressable(
            onTap: () => showShortcutsHelp(context),
            child: SizedBox(
              width: 32,
              height: 32,
              // Centred, so the glyph keeps its 16 (a tight box would stretch it to 32).
              child: Center(child: NaviIcon(NaviGlyph.help, size: 16, color: t.textSecondary)),
            ),
          ),
        ),
      ),
    );
  }
}
