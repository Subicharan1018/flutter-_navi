/// What the signed-in account may do on the NaviVibe server, from
/// `GET /me/capabilities`. The server decides (admins plus the people an admin
/// granted with `bin/fetch-access`); the app only hides what would be refused.
class ServerCapabilities {
  /// May use Search Online, playlist links, label search and Recognize > Download.
  final bool download;

  const ServerCapabilities({this.download = false});

  /// Nothing allowed: signed out, offline, or any error.
  static const none = ServerCapabilities();

  factory ServerCapabilities.fromJson(Object? json) {
    if (json is! Map) return none;
    return ServerCapabilities(download: json['download'] == true);
  }

  @override
  bool operator ==(Object other) => other is ServerCapabilities && other.download == download;

  @override
  int get hashCode => download.hashCode;
}
