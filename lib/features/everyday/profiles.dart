import 'dart:convert';

/// R3: "Who's listening?". The logins this device has seen on a server, so a
/// shared TV or PC can switch between family members with one tap and no
/// typing. Pure logic; storage is in profiles_providers.dart (the encrypted
/// auth box, since it holds passwords).

class Profile {
  const Profile({required this.serverUrl, required this.username, required this.password, this.name = ''});

  final String serverUrl;
  final String username;
  final String password;

  /// What the picker shows. Empty = the username.
  final String name;

  String get displayName => name.trim().isEmpty ? username : name.trim();

  /// One letter for the avatar.
  String get initial => displayName.isEmpty ? '?' : String.fromCharCode(displayName.runes.first).toUpperCase();

  /// Same person on the same server (case does not matter for either).
  String get key => keyOf(serverUrl, username);

  static String keyOf(String serverUrl, String username) =>
      '${_server(serverUrl)}|${username.trim().toLowerCase()}';

  static String _server(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');

  Profile copyWith({String? password, String? name}) =>
      Profile(serverUrl: serverUrl, username: username, password: password ?? this.password, name: name ?? this.name);

  Map<String, dynamic> toJson() => {'s': serverUrl, 'u': username, 'p': password, if (name.isNotEmpty) 'n': name};

  static Profile? tryParse(Object? j) {
    try {
      final m = j as Map;
      final p = Profile(
        serverUrl: m['s'] as String,
        username: m['u'] as String,
        password: m['p'] as String,
        name: (m['n'] as String?) ?? '',
      );
      return p.username.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }
}

class Profiles {
  const Profiles([this.all = const []]);
  final List<Profile> all;

  /// The profiles of one server, in the order they were first added.
  List<Profile> forServer(String serverUrl) => [
    for (final p in all)
      if (Profile._server(p.serverUrl) == Profile._server(serverUrl)) p,
  ];

  Profile? find(String serverUrl, String username) {
    final k = Profile.keyOf(serverUrl, username);
    for (final p in all) {
      if (p.key == k) return p;
    }
    return null;
  }

  /// Remembers a login that worked. A new person is added; a known one gets
  /// the newer password (the old one may have been changed on the server) and
  /// keeps their chosen name. Empty fields are ignored.
  Profiles remember(String serverUrl, String username, String password) {
    if (serverUrl.trim().isEmpty || username.trim().isEmpty || password.isEmpty) return this;
    final existing = find(serverUrl, username);
    if (existing == null) {
      return Profiles([...all, Profile(serverUrl: serverUrl.trim(), username: username.trim(), password: password)]);
    }
    if (existing.password == password) return this;
    return Profiles([for (final p in all) p.key == existing.key ? p.copyWith(password: password) : p]);
  }

  Profiles rename(String serverUrl, String username, String name) {
    final k = Profile.keyOf(serverUrl, username);
    return Profiles([for (final p in all) p.key == k ? p.copyWith(name: name.trim()) : p]);
  }

  /// Forgets a profile (the account itself is untouched).
  Profiles forget(String serverUrl, String username) {
    final k = Profile.keyOf(serverUrl, username);
    return Profiles([
      for (final p in all)
        if (p.key != k) p,
    ]);
  }

  String encode() => jsonEncode([for (final p in all) p.toJson()]);

  static Profiles decode(String? raw) {
    if (raw == null || raw.isEmpty) return const Profiles();
    try {
      final out = <Profile>[];
      final seen = <String>{};
      for (final e in jsonDecode(raw) as List) {
        final p = Profile.tryParse(e);
        if (p != null && seen.add(p.key)) out.add(p);
      }
      return Profiles(out);
    } catch (_) {
      return const Profiles();
    }
  }
}
