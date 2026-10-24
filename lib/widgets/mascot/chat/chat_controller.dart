import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/ai_shuffle/data/repositories/shuffle_exception.dart';
import '../../../features/ai_shuffle/logic/mix_intent_provider.dart';
import '../../../features/ai_shuffle/logic/recommendation_resolver.dart';
import '../../../features/ai_shuffle/logic/shuffle_providers.dart';
import '../../../features/discover/logic/discover_providers.dart';
import '../../../features/flow/logic/flow_controller.dart';
import '../../../features/listen/data/listen_models.dart';
import '../../../features/listen/logic/listen_providers.dart';
import '../../../features/taste/logic/taste_providers.dart';
import '../../../features/trending/logic/trending_providers.dart' show loadChartSongs;
import '../../../features/weekly_mix/logic/weekly_mix_providers.dart';
import '../../../models/song.dart';
import '../../../providers/catalog_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/player_provider.dart';
import '../../../providers/settings_provider.dart';
import '../microduck_pose.dart';
import '../microduck_talk.dart';
import 'chat_intent.dart';

enum ChatRole { duck, you }

/// Songs a reply is showing, with a line of "because" for each.
class ChatSongs {
  final String title;
  final List<Song> songs;
  final Map<String, String> because;

  /// Plays everything this reply is about (the whole mix, not just the cards).
  final Future<void> Function()? playAll;
  final String playLabel;

  const ChatSongs({
    required this.title,
    required this.songs,
    this.because = const {},
    this.playAll,
    this.playLabel = 'Play',
  });
}

class ChatMessage {
  final ChatRole role;
  final String text;
  final ChatSongs? songs;

  /// A failure told in character; shown with a retry.
  final bool failed;

  /// Replies animate in once; history shows them whole.
  final bool fresh;

  const ChatMessage(this.role, this.text, {this.songs, this.failed = false, this.fresh = false});

  ChatMessage settled() => ChatMessage(role, text, songs: songs, failed: failed);
}

class ChatState {
  final List<ChatMessage> messages;
  final bool busy;
  const ChatState({this.messages = const [], this.busy = false});
}

/// Microduck's chat. History lasts for the app session; "new chat" clears it.
/// Every answer comes from something the app already has: `/intent` ("describe
/// a mix"), Flow, the weekly mix, Discover, taste exclusions, or the song's own
/// metadata. Nothing here calls a model of its own.
final microduckChatProvider = NotifierProvider<MicroduckChatController, ChatState>(MicroduckChatController.new);

class MicroduckChatController extends Notifier<ChatState> {
  @override
  ChatState build() => ChatState(messages: [_greeting()]);

  ChatMessage _greeting() => ChatMessage(
        ChatRole.duck,
        'Hi, I’m ${ref.read(settingsProvider).microduckName}. Tell me a mood, or pick one below.',
      );

  void newChat() => state = ChatState(messages: [_greeting()]);

  void _add(ChatMessage m) {
    final old = [for (final x in state.messages) x.fresh ? x.settled() : x];
    state = ChatState(messages: [...old, m], busy: state.busy);
  }

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || state.busy) return;
    _add(ChatMessage(ChatRole.you, text));
    state = ChatState(messages: state.messages, busy: true);
    try {
      final reply = await _answer(text);
      if (!ref.mounted) return;
      _add(reply);
    } catch (e) {
      if (!ref.mounted) return;
      _add(ChatMessage(ChatRole.duck, _inCharacter(e), failed: true, fresh: true));
    } finally {
      if (ref.mounted) state = ChatState(messages: state.messages);
    }
  }

  /// Failures, as Microduck would put them.
  String _inCharacter(Object e) {
    if (e is ShuffleNetworkError) return 'My signal dropped. Check your connection and ask me again.';
    if (e is ShuffleAuthError) return 'I can’t sign in to the music server. Check your account in Settings.';
    if (e is ShuffleException) return 'The music server tripped over that one (${e.message}). Try again in a moment.';
    return 'Something short-circuited. Ask me again?';
  }

  ChatMessage _say(String text, {ChatSongs? songs}) => ChatMessage(ChatRole.duck, text, songs: songs, fresh: true);

  Song? get _current => ref.read(playerProvider).currentSong;

  MicroduckFacts _facts(Song song) {
    final catalog = ref.read(catalogSongProvider(song.id));
    return MicroduckFacts(
      songId: song.id,
      title: song.title,
      composer: song.composer,
      film: catalog?.film,
      year: song.year,
      playCount: song.playCount,
      starred: song.starred,
      bpm: danceBpm(catalog?.bpm) ?? cachedBpm(song.id),
    );
  }

  /// Holds an auto-dispose provider open while it loads (a bare `read` of its
  /// future could be torn down mid-await).
  Future<T> _load<T>(ProviderSubscription<Object?> Function() hold, Future<T> Function() future) async {
    final sub = hold();
    try {
      return await future();
    } finally {
      sub.close();
    }
  }

  Future<ChatMessage> _answer(String text) async {
    final song = _current;
    switch (routeChat(text)) {
      case ChatIntent.nowPlaying:
        if (song == null) return _say('Nothing is playing yet. Start a song and I’ll tell you all about it.');
        return _say(
          describeSong(title: song.title, artist: song.artist, facts: _facts(song)),
          songs: ChatSongs(title: 'Playing now', songs: [song]),
        );
      case ChatIntent.composer:
        if (song == null) return _say('Nothing is playing yet, so I have no composer to name.');
        final who = song.composer.isNotEmpty ? 'Music by ${song.composer}.' : 'The file doesn’t say who composed it.';
        return _say('“${song.title}” is by ${song.artist}. $who');
      case ChatIntent.recognize:
        return _say('Hold your phone to the music and tap the mic on Home. I’ll listen.');
      case ChatIntent.translate:
        return _say(
          song == null
              ? 'Start a song first, then open its lyrics and switch on Translate.'
              : 'Open the lyrics for “${song.title}” and switch on Translate. I’ll be right here.',
        );
      case ChatIntent.neverArtist:
      case ChatIntent.neverSong:
        if (song == null) return _say('Play the song or artist first, then tell me to never recommend it.');
        final options = neverOptionsFor(song);
        final artist = routeChat(text) == ChatIntent.neverArtist;
        final pick = options.firstWhere(
          (o) => artist ? o.kind == TasteKind.artist : o.kind == TasteKind.song,
          orElse: () => options.first,
        );
        await ref.read(tasteExclusionsProvider.notifier).add(pick);
        return _say('Done. I’ll steer clear of ${pick.label}. You can undo it under Taste.');
      case ChatIntent.weekly:
        return _weekly();
      case ChatIntent.discover:
        return _discover();
      case ChatIntent.flow:
        final ok = await ref.read(flowProvider.notifier).start();
        return _say(ok ? 'Flow is on. I’ll keep them coming.' : (ref.read(flowProvider).error ?? 'Couldn’t start Flow.'));
      case ChatIntent.moreLikeThis:
      case ChatIntent.mix:
        return _mix(mixQuery(text, song));
    }
  }

  Future<ChatMessage> _weekly() async {
    final mix = await _load(() => ref.listen(weeklyMixProvider, (_, _) {}), () => ref.read(weeklyMixProvider.future));
    if (mix.items.isEmpty) return _say('No weekly mix yet. A new one lands every Monday.');
    final picks = mix.items.take(5).toList();
    final songs = await ref.read(listenSongsProvider).loadPicks(picks);
    if (songs.isEmpty) return _say('Your weekly mix is ready, but none of it is in this library yet.');
    return _say(
      'Here’s your weekly mix, ${mix.items.length} songs.',
      songs: ChatSongs(
        title: 'Weekly mix',
        songs: songs,
        because: _because(picks),
        playLabel: 'Play weekly mix',
        playAll: () async {
          await ref.read(weeklyMixPlayerProvider).play(mix);
        },
      ),
    );
  }

  Map<String, String> _because(List<ListenPick> picks) => {
        for (final p in picks)
          if (p.why.isNotEmpty) p.songId: p.why,
      };

  Future<ChatMessage> _discover() async {
    final items = await _load(() => ref.listen(discoverProvider, (_, _) {}), () => ref.read(discoverProvider.future));
    if (items.isEmpty) return _say('Nothing new in your library right now. Check back after the next chart drop.');
    final top = items.take(5).toList();
    final byId = await loadChartSongs(ref, [for (final i in top) i.songId]);
    final songs = [for (final i in top) ?byId[i.songId]];
    return _say(
      'New in your library, ${items.length} to try.',
      songs: ChatSongs(
        title: 'New in your library',
        songs: songs,
        because: {for (final i in top) i.songId: i.reason},
        playLabel: 'Play them all',
        playAll: () async {
          await ref.read(discoverPlayerProvider).play(items);
        },
      ),
    );
  }

  Future<ChatMessage> _mix(String query) async {
    await ref.read(mixIntentProvider.notifier).apply(query);
    final s = ref.read(mixIntentProvider);
    if (s.error != null) return _say(s.error!);
    final r = s.result;
    if (r == null) return _say('I couldn’t read that as a mood. Try “calm Tamil melodies”.');
    final recs = ref.read(shuffleQueueProvider).allRecommendedSongs;
    final library = ref.read(allSongsProvider).asData?.value ?? const <Song>[];
    final resolver = RecommendationResolver(library);
    final songs = <Song>[];
    final because = <String, String>{};
    for (final rec in recs) {
      final match = resolver.resolve(rec);
      if (match == null) continue;
      songs.add(match);
      if (rec.why.isNotEmpty) because[match.id] = rec.why;
    }
    if (songs.isEmpty) return _say('Tuned for ${r.summary}, but none of those are in your library yet.');
    return _say(
      'Tuned for ${r.summary} · ${r.count} ${r.count == 1 ? 'song' : 'songs'}.',
      songs: ChatSongs(
        title: r.summary,
        songs: songs.take(5).toList(),
        because: because,
        playLabel: 'Play this mix',
        playAll: () => _playMix(songs),
      ),
    );
  }

  /// Plays a described mix the way the Smart Shuffle screen does: drop the
  /// preview batches, queue the songs, start a fresh session.
  Future<void> _playMix(List<Song> songs) async {
    final shuffle = ref.read(shuffleQueueProvider.notifier);
    shuffle.clearQueue();
    await ref.read(playerProvider.notifier).setQueue(songs, 0, playlistName: 'Microduck mix');
    shuffle.initSession();
  }

  @visibleForTesting
  Future<ChatMessage> answerForTest(String text) => _answer(text);
}
