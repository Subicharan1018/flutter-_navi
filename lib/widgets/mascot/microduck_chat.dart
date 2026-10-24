import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../features/ai_shuffle/logic/mix_intent_provider.dart';
import '../../features/ai_shuffle/logic/recommendation_resolver.dart';
import '../../features/ai_shuffle/logic/shuffle_providers.dart';
import '../../features/flow/logic/flow_controller.dart';
import '../../models/song.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import 'microduck.dart';
import 'microduck_pose.dart';
import 'microduck_talk.dart';

/// The mini chat: Microduck with a few quick chips and a text box. Everything
/// goes through endpoints the app already uses — "describe a mix" (`/intent`)
/// for anything typed, Flow (`/flow/next`) for "surprise me" — and what it
/// says about the current song comes from local data.
Future<void> showMicroduckChat(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MicroduckChatSheet(),
    );

enum _Who { duck, you }

class _Message {
  final _Who who;
  final String text;

  /// Offered under a duck message: play the mix it just built.
  final bool offersPlay;
  const _Message(this.who, this.text, {this.offersPlay = false});
}

class MicroduckChatSheet extends ConsumerStatefulWidget {
  const MicroduckChatSheet({super.key});

  @override
  ConsumerState<MicroduckChatSheet> createState() => _MicroduckChatSheetState();
}

class _MicroduckChatSheetState extends ConsumerState<MicroduckChatSheet> {
  static const _chips = ['Play something calm', 'More like this', 'Surprise me', 'What is this song?'];

  final _text = TextEditingController();
  final _scroll = ScrollController();
  late final List<_Message> _messages;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final name = ref.read(settingsProvider).microduckName;
    _messages = [_Message(_Who.duck, 'Hi, I’m $name. Tell me a mood, or pick one below.')];
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _say(_Message m) {
    if (!mounted) return;
    setState(() => _messages.add(m));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
      }
    });
  }

  Song? get _song => ref.read(playerProvider).currentSong;

  Future<void> _ask(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _busy) return;
    _text.clear();
    _say(_Message(_Who.you, text));
    final lower = text.toLowerCase();
    final song = _song;

    if (lower.contains('what is this') || lower.contains("what's this")) {
      _say(_Message(_Who.duck, song == null ? 'Nothing is playing yet.' : _describe(song)));
      return;
    }
    setState(() => _busy = true);
    try {
      if (lower.contains('surprise')) {
        final ok = await ref.read(flowProvider.notifier).start();
        _say(_Message(_Who.duck, ok ? 'Flow is on. I’ll keep them coming.' : (ref.read(flowProvider).error ?? 'Couldn’t start Flow.')));
      } else {
        final query = lower.contains('more like this')
            ? (song == null ? 'something I like' : 'songs like ${song.title} by ${song.artist}')
            : text;
        await ref.read(mixIntentProvider.notifier).apply(query);
        if (!mounted) return;
        final s = ref.read(mixIntentProvider);
        if (s.error != null) {
          _say(_Message(_Who.duck, s.error!));
        } else if (s.result != null) {
          final r = s.result!;
          _say(_Message(_Who.duck, 'Tuned for ${r.summary} · ${r.count} ${r.count == 1 ? 'song' : 'songs'}.', offersPlay: true));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _describe(Song song) {
    final catalog = ref.read(catalogSongProvider(song.id));
    return describeSong(title: song.title, artist: song.artist, facts: _facts(song, catalog?.film, catalog?.bpm));
  }

  MicroduckFacts _facts(Song song, String? film, double? catalogBpm) => MicroduckFacts(
        songId: song.id,
        title: song.title,
        composer: song.composer,
        film: film,
        year: song.year,
        playCount: song.playCount,
        starred: song.starred,
        bpm: danceBpm(catalogBpm) ?? cachedBpm(song.id),
      );

  /// Plays the mix the last request built, as the Smart Shuffle screen does.
  Future<void> _play() async {
    final shuffle = ref.read(shuffleQueueProvider.notifier);
    final recs = ref.read(shuffleQueueProvider).allRecommendedSongs;
    final library = ref.read(allSongsProvider).asData?.value ?? const <Song>[];
    final songs = RecommendationResolver(library).resolveAll(recs);
    if (songs.isEmpty) {
      _say(const _Message(_Who.duck, 'None of those are in your library yet.'));
      return;
    }
    shuffle.clearQueue();
    await ref.read(playerProvider.notifier).setQueue(songs, 0, playlistName: 'Microduck mix');
    shuffle.initSession();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final skin = ref.watch(settingsProvider.select((s) => s.microduckSkin));
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
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
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Microduck(pose: MicroduckPose.idle, size: 96, skin: skin, thinking: _busy, interactive: true),
                Flexible(
                  child: ListView.builder(
                    controller: _scroll,
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _Bubble(message: _messages[i], onPlay: _play),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _chips.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => _Chip(label: _chips[i], onTap: _busy ? null : () => _ask(_chips[i])),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: CupertinoTextField(
                    controller: _text,
                    placeholder: 'Describe a mix, like “calm Tamil melodies”',
                    style: t.body,
                    placeholderStyle: t.body.copyWith(color: t.textMuted),
                    cursorColor: t.accent,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _ask,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: t.textPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.textPrimary.withValues(alpha: 0.25)),
          ),
          child: Text(label, style: t.footnote.copyWith(color: t.textPrimary, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Message message;
  final VoidCallback onPlay;
  const _Bubble({required this.message, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final t = ThemeTokens.of(context);
    final mine = message.who == _Who.you;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: mine ? t.textPrimary : t.textPrimary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.text, style: t.body.copyWith(color: mine ? t.bgBase : t.textPrimary)),
            if (message.offersPlay)
              CupertinoButton(
                padding: const EdgeInsets.only(top: 6),
                minimumSize: const Size(44, 32),
                onPressed: onPlay,
                child: Text('Play it', style: t.footnote.copyWith(color: t.accent, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}
