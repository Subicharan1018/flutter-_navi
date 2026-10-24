/// An artist as Subsonic lists it (search results, artist index).
class Artist {
  final String id;
  final String name;
  final int albumCount;

  const Artist({required this.id, required this.name, this.albumCount = 0});

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Unknown Artist',
        albumCount: json['albumCount'] is int
            ? json['albumCount'] as int
            : int.tryParse(json['albumCount']?.toString() ?? '') ?? 0,
      );

  /// Subsonic cover-art id for the artist's portrait.
  String get coverArtId => 'ar-$id';

  @override
  bool operator ==(Object other) => other is Artist && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A genre with how much of the library it covers.
class Genre {
  final String name;
  final int songCount;
  final int albumCount;

  const Genre({required this.name, this.songCount = 0, this.albumCount = 0});

  factory Genre.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
    return Genre(
      // Subsonic puts the genre name in the 'value' field.
      name: (json['value'] ?? json['name'] ?? '').toString(),
      songCount: asInt(json['songCount']),
      albumCount: asInt(json['albumCount']),
    );
  }
}
