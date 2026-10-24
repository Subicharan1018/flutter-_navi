import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/features/online_fetch/data/fetch_models.dart';
import 'package:navivibe/features/online_fetch/data/online_fetch_api.dart';
import 'package:navivibe/features/online_fetch/logic/fetch_playlists.dart';
import 'package:navivibe/models/playlist.dart';
import 'package:navivibe/widgets/art/navi_icons.dart';
import 'package:navivibe/features/online_fetch/logic/online_fetch_providers.dart';
import 'package:navivibe/features/online_fetch/ui/fetch_activity.dart';
import 'package:navivibe/features/online_fetch/ui/search_online_row.dart';
import 'package:navivibe/features/online_fetch/ui/send_playlist_sheet.dart';
import 'package:navivibe/features/online_fetch/ui/widgets/fetch_candidate_row.dart';

/// The exact body the live server returned for "rowdy baby" (2026-10-16).
const _inLibraryJson = '''
{"candidates":[],"created_at":1792164192.4,"did_you_mean":null,"error":null,"id":18,
 "library":{"artist":"","matches":[{"album":"Rowdy Baby (From \\"Maari 2\\")",
   "artist":"Yuvan Shankar Raja • Prashant Pandey","id":"BVLDhaybfNoZVSx3g1kBTF",
   "reason":"exact title","score":100.0,"suffix":"flac","title":"Rowdy Baby (From \\"Maari 2\\")"}],
   "query":"rowdy baby","verdict":"in_library"},
 "llm_state":"off","query":"rowdy baby","status":"in_library"}
''';

Map<String, dynamic> _results({String llm = 'done', String status = 'done'}) => {
      'id': 10,
      'query': 'kanmani anbodu',
      'status': status,
      'did_you_mean': null,
      'llm_state': llm,
      'error': null,
      'library': {'verdict': 'not_found', 'matches': []},
      'candidates': [
        {
          'id': 71, 'title': 'Kanmani Anbodu Kadhalan (From "Guna")', 'artist': 'Kamal Haasan',
          'album': 'Guna (Original Motion Picture Soundtrack)', 'score': 100.0, 'kind': 'original',
          'reasons': ['film release', 'AI: best match'], 'library': 'not_found',
          'llm': {'kind': 'original', 'is_requested_song': true},
          'cover_url': 'https://e-cdns-images.dzcdn.net/images/cover/ab/250x250-000000-80-0-0.jpg',
        },
        {
          'id': 63, 'title': 'Kanmani Anbodu', 'artist': 'Suhail Kadavath', 'album': 'Kanmani Anbodu',
          'score': 55.0, 'kind': 'cover', 'reasons': ['AI: cover'], 'library': 'not_found', 'llm': null,
        },
      ],
    };

/// Answers /fetch requests from a script instead of the network.
class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions o) handler;
  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? body, Future<void>? cancel) async => handler(o);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {'content-type': ['application/json']},
    );

OnlineFetchApi _api(ResponseBody Function(RequestOptions o) handler) =>
    OnlineFetchApi(Dio(BaseOptions(baseUrl: 'https://x.test'))..httpClientAdapter = _FakeAdapter(handler));

Finder _glyph(NaviGlyph g) => find.byWidgetPredicate((w) => w is NaviIcon && w.glyph == g);

void main() {
  group('models', () {
    test('parses the live in-library answer', () {
      final s = FetchSearch.fromJson(jsonDecode(_inLibraryJson) as Map<String, dynamic>);
      expect(s.status, FetchSearchStatus.inLibrary);
      expect(s.libraryMatches.single.songId, 'BVLDhaybfNoZVSx3g1kBTF');
      expect(s.isSettled, isTrue);
    });

    test('results: kinds, AI flag, pending AI keeps polling', () {
      final s = FetchSearch.fromJson(_results(llm: 'pending'));
      expect(s.candidates.first.kind, FetchKind.original);
      expect(s.candidates.first.aiChecked, isTrue);
      expect(s.candidates.last.kind.label, 'Cover');
      expect(s.candidates.first.coverUrl, endsWith('250x250-000000-80-0-0.jpg'));
      expect(s.candidates.last.coverUrl, isNull);       // older servers send none
      expect(s.isSettled, isFalse);
    });

    test('server job statuses map to what the user sees', () {
      FetchJobPhase phase(String s) => FetchJob.fromJson({'id': 1, 'candidate_id': 2, 'status': s}).phase;
      expect(phase('picking'), FetchJobPhase.preparing);
      expect(phase('waiting'), FetchJobPhase.preparing);     // a link's song before the bot sends it
      expect(phase('downloading'), FetchJobPhase.downloading);
      expect(phase('scanning'), FetchJobPhase.adding);
      expect(phase('imported'), FetchJobPhase.adding);
      expect(phase('ready'), FetchJobPhase.ready);
      expect(phase('rejected'), FetchJobPhase.rejected);
      expect(phase('import_failed'), FetchJobPhase.failed);
      expect(FetchJob.fromJson({'id': 1, 'candidate_id': 2, 'status': 'ready'}).isFinished, isTrue);
    });
  });

  group('api', () {
    test('server wording is shown for limits', () async {
      final api = _api((_) => _json(429, {'error': 'daily download limit reached'}));
      await expectLater(
        api.startDownload(5),
        throwsA(isA<OnlineFetchException>().having((e) => e.message, 'message', 'daily download limit reached')),
      );
    });

    test('enabled is false on any error', () async {
      expect(await _api((_) => _json(503, {'error': 'offline'})).enabled(), isFalse);
      expect(await _api((_) => _json(200, {'enabled': true})).enabled(), isTrue);
    });
  });

  group('controllers', () {
    setUp(() {
      OnlineSearchController.pollEvery = Duration.zero;
      FetchJobsController.pollEvery = Duration.zero;
    });

    test('search polls until the AI check has answered', () async {
      var polls = 0;
      final api = _api((o) {
        if (o.method == 'POST') return _json(202, {'search_id': 10});
        polls++;
        return _json(200, _results(llm: polls < 3 ? 'pending' : 'done'));
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final sub = c.listen(onlineSearchProvider, (_, _) {});
      addTearDown(sub.close);

      await c.read(onlineSearchProvider.notifier).start('kanmani anbodu');
      final s = c.read(onlineSearchProvider);
      expect(polls, 3);
      expect(s.search!.isSettled, isTrue);
      expect(s.search!.candidates.first.artist, 'Kamal Haasan');
    });

    test('download goes preparing → downloading → ready', () async {
      final statuses = ['picking', 'downloading', 'scanning', 'ready'];
      var i = 0;
      final seen = <FetchJobPhase>[];
      final api = _api((o) {
        if (o.method == 'POST') return _json(202, {'job_id': 3});
        return _json(200, {
          'id': 3, 'candidate_id': 71, 'status': statuses[i++], 'progress': 0.5,
          'nd_song_id': i == statuses.length ? 'nd-new' : null,
        });
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      c.listen(fetchJobsProvider, (_, next) {
        final p = next.jobs[71]?.phase;
        if (p != null && (seen.isEmpty || seen.last != p)) seen.add(p);
      });

      await c.read(fetchJobsProvider.notifier).download(71);
      expect(seen, [FetchJobPhase.preparing, FetchJobPhase.downloading, FetchJobPhase.adding, FetchJobPhase.ready]);
      expect(c.read(fetchJobsProvider).jobs[71]!.songId, 'nd-new');
    });

    test('a failed start is shown, and tapping again retries', () async {
      var posts = 0;
      final api = _api((o) {
        if (o.method == 'GET') return _json(200, {'id': 4, 'candidate_id': 71, 'status': 'rejected'});
        posts++;
        return posts == 1 ? _json(429, {'error': 'daily download limit reached'}) : _json(202, {'job_id': 4});
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final jobs = c.read(fetchJobsProvider.notifier);

      await jobs.download(71);
      expect(c.read(fetchJobsProvider).jobs[71]!.phase, FetchJobPhase.failed);
      expect(c.read(fetchJobsProvider).jobs[71]!.error, 'daily download limit reached');

      await jobs.download(71);                       // a failed job can be retried…
      expect(posts, 2);
      expect(c.read(fetchJobsProvider).jobs[71]!.phase, FetchJobPhase.rejected);
      await jobs.download(71);                       // …a finished one is not restarted
      expect(posts, 2);
    });
  });

  group('batches', () {
    setUp(() {
      OnlineSearchController.pollEvery = Duration.zero;
      FetchJobsController.pollEvery = Duration.zero;
    });

    test('batch json: counts, summary, songs to play', () {
      final b = FetchBatch.fromJson(_batch('done'));
      expect(b.kind, FetchSearchType.album);
      expect(b.isFinished, isTrue);
      expect(b.headline, 'Album downloaded');
      expect(b.summary, '1 song added, 1 already owned, 1 isn’t available in lossless');
      expect(b.songIds, ['nd-owned', 'nd-new']);          // track order, owned ones too
      expect(FetchBatch.fromJson({..._batch('listing'), 'kind': 'songs'}).kind, isNull);
      expect(FetchBatch.fromJson(_batch('listing')).status, FetchBatchStatus.starting);
    });

    test('album / artist / playlist results carry their type', () {
      final c = FetchCandidate.fromJson(_album);
      expect(c.type, FetchSearchType.album);
      expect(c.trackCount, 3);
      expect(c.isSong, isFalse);
    });

    test('search kind and batch picks are sent', () async {
      final sent = <Object?>[];
      final api = _api((o) {
        sent.add(o.data);
        return _json(202, o.path.endsWith('batches') ? {'batch_id': 2} : {'search_id': 9});
      });
      await api.startSearch('maari 2', type: FetchSearchType.album);
      await api.startSearch('rowdy baby');
      await api.startArtistSongs(12);
      await api.startBatch([3, 4]);
      expect(sent, [
        {'query': 'maari 2', 'kind': 'album'},
        {'query': 'rowdy baby'},
        {'candidate_id': 12},
        {'candidate_ids': [3, 4]},
      ]);
    });

    test('an album downloads as a batch and is announced once', () async {
      final statuses = ['listing', 'running', 'running', 'done'];
      var i = 0;
      final api = _api((o) {
        if (o.method == 'POST') return _json(202, {'batch_id': 2});
        return _json(200, _batch(statuses[i < statuses.length - 1 ? i++ : i]));
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final announced = <FetchFinished>[];
      c.listen(fetchFinishedProvider, (_, next) {
        if (next != null) announced.add(next);
      });
      final seen = <FetchBatchStatus>[];
      c.listen(fetchJobsProvider, (_, next) {
        final s = next.batchFor(500)?.status;
        if (s != null && (seen.isEmpty || seen.last != s)) seen.add(s);
      });

      await c.read(fetchJobsProvider.notifier).downloadAll([FetchCandidate.fromJson(_album)]);
      expect(seen, [FetchBatchStatus.starting, FetchBatchStatus.running, FetchBatchStatus.done]);
      expect(announced.single.headline, 'Album downloaded');
      expect(announced.single.detail,
          'Maari 2 (Original Motion Picture Soundtrack) · 1 song added, 1 already owned, 1 isn’t available in lossless');
      expect(announced.single.songIds, ['nd-owned', 'nd-new']);
      expect(c.read(fetchJobsProvider).isActive, isFalse);
    });

    test('one bad poll doesn’t fail a download', () async {
      var gets = 0;
      final api = _api((o) {
        if (o.method == 'POST') return _json(202, {'batch_id': 2});
        gets++;
        return gets == 1 ? _json(429, {'error': 'Too many requests'}) : _json(200, _batch('done'));
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      await c.read(fetchJobsProvider.notifier).downloadAll([FetchCandidate.fromJson(_album)]);
      expect(c.read(fetchJobsProvider).batchFor(500)!.status, FetchBatchStatus.done);
    });

    test('being offline (phone asleep) never fails a download', () async {
      var gets = 0;
      final api = _api((o) {
        if (o.method == 'POST') return _json(202, {'batch_id': 2});
        // More failed polls than maxPollErrors, all "can't reach the server".
        if (++gets <= FetchJobsController.maxPollErrors + 3) {
          throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
        }
        return _json(200, _batch('done'));
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      await c.read(fetchJobsProvider.notifier).downloadAll([FetchCandidate.fromJson(_album)]);
      expect(c.read(fetchJobsProvider).batchFor(500)!.status, FetchBatchStatus.done);
    });

    test('several songs: one batch; their rows follow its items; owned ones left out', () async {
      final posts = <String>[];
      final api = _api((o) {
        if (o.method == 'POST') {
          posts.add(o.path);
          return _json(202, {'batch_id': 3});
        }
        return _json(200, {
          ..._batch('running'), 'kind': 'songs', 'candidate_ids': [71, 63],
          'items': [
            {'candidate_id': 71, 'status': 'downloading', 'progress': 0.5},
            {'candidate_id': 63, 'status': 'queued'},
          ],
        });
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final s = FetchSearch.fromJson(_results());
      final owned = FetchCandidate.fromJson({..._album, 'id': 99, 'type': 'song', 'library': 'in_library'});
      final ctrl = c.read(fetchJobsProvider.notifier);
      unawaited(ctrl.downloadAll([...s.candidates, owned]));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(fetchJobsProvider).jobFor(71)!.phase, FetchJobPhase.preparing);   // before the server answers
      await pumpEventQueue();
      expect(posts, ['/fetch/batches']);
      expect(c.read(fetchJobsProvider).jobFor(71)!.phase, FetchJobPhase.downloading);
      expect(c.read(fetchJobsProvider).isActive, isTrue);
    });

    test('a single picked song is a plain download', () async {
      final posts = <String>[];
      final api = _api((o) {
        if (o.method == 'POST') posts.add(o.path);
        return o.method == 'POST'
            ? _json(202, {'job_id': 4})
            : _json(200, {'id': 4, 'candidate_id': 71, 'status': 'rejected'});
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      await c.read(fetchJobsProvider.notifier).downloadAll([FetchSearch.fromJson(_results()).candidates.first]);
      expect(posts, ['/fetch/jobs']);
    });

    test('artist top songs, and back to the artists', () async {
      final api = _api((o) {
        if (o.method == 'POST') return _json(202, {'search_id': o.data is Map && (o.data as Map).containsKey('candidate_id') ? 11 : 10});
        return _json(200, o.path.endsWith('/11') ? _results() : {..._results(), 'candidates': [_artist]});
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final sub = c.listen(onlineSearchProvider, (_, _) {});
      addTearDown(sub.close);
      final ctrl = c.read(onlineSearchProvider.notifier);

      await ctrl.start('anirudh', type: FetchSearchType.artist);
      final artist = c.read(onlineSearchProvider).search!.candidates.single;
      expect(artist.type, FetchSearchType.artist);
      await ctrl.openArtist(artist);
      final top = c.read(onlineSearchProvider);
      expect(top.artist!.id, artist.id);
      expect(top.listsSongs, isTrue);
      expect(top.search!.candidates.first.title, startsWith('Kanmani'));
      ctrl.back();
      expect(c.read(onlineSearchProvider).type, FetchSearchType.artist);
      expect(c.read(onlineSearchProvider).artist, isNull);
    });
  });

  group('playlists', () {
    setUp(() => FetchJobsController.pollEvery = Duration.zero);

    Playlist pl(String id, String name, {String? owner}) =>
        Playlist(id: id, name: name, comment: '', songCount: 0, duration: 0, owner: owner);

    test('a new playlist: made in the bot’s order, each song once', () async {
      final store = _FakeStore();
      final id = await upsertFetchPlaylist(store, 'Tamil Hits', ['a', 'b', 'a', 'c']);
      expect(id, 'new-1');
      expect(store.created, ['Tamil Hits']);
      expect(store.songs['new-1'], ['a', 'b', 'c']);
    });

    test('asked again: the user’s playlist gets only the new songs, no copy', () async {
      final store = _FakeStore(existing: [pl('p1', 'Tamil Hits', owner: 'Subi')])..songs['p1'] = ['b', 'x'];
      final id = await upsertFetchPlaylist(store, 'Tamil Hits', ['a', 'b', 'c']);
      expect(id, 'p1');
      expect(store.created, isEmpty);
      expect(store.songs['p1'], ['b', 'x', 'a', 'c']);       // kept the user's own edits
      store.writes = 0;
      await upsertFetchPlaylist(store, 'Tamil Hits', ['a', 'b']);
      expect(store.writes, 0);                               // nothing new: nothing written
    });

    test('another user’s public playlist of the same name is left alone', () async {
      final store = _FakeStore(existing: [pl('p9', 'Tamil Hits', owner: 'anish')]);
      expect(await upsertFetchPlaylist(store, 'Tamil Hits', ['a']), 'new-1');
      expect(store.songs.containsKey('p9'), isFalse);
    });

    test('playlist batch → the user’s playlist, recorded, “Playlist ready: 3 of 4”', () async {
      final store = _FakeStore();
      final posted = <String, Object?>{};
      final api = _api((o) {
        if (o.method == 'POST' && o.path.endsWith('/playlist')) {
          posted[o.path] = o.data;
          return _json(200, {'ok': true});
        }
        if (o.method == 'POST') return _json(202, {'batch_id': 7});
        return _json(200, _playlistBatch());
      });
      final c = ProviderContainer(overrides: [
        onlineFetchApiProvider.overrideWithValue(api),
        fetchPlaylistStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      final announced = <FetchFinished>[];
      c.listen(fetchFinishedProvider, (_, n) => n == null ? null : announced.add(n));

      await c.read(fetchJobsProvider.notifier).downloadAll([FetchCandidate.fromJson(_playlist)]);
      expect(store.songs['new-1'], ['nd-owned', 'nd-new', 'nd-shared']);
      expect(posted, {'/fetch/batches/7/playlist': {'playlist_id': 'new-1'}});
      expect(announced.single.headline, 'Playlist ready');
      expect(announced.single.detail, 'Tamil Hits · 3 of 4 songs. 1 isn’t available in lossless.');
      expect(c.read(fetchJobsProvider).batchFor(700)!.playlistId, 'new-1');
    });

    test('playlist can’t be made now: said so, and made on the next app start', () async {
      final store = _FakeStore()..fail = true;
      var made = false;
      final api = _api((o) {
        if (o.method == 'POST' && o.path.endsWith('/playlist')) {
          made = true;
          return _json(200, {'ok': true});
        }
        if (o.method == 'POST') return _json(202, {'batch_id': 7});
        if (o.path == '/fetch/batches') return _json(200, [_playlistBatch()..remove('items')]);
        return _json(200, _playlistBatch());
      });
      final c = ProviderContainer(overrides: [
        onlineFetchApiProvider.overrideWithValue(api),
        fetchPlaylistStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(c.dispose);
      final announced = <FetchFinished>[];
      c.listen(fetchFinishedProvider, (_, n) => n == null ? null : announced.add(n));
      await c.read(fetchJobsProvider.notifier).downloadAll([FetchCandidate.fromJson(_playlist)]);
      expect(made, isFalse);
      expect(announced.single.detail, contains('tried again'));

      // Next app start: a fresh tracker finds the finished batch without a playlist.
      final c2 = ProviderContainer(overrides: [
        onlineFetchApiProvider.overrideWithValue(api),
        fetchPlaylistStoreProvider.overrideWithValue(store..fail = false),
      ]);
      addTearDown(c2.dispose);
      await c2.read(fetchJobsProvider.notifier).resume();
      expect(made, isTrue);
      expect(store.songs['new-1'], ['nd-owned', 'nd-new', 'nd-shared']);
    });

    test('summaries say what was skipped and why', () {
      final album = FetchBatch.fromJson({..._batch('done'), 'lossy': 2, 'failed': 1});
      expect(album.summary, '1 song added, 1 already owned, 2 aren’t available in lossless, 1 couldn’t be found');
      final whole = FetchBatch.fromJson({..._playlistBatch(), 'lossy': 0, 'total': 3});
      expect(whole.summary, '3 songs.');
    });
  });

  group('send a playlist', () {
    setUp(() {
      OnlineSearchController.pollEvery = Duration.zero;
      FetchJobsController.pollEvery = Duration.zero;
    });

    test('link check: what works, and why the rest doesn’t', () {
      expect(playlistLinkProblem('https://www.deezer.com/en/playlist/1032500191?utm=x'), isNull);
      expect(playlistLinkProblem(' https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=1 '), isNull);
      expect(playlistLinkProblem('tamil hits'), contains('Paste a playlist link'));
      expect(playlistLinkProblem('https://www.youtube.com/playlist?list=PLx'), contains('doesn’t take this site'));
      expect(playlistLinkProblem('https://www.deezer.com/album/81950092'), contains('isn’t a playlist'));
      expect(playlistLinkProblem('https://example.com/x'), 'Only Deezer and Spotify playlist links work.');
      expect(looksLikeLink('https://x'), isTrue);
      expect(looksLikeLink('maari 2'), isFalse);
    });

    test('a bad link fails at once, without asking the server', () async {
      var calls = 0;
      final api = _api((o) {
        calls++;
        return _json(500, {});
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final sub = c.listen(sendPlaylistProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(sendPlaylistProvider.notifier).startLink('https://youtu.be/abc');
      expect(calls, 0);
      expect(c.read(sendPlaylistProvider).error, contains('Only Deezer and Spotify'));
    });

    test('a good link lists its songs, owned or new, under the playlist’s name', () async {
      final sent = <Object?>[];
      final api = _api((o) {
        if (o.method == 'POST') {
          sent.add(o.data);
          return _json(202, {'search_id': 52});
        }
        return _json(200, _linkSearch());
      });
      final c = ProviderContainer(overrides: [onlineFetchApiProvider.overrideWithValue(api)]);
      addTearDown(c.dispose);
      final sub = c.listen(sendPlaylistProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(sendPlaylistProvider.notifier).startLink('https://www.deezer.com/playlist/15824893581');
      final s = c.read(sendPlaylistProvider);
      expect(sent, [{'link': 'https://www.deezer.com/playlist/15824893581'}]);
      expect(s.isLink, isTrue);
      expect(s.listsSongs, isFalse);                       // they go all together
      expect(s.search!.title, 'B.K.lywood-M-hits');
      expect([for (final x in s.search!.candidates) x.inLibrary], [true, false, true]);
    });

    test('download: one playlist batch with every song; a refusal adds nothing', () async {
      var refuse = true;
      final sent = <Object?>[];
      final api = _api((o) {
        if (o.method == 'POST') {
          sent.add(o.data);
          return refuse
              ? _json(409, {'error': 'A playlist link is already downloading. Wait for it to finish.'})
              : _json(202, {'batch_id': 4});
        }
        return _json(200, {..._playlistBatch(), 'id': 4, 'candidate_ids': [801, 802, 803], 'playlist_id': 'p'});
      });
      final c = ProviderContainer(overrides: [
        onlineFetchApiProvider.overrideWithValue(api),
        fetchPlaylistStoreProvider.overrideWithValue(_FakeStore()),
      ]);
      addTearDown(c.dispose);
      final listed = FetchSearch.fromJson(_linkSearch());
      final jobs = c.read(fetchJobsProvider.notifier);
      await expectLater(jobs.downloadLink(listed),
          throwsA(isA<OnlineFetchException>().having((e) => e.message, 'message', contains('already downloading'))));
      expect(c.read(fetchJobsProvider).isEmpty, isTrue);
      refuse = false;
      await jobs.downloadLink(listed);
      expect(sent.last, {'search_id': 52});
      final b = c.read(fetchJobsProvider).batchFor(801)!;
      expect(b.kind, FetchSearchType.playlist);
      expect(b.title, 'Tamil Hits');                       // from the server's batch
      expect(b.status, FetchBatchStatus.done);
    });

    testWidgets('the sheet shows the playlist, its counts and the download button', (tester) async {
      final c = ProviderContainer(overrides: [onlineFetchEnabledProvider.overrideWith((ref) async => false)]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: ThemeTokens(
              tokens: AppThemeTokens.fallback,
              child: const SingleChildScrollView(child: SendPlaylistSheet()),
            ),
          ),
        ),
      ));
      c.read(sendPlaylistProvider.notifier).state = OnlineSearchState(
        query: 'https://www.deezer.com/playlist/15824893581',
        isLink: true,
        search: FetchSearch.fromJson(_linkSearch()),
      );
      await tester.pump();
      expect(find.text('B.K.lywood-M-hits'), findsOneWidget);
      expect(find.text('3 songs · 1 new · 2 in your library'), findsOneWidget);
      expect(find.text('Download 1 New Song'), findsOneWidget);
      expect(find.text('In your library'), findsNWidgets(2));
      expect(_glyph(NaviGlyph.downloadCircle), findsNothing);   // rows don't download one by one
    });
  });

  group('no library results', () {
    Future<void> pump(WidgetTester tester, {required bool online}) => tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [onlineFetchEnabledProvider.overrideWith((ref) async => online)],
          child: MaterialApp(
            home: Scaffold(
              body: ThemeTokens(tokens: AppThemeTokens.fallback, child: const NoLibraryResults(query: 'kaavaalaa')),
            ),
          ),
        ));

    testWidgets('offers Search Online and, under it, Send a playlist link', (tester) async {
      await pump(tester, online: true);
      await tester.pump();
      expect(find.text('No results for “kaavaalaa”'), findsOneWidget);
      expect(find.text('Search Online'), findsOneWidget);
      expect(find.text('Send a playlist link'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Send a playlist link')).dy,
          greaterThan(tester.getTopLeft(find.text('Search Online')).dy));
      await tester.tap(find.text('Send a playlist link'));
      await tester.pumpAndSettle();
      expect(find.text('Send a Playlist'), findsOneWidget);       // its sheet opened
    });

    testWidgets('without online search: neither action', (tester) async {
      await pump(tester, online: false);
      await tester.pump();
      expect(find.text('Search Online'), findsNothing);
      expect(find.text('Send a playlist link'), findsNothing);
    });
  });

  group('app-wide', () {
    Widget host(Widget child, List overrides) => ProviderScope(
          key: UniqueKey(),
          overrides: [
            onlineFetchEnabledProvider.overrideWith((ref) async => false),
            ...overrides.cast(),
          ],
          child: MaterialApp(home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: child))),
        );

    testWidgets('ring shows only while something downloads', (tester) async {
      await tester.pumpWidget(host(const FetchActivityRing(child: SizedBox(width: 62, height: 62)), []));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(host(const FetchActivityRing(child: SizedBox(width: 62, height: 62)), [
        fetchJobsProvider.overrideWith(() => _SeededJobs(const FetchDownloads(jobs: {
              71: FetchJob(id: 3, candidateId: 71, phase: FetchJobPhase.downloading, progress: 0.5),
            }))),
      ]));
      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, closeTo(0.45, 0.001));
    });

    testWidgets('finish pop-up: headline, actions, then dismisses itself', (tester) async {
      final c = ProviderContainer(overrides: [onlineFetchEnabledProvider.overrideWith((ref) async => false)]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: const FetchFinishedBanner())),
        ),
      ));
      expect(find.text('Album downloaded'), findsNothing);
      c.read(fetchFinishedProvider.notifier).announce(
          headline: 'Album downloaded', detail: '12 songs added, 2 already owned', songIds: ['a', 'b']);
      await tester.pumpAndSettle();
      expect(find.text('Album downloaded'), findsOneWidget);
      expect(find.text('12 songs added, 2 already owned'), findsOneWidget);
      expect(find.bySemanticsLabel('Play'), findsOneWidget);
      expect(find.bySemanticsLabel('Add to Playlist'), findsOneWidget);
      await tester.pump(FetchFinishedBanner.showFor + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Album downloaded'), findsNothing);
    });

    testWidgets('a failed download shows no Play', (tester) async {
      final c = ProviderContainer(overrides: [onlineFetchEnabledProvider.overrideWith((ref) async => false)]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(body: ThemeTokens(tokens: AppThemeTokens.fallback, child: const FetchFinishedBanner())),
        ),
      ));
      c.read(fetchFinishedProvider.notifier).announce(headline: 'Not available in lossless quality', detail: 'X');
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Play'), findsNothing);
      await tester.pump(FetchFinishedBanner.showFor + const Duration(seconds: 1));
    });
  });

  group('row', () {
    Future<void> pump(WidgetTester tester, FetchCandidate cand, {FetchJob? job, FetchBatch? batch, bool? selected}) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),     // a fresh scope per pump: overrides can't change in place
        overrides: [
          if (job != null || batch != null)
            fetchJobsProvider.overrideWith(() => _SeededJobs(FetchDownloads(
                  jobs: {cand.id: ?job},
                  batches: {1: ?batch},
                ))),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ThemeTokens(
              tokens: AppThemeTokens.fallback,
              child: FetchCandidateRow(candidate: cand, onDownload: () {}, onPlayOwned: () {}, selected: selected),
            ),
          ),
        ),
      ));
    }

    testWidgets('an album shows its song count, then the batch’s progress', (tester) async {
      final album = FetchCandidate.fromJson(_album);
      await pump(tester, album);
      expect(find.text('Album · Yuvan Shankar Raja · 3 songs'), findsOneWidget);
      await pump(tester, album, batch: FetchBatch.fromJson(_batch('running')));
      expect(find.text('2 of 3 songs'), findsOneWidget);
      await pump(tester, album, batch: FetchBatch.fromJson(_batch('done')));
      expect(find.text('1 song added, 1 already owned, 1 isn’t available in lossless'), findsOneWidget);
    });

    testWidgets('select mode shows a check circle instead of the action', (tester) async {
      final song = FetchSearch.fromJson(_results()).candidates.first;
      await pump(tester, song, selected: true);
      expect(_glyph(NaviGlyph.checkCircle), findsOneWidget);
      expect(_glyph(NaviGlyph.downloadCircle), findsNothing);
    });

    final cover = FetchCandidate.fromJson((_results()['candidates'] as List).last as Map<String, dynamic>);

    testWidgets('labels a cover', (tester) async {
      await pump(tester, cover);
      expect(find.text('Cover'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows download progress', (tester) async {
      await pump(tester, cover,
          job: const FetchJob(id: 3, candidateId: 63, phase: FetchJobPhase.downloading, progress: 0.42));
      expect(find.text('Downloading 42%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('explains a lossy-only result', (tester) async {
      await pump(tester, cover, job: const FetchJob(id: 3, candidateId: 63, phase: FetchJobPhase.rejected));
      expect(find.text('Not available in lossless quality'), findsOneWidget);
    });
  });
}

class _SeededJobs extends FetchJobsController {
  final FetchDownloads seed;
  _SeededJobs(this.seed);

  @override
  FetchDownloads build() => seed;
}

/// GET /fetch/searches/{id} for a pasted Deezer link (live shape, 2026-10-17).
Map<String, dynamic> _linkSearch() {
  Map<String, dynamic> song(int id, String title, bool owned) => {
        'id': id, 'title': title, 'artist': 'A', 'album': '', 'score': 0.0, 'kind': 'original', 'reasons': [],
        'library': owned ? 'in_library' : 'not_found', 'llm': null, 'type': 'song', 'track_count': null,
        'duration_s': 200,
      };
  return {
    'id': 52, 'query': 'https://www.deezer.com/playlist/15824893581', 'kind': 'link', 'title': 'B.K.lywood-M-hits',
    'status': 'done', 'did_you_mean': null, 'llm_state': 'off', 'error': null, 'library': null,
    'candidates': [song(801, 'Jujubee', true), song(802, 'Oh Mama! TETEMA', false), song(803, 'Marana Mass', true)],
  };
}

/// Records playlist writes instead of calling the music server.
class _FakeStore implements FetchPlaylistStore {
  final List<Playlist> existing;
  final created = <String>[];
  final songs = <String, List<String>>{};
  var writes = 0;
  var fail = false;
  _FakeStore({this.existing = const []});

  @override
  String get user => 'subi';

  @override
  Future<List<Playlist>> playlists() async {
    if (fail) throw Exception('offline');
    return existing;
  }

  @override
  Future<List<String>> songIds(String playlistId) async => [...?songs[playlistId]];

  @override
  Future<String> create(String name) async {
    created.add(name);
    return 'new-${created.length}';
  }

  @override
  Future<void> setSongs(String playlistId, List<String> ids) async {
    writes++;
    songs[playlistId] = [...ids];
  }
}

const _playlist = <String, dynamic>{
  'id': 700, 'title': 'Tamil Hits', 'artist': 'Che', 'album': '', 'score': 0.0, 'kind': 'original',
  'reasons': [], 'library': 'not_found', 'llm': null, 'type': 'playlist', 'track_count': 5,
};

/// A finished playlist batch: two songs owned (one listed twice by the bot,
/// so one job), one new, one only in MP3. Another user already fetched
/// 'nd-shared', so it's owned here too.
Map<String, dynamic> _playlistBatch() => {
      'id': 7, 'kind': 'playlist', 'title': 'Tamil Hits', 'artist': 'Che', 'cover_url': null,
      'status': 'done', 'error': null, 'candidate_ids': [700], 'playlist_id': null,
      'total': 4, 'added': 1, 'owned': 2, 'lossy': 1, 'failed': 0, 'pending': 0, 'progress': 1.0,
      'items': [
        {'candidate_id': 1, 'title': 'Kanne Kanne', 'status': 'duplicate', 'nd_song_id': 'nd-owned'},
        {'candidate_id': 2, 'title': 'Maari Gethu', 'status': 'ready', 'nd_song_id': 'nd-new'},
        {'candidate_id': 3, 'title': 'Lossy Song', 'status': 'rejected'},
        {'candidate_id': 4, 'title': 'Shared', 'status': 'duplicate', 'nd_song_id': 'nd-shared'},
      ],
    };

/// An album result, as tg-fetcher lists `.a maari 2` (2026-10-17).
const _album = <String, dynamic>{
  'id': 500, 'title': 'Maari 2 (Original Motion Picture Soundtrack)', 'artist': 'Yuvan Shankar Raja',
  'album': '', 'score': 0.0, 'kind': 'original', 'reasons': [], 'library': 'not_found', 'llm': null,
  'cover_url': null, 'type': 'album', 'track_count': 3, 'duration_s': null,
};

const _artist = <String, dynamic>{
  'id': 600, 'title': 'Anirudh Ravichander', 'artist': '', 'album': '', 'score': 0.0, 'kind': 'original',
  'reasons': [], 'library': 'not_found', 'llm': null, 'type': 'artist', 'track_count': null,
};

/// `GET /fetch/batches/{id}` for the album above, at [status].
Map<String, dynamic> _batch(String status) => {
      'id': 2, 'kind': 'album', 'title': 'Maari 2 (Original Motion Picture Soundtrack)',
      'artist': 'Yuvan Shankar Raja', 'cover_url': null, 'status': status, 'error': null,
      'candidate_ids': [500],
      'total': status == 'listing' ? 0 : 3,
      'added': status == 'listing' ? 0 : 1,
      'owned': status == 'listing' ? 0 : 1,
      'lossy': status == 'done' ? 1 : 0,       // Maari’s Aanandhi: MP3 only
      'failed': 0,
      'pending': status == 'done' ? 0 : (status == 'listing' ? 0 : 1),
      'progress': status == 'done' ? 1.0 : 0.4,
      'items': [
        if (status != 'listing') {'candidate_id': 901, 'title': 'Rowdy Baby', 'status': 'duplicate', 'nd_song_id': 'nd-owned'},
        if (status == 'running') ...[
          {'candidate_id': 902, 'title': 'Maari Gethu', 'status': 'ready', 'nd_song_id': 'nd-new'},
          {'candidate_id': 903, 'title': 'Maari’s Aanandhi', 'status': 'downloading', 'progress': 0.2},
        ],
        if (status == 'done') ...[
          {'candidate_id': 902, 'title': 'Maari Gethu', 'status': 'ready', 'nd_song_id': 'nd-new'},
          {'candidate_id': 903, 'title': 'Maari’s Aanandhi', 'status': 'rejected'},
        ],
      ],
    };
