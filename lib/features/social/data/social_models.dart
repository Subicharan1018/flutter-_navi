import '../../../models/song.dart';

String _s(Object? v) => v?.toString() ?? '';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse(_s(v)) ?? 0;

/// What a person has chosen to share. Everything starts off.
class SocialSettings {
  final bool enabled;
  final bool hideActivity;
  const SocialSettings({this.enabled = false, this.hideActivity = false});

  factory SocialSettings.fromJson(Map<String, dynamic> j) =>
      SocialSettings(enabled: j['enabled'] == true, hideActivity: j['hide_activity'] == true);

  SocialSettings copyWith({bool? enabled, bool? hideActivity}) =>
      SocialSettings(enabled: enabled ?? this.enabled, hideActivity: hideActivity ?? this.hideActivity);
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

class JamMember {
  final String username;
  final bool isHost;
  const JamMember(this.username, this.isHost);
}

class JamState {
  final String code;
  final int version;
  final String host;
  final bool youAreHost;
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
  });

  JamItem? get current => index >= 0 && index < queue.length ? queue[index] : null;

  factory JamState.fromJson(Map<String, dynamic> j) => JamState(
        code: _s(j['code']),
        version: _i(j['version']),
        host: _s(j['host']),
        youAreHost: j['you_are_host'] == true,
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
