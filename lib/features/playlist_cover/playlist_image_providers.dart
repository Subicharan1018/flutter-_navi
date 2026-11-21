import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/web_session.dart';
import '../../providers/settings_provider.dart';
import '../listenbrainz/listenbrainz_link.dart' show navidromeLoginToken;
import 'playlist_image_api.dart';

/// Navidrome's own sign-in token for the saved account (the browser already
/// holds one and never keeps the password).
final navidromeJwtProvider = Provider.autoDispose<Future<String> Function()>((ref) {
  final s = ref.watch(settingsProvider);
  final base = WebSession.navidromeBase(s.serverUrl);
  return () async => WebSession.jwt ?? await navidromeLoginToken(base: base, username: s.username, password: s.password);
});

final playlistImageApiProvider = Provider.autoDispose<PlaylistImageApi>((ref) => PlaylistImageApi(
      base: WebSession.navidromeBase(ref.watch(settingsProvider).serverUrl),
      jwt: ref.watch(navidromeJwtProvider),
    ));
