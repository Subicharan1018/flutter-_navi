import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../features/recognize/ui/recognize_sheet.dart';
import '../../models/song.dart';
import '../../player/artwork.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../add_to_playlist_dialog.dart';
import '../art/navi_icons.dart';
import '../ui/action_sheet.dart' show showToast;
import 'chat/chat_controller.dart';
import 'chat/chat_intent.dart';
import 'chat/chat_voice.dart';
import 'microduck.dart';
import 'microduck_mesh.dart';
import 'microduck_pose.dart';

/// True while the chat sheet is up: the one robot on screen is the chat's, so
/// the strip's steps aside.
final ValueNotifier<bool> microduckChatOpen = ValueNotifier(false);

/// The chat: Microduck in the header (thinking while it works, talking while a
/// reply appears, hopping when it has answered), replies as plain monochrome
/// bubbles with song cards, and suggestions that fit the moment.
Future<void> showMicroduckChat(BuildContext context) async {
  microduckChatOpen.value = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MicroduckChatSheet(),
    );
  } finally {
    microduckChatOpen.value = false;
  }
}

class MicroduckChatSheet extends ConsumerStatefulWidget {
  const MicroduckChatSheet({super.key});

  @override
  ConsumerState<MicroduckChatSheet> createState() => _MicroduckChatSheetState();
}

class _MicroduckChatSheetState extends ConsumerState<MicroduckChatSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();

  /// How many replies are still appearing letter by letter.
  final ValueNotifier<int> _revealing = ValueNotifier(0);
  int _seen = 0;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _revealing.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      }
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    if (routeChat(text) == ChatIntent.recognize) {
      // Listening to the room is its own sheet; hand over to it.
      final host = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop();
      await showRecognizeSheet(host);
      return;
    }
    _text.clear();
    await ref.read(microduckChatProvider.notifier).send(text);
  }

  Future<void> _speak() async {
    final said = await ref.read(chatVoiceInputProvider).listen();
    if (said != null && said.trim().isNotEmpty) await _send(said);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final chat = ref.watch(microduckChatProvider);
    final skin = ref.watch(settingsProvider.select((s) => s.microduckSkin));
    final name = ref.watch(settingsProvider.select((s) => s.microduckName));
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final voice = ref.watch(chatVoiceInputProvider);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    if (chat.messages.length != _seen) {
      _seen = chat.messages.length;
      _toEnd();
    }
    final chips = suggestChips(current: song, now: DateTime.now());

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bgSurfaceOpaque,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: _revealing,
                  builder: (context, revealing, _) => _Header(
                    name: name,
                    skin: skin,
                    thinking: chat.busy,
                    talking: revealing > 0,
                    onNewChat: () => ref.read(microduckChatProvider.notifier).newChat(),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    itemCount: chat.messages.length + (chat.busy ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == chat.messages.length) return const _Typing();
                      final m = chat.messages[i];
                      return _MessageView(
                        message: m,
                        onRevealing: (on) {
                          _revealing.value = (_revealing.value + (on ? 1 : -1)).clamp(0, 99);
                          if (on) _toEnd();
                        },
                        onRetry: m.failed ? () => _send(_lastAsk(chat.messages, i)) : null,
                      );
                    },
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: chips.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _Chip(label: chips[i].label, onTap: chat.busy ? null : () => _send(chips[i].text)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: _text,
                          placeholder: 'Describe a mix, like “calm Tamil melodies”',
                          style: t.body,
                          placeholderStyle: t.body.copyWith(color: t.textMuted),
                          cursorColor: t.accent,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _send,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: t.textPrimary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      if (voice.available)
                        _IconButton(glyph: NaviGlyph.mic, label: 'Speak', onTap: chat.busy ? null : _speak),
                      _IconButton(glyph: NaviGlyph.caretUp, label: 'Send', onTap: chat.busy ? null : () => _send(_text.text)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What the person asked before the failed reply at [index].
  static String _lastAsk(List<ChatMessage> messages, int index) {
    for (var i = index - 1; i >= 0; i--) {
      if (messages[i].role == ChatRole.you) return messages[i].text;
    }
    return '';
  }
}

class _Header extends StatelessWidget {
  final String name;
  final MicroduckSkin skin;
  final bool thinking;
  final bool talking;
  final VoidCallback onNewChat;
  const _Header({required this.name, required this.skin, required this.thinking, required this.talking, required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
      child: Row(
        children: [
          Microduck(pose: MicroduckPose.idle, size: 92, skin: skin, thinking: thinking, talking: talking, interactive: true),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: t.title3),
                Text(
                  thinking ? 'Thinking…' : (talking ? 'Talking…' : 'Ask me for music'),
                  style: t.footnote.copyWith(color: t.textSecondary),
                ),
              ],
            ),
          ),
          _IconButton(glyph: NaviGlyph.edit, label: 'New chat', onTap: onNewChat),
          _IconButton(glyph: NaviGlyph.close, label: 'Close', onTap: () => Navigator.of(context).maybePop()),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final NaviGlyph glyph;
  final String label;
  final VoidCallback? onTap;
  const _IconButton({required this.glyph, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onTap,
      child: NaviIcon(glyph, size: 22, color: onTap == null ? t.textMuted : t.textPrimary, semanticLabel: label),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _Chip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Center(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            height: 36,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.textPrimary.withValues(alpha: 0.25)),
            ),
            child: Text(label, style: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

/// The robot's typing indicator is on its own screen in the header; in the
/// list this is only a quiet placeholder so the layout does not jump.
class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text('Working on it…', style: t.footnote.copyWith(color: t.textMuted)),
    );
  }
}

class _MessageView extends StatelessWidget {
  final ChatMessage message;
  final ValueChanged<bool> onRevealing;
  final VoidCallback? onRetry;
  const _MessageView({required this.message, required this.onRevealing, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final mine = message.role == ChatRole.you;
    final songs = message.songs;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? t.textPrimary : t.textPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: mine
                  ? Text(message.text, style: t.body.copyWith(color: t.bgBase))
                  : _Reveal(
                      text: message.text,
                      animate: message.fresh,
                      style: t.body.copyWith(color: t.textPrimary),
                      onRevealing: onRevealing,
                    ),
            ),
            if (onRetry != null)
              CupertinoButton(
                padding: const EdgeInsets.only(top: 4, left: 6),
                minimumSize: const Size(44, 32),
                onPressed: onRetry,
                child: Text('Try again', style: t.footnote.copyWith(color: t.accent, fontWeight: FontWeight.w700)),
              ),
            if (songs != null) _SongCards(songs: songs),
          ],
        ),
      ),
    );
  }
}

/// Shows [text] a few letters at a time the first time it appears, as if it
/// were being said; whole at once on later builds and with reduced motion.
class _Reveal extends StatefulWidget {
  final String text;
  final bool animate;
  final TextStyle style;
  final ValueChanged<bool> onRevealing;
  const _Reveal({required this.text, required this.animate, required this.style, required this.onRevealing});

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _reported = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || !widget.animate) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    final ms = (widget.text.length * 22).clamp(300, 1800);
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: ms));
    _c = c;
    _reported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRevealing(true));
    c.forward().whenComplete(() {
      if (mounted && _reported) {
        _reported = false;
        widget.onRevealing(false);
      }
    });
  }

  @override
  void dispose() {
    if (_reported) widget.onRevealing(false);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || c.isCompleted) return Text(widget.text, style: widget.style);
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final n = (widget.text.length * Curves.easeOut.transform(c.value)).round();
        // The full text lays out invisibly, so the bubble does not grow word by word.
        return Stack(
          children: [
            Opacity(opacity: 0, child: Text(widget.text, style: widget.style)),
            Text(widget.text.substring(0, n), style: widget.style),
          ],
        );
      },
    );
  }
}

/// Song cards: cover, title, artist, a "because" line and play / queue /
/// playlist buttons; and one button to play the whole mix.
class _SongCards extends ConsumerWidget {
  final ChatSongs songs;
  const _SongCards({required this.songs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(songs.title.toUpperCase(), style: t.caption1.copyWith(color: t.textMuted, letterSpacing: 0.6)),
          ),
          for (final s in songs.songs) _SongRow(song: s, because: songs.because[s.id]),
          if (songs.playAll != null)
            CupertinoButton(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
              minimumSize: const Size(44, 36),
              onPressed: () async {
                await songs.playAll!();
                if (context.mounted) Navigator.of(context).maybePop();
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  NaviIcon(NaviGlyph.play, size: 16, color: t.accent),
                  const SizedBox(width: 6),
                  Text(songs.playLabel, style: t.subheadline.copyWith(color: t.accent, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SongRow extends ConsumerWidget {
  final Song song;
  final String? because;
  const _SongRow({required this.song, required this.because});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ThemeTokens.of(context);
    final url = ref.read(subsonicServiceProvider).getCoverArtUrl(song.coverArt);
    final player = ref.read(playerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CoverImage(url: url, cacheKey: coverCacheKey(song), width: 46, height: 46, cacheWidth: 138),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.callout.copyWith(fontWeight: FontWeight.w600)),
                Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.footnote.copyWith(color: t.textSecondary)),
                if (because != null)
                  Text(because!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.footnote.copyWith(color: t.textMuted, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          _IconButton(glyph: NaviGlyph.play, label: 'Play ${song.title}', onTap: () => player.setQueue([song], 0, playlistName: 'Microduck')),
          _IconButton(
            glyph: NaviGlyph.playLast,
            label: 'Add ${song.title} to the queue',
            onTap: () async {
              await player.addToQueue(song);
              if (context.mounted) showToast(context, 'Added to queue');
            },
          ),
          _IconButton(glyph: NaviGlyph.addToPlaylist, label: 'Add ${song.title} to a playlist', onTap: () => showAddToPlaylist(context, song)),
        ],
      ),
    );
  }
}
