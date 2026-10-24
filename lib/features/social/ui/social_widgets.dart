import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/art/generated_cover.dart';
import '../../../widgets/art/navi_icons.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../logic/social_providers.dart';

/// A person: a generated round cover seeded by their name, so the same person
/// looks the same on every phone.
class PersonAvatar extends StatelessWidget {
  final String username;
  final double size;
  const PersonAvatar(this.username, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GeneratedCover.seeded(seed: 'person|${username.toLowerCase()}'),
            Center(
              child: Text(
                username.isEmpty ? '' : username.characters.first.toUpperCase(),
                style: t.headline.copyWith(fontSize: size * 0.4, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centred empty or error content with a drawn glyph and one action.
class SocialNote extends StatelessWidget {
  final NaviGlyph glyph;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SocialNote({
    super.key,
    required this.glyph,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xxxl, vertical: Space.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NaviIcon(glyph, size: 40, color: t.textMuted),
          const SizedBox(height: Space.md),
          Text(title, textAlign: TextAlign.center, style: t.title3),
          const SizedBox(height: Space.xs),
          Text(message, textAlign: TextAlign.center, style: t.subheadline),
          if (actionLabel != null) ...[
            const SizedBox(height: Space.lg),
            SocialButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// The one filled action button on social pages.
class SocialButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool quiet;
  final bool busy;
  final bool destructive;

  const SocialButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.quiet = false,
    this.busy = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final fg = destructive ? t.danger : (quiet ? t.accent : t.onAccent);
    final bg = quiet ? t.fill : t.accent;
    return Semantics(
      button: true,
      label: label,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: busy ? null : onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onPressed == null ? t.fill : bg,
            borderRadius: BorderRadius.circular(Radii.control),
          ),
          child: busy
              ? const CupertinoActivityIndicator()
              : Text(label, style: t.headline.copyWith(color: onPressed == null ? t.textMuted : fg)),
        ),
      ),
    );
  }
}

/// One line of small print under a section ("Only people who turned this on…").
class SocialFootnote extends StatelessWidget {
  final String text;
  const SocialFootnote(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
        child: Text(text, style: ThemeTokens.of(context).footnote),
      );
}

/// Asks for a line of text (a name, a code). Returns null when cancelled.
Future<String?> askForText(
  BuildContext context, {
  required String title,
  required String placeholder,
  required String action,
  String initial = '',
  TextCapitalization capitalization = TextCapitalization.sentences,
}) {
  final controller = TextEditingController(text: initial);
  return showCupertinoDialog<String>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: Space.md),
        child: CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          autofocus: true,
          textCapitalization: capitalization,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
      ),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: Text(action),
        ),
      ],
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}

/// Picks one of the people who turned social features on. [skip] hides people
/// who are already in whatever this is for.
Future<String?> pickPerson(BuildContext context, WidgetRef ref, {Set<String> skip = const {}, required String title}) async {
  final users = await ref.read(socialUsersProvider.future);
  if (!context.mounted) return null;
  final skipLower = {for (final s in skip) s.toLowerCase()};
  final people = [for (final u in users) if (!skipLower.contains(u.toLowerCase())) u];
  return showPlatformSheet<String>(
    context: context,
    title: title,
    builder: (ctx) {
      final t = ThemeTokens.of(ctx);
      if (people.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(Space.xxl, Space.md, Space.xxl, Space.xxl),
          child: Text(
            'No one else has turned social features on yet. Ask your friends to switch them on in Settings.',
            textAlign: TextAlign.center,
            style: t.subheadline,
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: SheetGroup(children: [
          for (final p in people)
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(ctx).pop(p);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm + 2),
                child: Row(children: [
                  PersonAvatar(p, size: 36),
                  const SizedBox(width: Space.md),
                  Expanded(child: Text(p, style: t.body)),
                ]),
              ),
            ),
        ]),
      );
    },
  );
}
