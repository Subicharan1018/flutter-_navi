import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../widgets/desktop_dialogs.dart' show showPlatformSheet;
import '../../../widgets/ui/action_sheet.dart';
import '../data/social_api.dart';
import '../data/social_models.dart';
import '../logic/reaction_rules.dart';
import '../logic/social_providers.dart';

/// Pick an emoji, optionally add a short note, and send it to a friend about
/// the song they are playing. Hidden by callers when the server lacks it.
Future<void> showReactionSheet(BuildContext context, Person friend) {
  final song = friend.nowPlaying;
  if (song == null) return Future.value();
  return showPlatformSheet<void>(
    context: context,
    title: 'React to ${friend.username}',
    builder: (_) => _ReactionBody(friend: friend, song: song, page: context),
  );
}

class _ReactionBody extends ConsumerStatefulWidget {
  final Person friend;
  final FriendSong song;
  final BuildContext page;
  const _ReactionBody({required this.friend, required this.song, required this.page});

  @override
  ConsumerState<_ReactionBody> createState() => _ReactionBodyState();
}

class _ReactionBodyState extends ConsumerState<_ReactionBody> {
  final _note = TextEditingController();
  String _emoji = reactionEmoji.first;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final page = widget.page;
    final s = widget.song;
    String message;
    try {
      await ref.read(socialApiProvider).react(
            widget.friend.username,
            _emoji,
            note: cleanReactionNote(_note.text),
            songId: s.songId,
            title: s.title,
            artist: s.artist,
          );
      message = 'Sent to ${widget.friend.username}';
    } on SocialException catch (e) {
      message = e.status == 404 ? 'This server doesn’t support reactions yet.' : e.message;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (page.mounted) showToast(page, message);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final s = widget.song;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          s.artist.isEmpty ? s.title : '${s.title} · ${s.artist}',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.subheadline,
        ),
        const SizedBox(height: Space.md),
        Wrap(alignment: WrapAlignment.center, spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final e in reactionEmoji)
            CupertinoClickable(
              onTap: () => setState(() => _emoji = e),
              scaleFactor: 0.94,
              semanticLabel: 'React $e',
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: e == _emoji ? t.accent : t.outline, width: e == _emoji ? 2 : 0.5),
                ),
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            ),
        ]),
        const SizedBox(height: Space.md),
        CupertinoTextField(
          controller: _note,
          placeholder: 'Add a note (optional)',
          maxLength: reactionNoteMax,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _busy ? null : _send(),
        ),
        const SizedBox(height: Space.md),
        CupertinoButton(
          color: t.accent,
          disabledColor: t.fill,
          borderRadius: BorderRadius.circular(Radii.capsule),
          onPressed: _busy ? null : _send,
          child: Text('Send $_emoji', style: t.headline.copyWith(color: t.onAccent)),
        ),
      ]),
    );
  }
}
