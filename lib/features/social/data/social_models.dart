import '../../../models/song.dart';

String _s(Object? v) => v?.toString() ?? '';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;

/// What a person has chosen to share. Everything starts off.
class SocialSettings {
  final bool enabled;
  final bool hideActivity;

  /// Hide "what I'm listening to" (People, Listening now, notifications). The
  /// server makes it follow [hideActivity] until the person sets it themselves.
  final bool hideListening;
  const SocialSettings({this.enabled = false, this.hideActivity = false, bool? hideListening})
      : hideListening = hideListening ?? hideActivity;

  factory SocialSettings.fromJson(Map<String, dynamic> j) => SocialSettings(
        enabled: j['enabled'] == true,
        hideActivity: j['hide_activity'] == true,
        hideListening: j['hide_listening'] is bool ? j['hide_listening'] as bool : null,
      );

  SocialSettings copyWith({bool? enabled, bool? hideActivity, bool? hideListening}) => SocialSettings(
        enabled: enabled ?? this.enabled,
        hideActivity: hideActivity ?? this.hideActivity,
        hideListening: hideListening ?? this.hideListening,
      );
}

// ── Friend activity ──────────────────────────────────────────────────────────

class FriendSong {
  final String songId;
  final String title;
  final String artist;
  final String album;
  final String coverArt;

  /// Seconds-resolution age of the play: minutes for now-playing, null for history.
  final int? minutesAgo;
  final int? playedAt;

  const FriendSong({
    required this.songId,
    required this.title,
    this.artist = '',
    this.album = '',
    this.coverArt = '',
    this.minutesAgo,
    this.playedAt,
  });

  bool get playable => songId.isNotEmpty;

  factory FriendSong.fromJson(Map<String, dynamic> j) => FriendSong(
        songId: _s(j['song_id']),
        title: _s(j['title']),
        artist: _s(j['artist']),
        album: _s(j['album']),
        coverArt: _s(j['cover_art']),
        minutesAgo: j['minutes_ago'] == null ? null : _i(j['minutes_ago']),
        playedAt: j['played_at'] == null ? null : _i(j['played_at']),
      );
}

class FriendActivity {
  final String username;
  final FriendSong? nowPlaying;
  final List<FriendSong> recent;
  const FriendActivity({required this.username, this.nowPlaying, this.recent = const []});

  factory FriendActivity.fromJson(Map<String, dynamic> j) => FriendActivity(
        username: _s(j['username']),
        nowPlaying: j['now_playing'] is Map
            ? FriendSong.fromJson(Map<String, dynamic>.from(j['now_playing'] as Map))
            : null,
        recent: [
          for (final r in (j['recent'] as List? ?? const []))
            if (r is Map) FriendSong.fromJson(Map<String, dynamic>.from(r)),
        ],
      );
}

class FriendFeed {
  /// False until this person turned friend activity on.
  final bool enabled;
  final List<FriendActivity> friends;
  const FriendFeed({this.enabled = false, this.friends = const []});

  factory FriendFeed.fromJson(Map<String, dynamic> j) => FriendFeed(
        enabled: j['enabled'] == true,
        friends: [
          for (final f in (j['friends'] as List? ?? const []))
            if (f is Map) FriendActivity.fromJson(Map<String, dynamic>.from(f)),
        ],
      );
}

// ── People ───────────────────────────────────────────────────────────────────

/// How present someone is. Shown by shape (filled / half / hollow / dashed),
/// never by colour alone.
enum PresenceState {
  active,
  idle,
  offline,

  /// Chose not to share what they listen to: nothing else is known.
  hidden;

  static PresenceState parse(Object? v) => switch (v) {
        'active' => PresenceState.active,
        'idle' => PresenceState.idle,
        'hidden' => PresenceState.hidden,
        _ => PresenceState.offline,
      };

  String get label => switch (this) {
        PresenceState.active => 'Listening now',
        PresenceState.idle => 'Idle',
        PresenceState.offline => 'Offline',
        PresenceState.hidden => 'Not sharing',
      };
}

/// The room a person is in, as far as the server lets you see it.
class PersonRoom {
  final JamMode mode;
  final bool open;
  final int members;

  /// Only present when the room's admin opened it to friends.
  final String? code;
  final bool joinable;
  const PersonRoom({required this.mode, this.open = false, this.members = 1, this.code, this.joinable = false});

  factory PersonRoom.fromJson(Map<String, dynamic> j) => PersonRoom(
        mode: JamMode.parse(j['mode']),
        open: j['open'] == true,
        members: _i(j['members']),
        code: j['code'] as String?,
        joinable: j['joinable'] == true && j['code'] is String,
      );
}

class Person {
  final String username;
  final PresenceState state;
  final FriendSong? nowPlaying;
  final PersonRoom? room;
  const Person({required this.username, this.state = PresenceState.offline, this.nowPlaying, this.room});

  bool get isActive => state == PresenceState.active;

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        username: _s(j['username']),
        state: PresenceState.parse(j['state']),
        nowPlaying:
            j['now_playing'] is Map ? FriendSong.fromJson(Map<String, dynamic>.from(j['now_playing'] as Map)) : null,
        room: j['room'] is Map ? PersonRoom.fromJson(Map<String, dynamic>.from(j['room'] as Map)) : null,
      );
}

class PeopleList {
  /// False until this person turned social features on.
  final bool enabled;
  final List<Person> people;
  const PeopleList({this.enabled = false, this.people = const []});

  factory PeopleList.fromJson(Map<String, dynamic> j) => PeopleList(
        enabled: j['enabled'] == true,
        people: [
          for (final p in (j['people'] as List? ?? const []))
            if (p is Map) Person.fromJson(Map<String, dynamic>.from(p)),
        ],
      );

  List<Person> get listeningNow => [for (final p in people) if (p.isActive) p];
}

// ── Jam ──────────────────────────────────────────────────────────────────────

class JamItem {
  final int id;
  final String songId;
  final String title;
  final String artist;
  final String album;
  final String coverArt;
  final int durationS;
  final String addedBy;

  const JamItem({
    required this.id,
    required this.songId,
    required this.title,
    this.artist = '',
    this.album = '',
    this.coverArt = '',
    this.durationS = 0,
    this.addedBy = '',
  });

  factory JamItem.fromJson(Map<String, dynamic> j) => JamItem(
        id: _i(j['id']),
        songId: _s(j['song_id']),
        title: _s(j['title']),
        artist: _s(j['artist']),
        album: _s(j['album']),
        coverArt: _s(j['cover_art']),
        durationS: _i(j['duration_s']),
        addedBy: _s(j['added_by']),
      );

  /// A playable [Song] built from what the Jam carries, so every phone has the
  /// same queue positions whatever its local library mirror holds.
  Song toSong() => Song.fromJson({
        'id': songId,
        'title': title,
        'artist': artist,
        'album': album,
        'coverArt': coverArt,
        'duration': durationS,
      });
}

/// How a room is run. In a [jam] the creator is the admin and members can only
/// add songs; in a [collab] room everyone edits one shared queue.
enum JamMode {
  jam,
  collab;

  static JamMode parse(Object? v) => v == 'collab' ? JamMode.collab : JamMode.jam;
  String get wire => name;
  String get label => this == JamMode.jam ? 'Jam' : 'Collab';
}

class JamMember {
  final String username;
  final bool isHost;
  const JamMember(this.username, this.isHost);

  /// The room's admin (the old name for it is "host").
  bool get isAdmin => isHost;
  String get role => isHost ? 'Admin' : 'Member';
}

/// A member asking the admin to skip the song that is playing.
class SkipRequest {
  final String username;
  final int itemId;
  const SkipRequest(this.username, this.itemId);
}

/// Someone who left, timed out or was removed, for "Recently left".
class LeftMember {
  final String username;

  /// 'left' or 'removed'.
  final String reason;
  final int agoS;
  const LeftMember(this.username, this.reason, this.agoS);

  bool get removed => reason == 'removed';
}

class JamState {
  final String code;
  final int version;
  final JamMode mode;

  /// The admin opened the room to friends: they can join from People.
  final bool open;
  final String host;
  final bool youAreHost;

  /// Whether this person may reorder, remove, skip and control playback. Always
  /// true for the admin and, in a collab room, for everyone. The server is the
  /// real gate; this only decides which controls to show.
  final bool youCanEdit;

  /// Open requests to skip the current song (the admin acts on these).
  final List<SkipRequest> skipRequests;

  /// You already asked to skip the current song.
  final bool youRequestedSkip;

  /// The last few people who left or were removed, newest first.
  final List<LeftMember> recentlyLeft;
  final List<JamMember> members;
  final List<JamItem> queue;
  final int index;
  final bool playing;

  /// Where playback was at [serverMs] (server clock).
  final int positionMs;
  final int serverMs;

  const JamState({
    required this.code,
    required this.version,
    required this.host,
    required this.youAreHost,
    required this.members,
    required this.queue,
    required this.index,
    required this.playing,
    required this.positionMs,
    required this.serverMs,
    this.mode = JamMode.jam,
    this.open = false,
    this.skipRequests = const [],
    this.youRequestedSkip = false,
    this.recentlyLeft = const [],
    bool? youCanEdit,
  }) : youCanEdit = youCanEdit ?? (youAreHost || mode == JamMode.collab);

  String get admin => host;
  bool get youAreAdmin => youAreHost;
  bool get isCollab => mode == JamMode.collab;

  JamItem? get current => index >= 0 && index < queue.length ? queue[index] : null;

  factory JamState.fromJson(Map<String, dynamic> j) => JamState(
        code: _s(j['code']),
        version: _i(j['version']),
        mode: JamMode.parse(j['mode']),
        open: j['open'] == true,
        skipRequests: [
          for (final r in (j['skip_requests'] as List? ?? const []))
            if (r is Map) SkipRequest(_s(r['username']), _i(r['item_id'])),
        ],
        youRequestedSkip: j['you_requested_skip'] == true,
        recentlyLeft: [
          for (final r in (j['recently_left'] as List? ?? const []))
            if (r is Map) LeftMember(_s(r['username']), _s(r['reason']), _i(r['ago_s'])),
        ],
        host: _s(j['admin'] ?? j['host']),
        youAreHost: (j['you_are_admin'] ?? j['you_are_host']) == true,
        youCanEdit: j['you_can_edit'] is bool ? j['you_can_edit'] as bool : null,
        members: [
          for (final m in (j['members'] as List? ?? const []))
            if (m is Map) JamMember(_s(m['username']), m['is_host'] == true),
        ],
        queue: [
          for (final q in (j['queue'] as List? ?? const []))
            if (q is Map) JamItem.fromJson(Map<String, dynamic>.from(q)),
        ],
        index: _i(j['index']),
        playing: j['playing'] == true,
        positionMs: _i(j['position_ms']),
        serverMs: _i(j['server_ms']),
      );
}

// ── Collaborative playlists ─────────────────────────────────────────────────

class CollabEntry {
  final int entryId;
  final String songId;
  final String addedBy;
  final int addedAt;
  const CollabEntry({required this.entryId, required this.songId, required this.addedBy, this.addedAt = 0});

  factory CollabEntry.fromJson(Map<String, dynamic> j) => CollabEntry(
        entryId: _i(j['entry_id']),
        songId: _s(j['song_id']),
        addedBy: _s(j['added_by']),
        addedAt: _i(j['added_at']),
      );
}

class CollabMember {
  final String username;
  final bool active;
  const CollabMember(this.username, this.active);
}

class CollabPlaylist {
  final String id;
  final String name;
  final String owner;
  final bool isOwner;

  /// 'active' or 'invited' (null: not a member).
  final String? status;
  final String? invitedBy;
  final int songCount;
  final List<CollabMember> members;
  final List<CollabEntry> songs;

  const CollabPlaylist({
    required this.id,
    required this.name,
    required this.owner,
    required this.isOwner,
    this.status,
    this.invitedBy,
    this.songCount = 0,
    this.members = const [],
    this.songs = const [],
  });

  bool get invited => status == 'invited';

  factory CollabPlaylist.fromJson(Map<String, dynamic> j) => CollabPlaylist(
        id: _s(j['id']),
        name: _s(j['name']),
        owner: _s(j['owner']),
        isOwner: j['is_owner'] == true,
        status: j['status'] as String?,
        invitedBy: j['invited_by'] as String?,
        songCount: _i(j['song_count']),
        members: [
          for (final m in (j['members'] as List? ?? const []))
            if (m is Map) CollabMember(_s(m['username']), m['status'] == 'active'),
        ],
        songs: [
          for (final s in (j['songs'] as List? ?? const []))
            if (s is Map) CollabEntry.fromJson(Map<String, dynamic>.from(s)),
        ],
      );
}

// ── Blend ────────────────────────────────────────────────────────────────────

class BlendSong {
  final String songId;
  final String title;

  /// Who it came from: 'both' or a username.
  final String from;
  const BlendSong({required this.songId, required this.title, required this.from});

  factory BlendSong.fromJson(Map<String, dynamic> j) =>
      BlendSong(songId: _s(j['song_id']), title: _s(j['title']), from: _s(j['from']));
}

class Blend {
  final String id;
  final String withUser;
  final String status;
  final bool incoming;
  final bool paused;
  final int? matchPct;
  final String? refreshedOn;
  final List<BlendSong> songs;
  final bool notEnoughListening;

  const Blend({
    required this.id,
    required this.withUser,
    required this.status,
    this.incoming = false,
    this.paused = false,
    this.matchPct,
    this.refreshedOn,
    this.songs = const [],
    this.notEnoughListening = false,
  });

  bool get pending => status == 'pending';

  factory Blend.fromJson(Map<String, dynamic> j) => Blend(
        id: _s(j['id']),
        withUser: _s(j['with']),
        status: _s(j['status']),
        incoming: j['incoming'] == true,
        paused: j['paused'] == true,
        matchPct: j['match_pct'] == null ? null : _i(j['match_pct']),
        refreshedOn: j['refreshed_on'] as String?,
        songs: [
          for (final s in (j['songs'] as List? ?? const []))
            if (s is Map) BlendSong.fromJson(Map<String, dynamic>.from(s)),
        ],
        notEnoughListening: j['not_enough_listening'] == true,
      );
}
