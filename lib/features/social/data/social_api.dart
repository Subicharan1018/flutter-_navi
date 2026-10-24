import 'package:dio/dio.dart';

import '../../../models/song.dart';
import 'social_models.dart';

/// A social request failed. [message] is safe to show as is; [status] lets the
/// Jam tell "the Jam ended" (410) from "you were dropped" (403).
class SocialException implements Exception {
  final String message;
  final int? status;
  const SocialException(this.message, {this.status});

  bool get ended => status == 410;
  bool get notInJam => status == 403;

  @override
  String toString() => message;
}

/// Client for the shuffle server's `/social/*` routes (Jam, shared playlists,
/// Blend, friend activity). Build it with `createShuffleDio` so it shares the
/// shuffle client's auth and retries.
class SocialApi {
  final Dio _dio;
  const SocialApi(this._dio);

  // ── settings / people ────────────────────────────────────────────────────

  Future<SocialSettings> settings() =>
      _wrap(() async => SocialSettings.fromJson(await _get('/social/settings')));

  Future<SocialSettings> saveSettings({bool? enabled, bool? hideActivity}) => _wrap(() async {
        final r = await _dio.put<Map<String, dynamic>>('/social/settings', data: {
          'enabled': ?enabled,
          'hide_activity': ?hideActivity,
        });
        return SocialSettings.fromJson(r.data ?? const {});
      });

  Future<List<String>> users() => _wrap(() async {
        final j = await _get('/social/users');
        return [for (final u in (j['users'] as List? ?? const [])) u.toString()];
      });

  Future<FriendFeed> activity() => _wrap(() async => FriendFeed.fromJson(await _get('/social/activity')));

  // ── Jam ──────────────────────────────────────────────────────────────────

  Future<JamState> jamCreate() => _wrap(() async => _jam(await _post('/social/jam')));

  Future<JamState> jamJoin(String code) =>
      _wrap(() async => _jam(await _post('/social/jam/join', {'code': code.trim()})));

  Future<JamState?> jamCurrent() => _wrap(() async {
        final j = await _get('/social/jam/current');
        return j['jam'] is Map ? JamState.fromJson(Map<String, dynamic>.from(j['jam'] as Map)) : null;
      });

  /// The Jam's state, or null (with [serverMs]/[version] unchanged) when
  /// nothing changed since [since].
  Future<JamPoll> jamPoll(String code, int since) => _wrap(() async {
        final j = await _get('/social/jam/$code', {'since': since});
        if (j['changed'] == false) {
          return JamPoll(null, serverMs: (j['server_ms'] as num?)?.toInt() ?? 0);
        }
        final state = JamState.fromJson(Map<String, dynamic>.from(j['jam'] as Map));
        return JamPoll(state, serverMs: state.serverMs);
      });

  Future<JamState> jamAddSongs(String code, List<Song> songs) => _wrap(() async => _jam(await _post(
        '/social/jam/$code/queue',
        {
          'songs': [
            for (final s in songs)
              {
                'song_id': s.id,
                'title': s.title,
                'artist': s.artist,
                'album': s.album,
                'cover_art': s.coverArt,
                'duration_s': s.duration,
              },
          ],
        },
      )));

  Future<JamState> jamRemoveItem(String code, int itemId) =>
      _wrap(() async => _jam(await _delete('/social/jam/$code/queue/$itemId')));

  Future<JamState> jamControl(String code, String action, {int? positionMs, int? index}) =>
      _wrap(() async => _jam(await _post('/social/jam/$code/control', {
            'action': action,
            'position_ms': ?positionMs,
            'index': ?index,
          })));

  Future<void> jamLeave(String code) => _wrap(() async => _post('/social/jam/$code/leave'));

  Future<void> jamEnd(String code) => _wrap(() async => _post('/social/jam/$code/end'));

  // ── collaborative playlists ──────────────────────────────────────────────

  Future<List<CollabPlaylist>> collabList() => _wrap(() async {
        final j = await _get('/social/collab');
        return [
          for (final p in (j['playlists'] as List? ?? const []))
            if (p is Map) CollabPlaylist.fromJson(Map<String, dynamic>.from(p)),
        ];
      });

  Future<CollabPlaylist> collabCreate(String name, {List<String> songIds = const []}) =>
      _wrap(() async => _collab(await _post('/social/collab', {'name': name, 'song_ids': songIds})));

  Future<CollabPlaylist> collabGet(String id) => _wrap(() async => _collab(await _get('/social/collab/$id')));

  Future<CollabPlaylist> collabRename(String id, String name) => _wrap(() async {
        final r = await _dio.patch<Map<String, dynamic>>('/social/collab/$id', data: {'name': name});
        return _collab(r.data ?? const {});
      });

  Future<void> collabDelete(String id) => _wrap(() async => _delete('/social/collab/$id'));

  Future<CollabPlaylist> collabInvite(String id, String username) =>
      _wrap(() async => _collab(await _post('/social/collab/$id/invite', {'username': username})));

  Future<void> collabRespond(String id, bool accept) =>
      _wrap(() async => _post('/social/collab/$id/respond', {'accept': accept}));

  Future<void> collabRemoveMember(String id, String username) =>
      _wrap(() async => _delete('/social/collab/$id/members/${Uri.encodeComponent(username)}'));

  Future<CollabPlaylist> collabAddSongs(String id, List<String> songIds) =>
      _wrap(() async => _collab(await _post('/social/collab/$id/songs', {'song_ids': songIds})));

  Future<CollabPlaylist> collabRemoveSong(String id, int entryId) =>
      _wrap(() async => _collab(await _delete('/social/collab/$id/songs/$entryId')));

  // ── Blend ────────────────────────────────────────────────────────────────

  Future<List<Blend>> blends() => _wrap(() async {
        final j = await _get('/social/blend');
        return [
          for (final b in (j['blends'] as List? ?? const []))
            if (b is Map) Blend.fromJson(Map<String, dynamic>.from(b)),
        ];
      });

  Future<Blend> blendInvite(String username) => _wrap(() async {
        final j = await _post('/social/blend', {'username': username});
        return Blend.fromJson(Map<String, dynamic>.from(j['blend'] as Map));
      });

  Future<void> blendRespond(String id, bool accept) =>
      _wrap(() async => _post('/social/blend/$id/respond', {'accept': accept}));

  Future<Blend> blend(String id) => _wrap(() async {
        final j = await _get('/social/blend/$id');
        return Blend.fromJson(Map<String, dynamic>.from(j['blend'] as Map));
      });

  Future<void> blendLeave(String id) => _wrap(() async => _delete('/social/blend/$id'));

  // ── plumbing ─────────────────────────────────────────────────────────────

  JamState _jam(Map<String, dynamic> j) => JamState.fromJson(Map<String, dynamic>.from(j['jam'] as Map));

  CollabPlaylist _collab(Map<String, dynamic> j) =>
      CollabPlaylist.fromJson(Map<String, dynamic>.from((j['playlist'] ?? j) as Map));

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async =>
      (await _dio.get<Map<String, dynamic>>(path, queryParameters: query)).data ?? const {};

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? body]) async =>
      (await _dio.post<Map<String, dynamic>>(path, data: body ?? const {})).data ?? const {};

  Future<Map<String, dynamic>> _delete(String path) async =>
      (await _dio.delete<Map<String, dynamic>>(path)).data ?? const {};

  Future<T> _wrap<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final data = e.response?.data;
      final server = data is Map && data['error'] is String ? data['error'] as String : null;
      throw SocialException(
        switch (status) {
          null => 'Can’t reach the server. Check your connection.',
          401 => 'Sign in again to use social features.',
          429 => 'Too many requests. Wait a moment and try again.',
          _ => server ?? 'The server couldn’t do that. Try again.',
        },
        status: status,
      );
    }
  }
}

/// One Jam poll: [state] is null when nothing changed.
class JamPoll {
  final JamState? state;
  final int serverMs;
  const JamPoll(this.state, {required this.serverMs});
}
