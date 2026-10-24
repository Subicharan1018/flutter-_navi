// The definition of a smart playlist: a tree of rules (AND / OR groups), a
// sort and an optional limit. Pure data with JSON, so it lives in Hive and is
// evaluated locally (see smart_evaluator.dart).

enum SmartFieldKind { text, number, days, flag }

enum SmartField {
  title('Title', SmartFieldKind.text),
  artist('Artist', SmartFieldKind.text),
  album('Album', SmartFieldKind.text),
  genre('Genre', SmartFieldKind.text),
  composer('Composer', SmartFieldKind.text),
  language('Language', SmartFieldKind.text),
  mood('Mood', SmartFieldKind.text),
  year('Year', SmartFieldKind.number),
  length('Length (min)', SmartFieldKind.number),
  playCount('Play count', SmartFieldKind.number),
  recentPlays('Plays in the last…', SmartFieldKind.number),
  rating('Rating', SmartFieldKind.number),
  added('Date added', SmartFieldKind.days),
  lastPlayed('Last played', SmartFieldKind.days),
  starred('Starred', SmartFieldKind.flag);

  final String label;
  final SmartFieldKind kind;
  const SmartField(this.label, this.kind);

  /// Fields whose value is picked from a list rather than typed.
  bool get isChoice => this == language || this == mood;

  List<SmartOp> get ops => switch (kind) {
        SmartFieldKind.text => isChoice
            ? const [SmartOp.isOp, SmartOp.isNot]
            : const [SmartOp.isOp, SmartOp.isNot, SmartOp.contains, SmartOp.notContains],
        SmartFieldKind.number => const [SmartOp.eq, SmartOp.neq, SmartOp.gt, SmartOp.gte, SmartOp.lt, SmartOp.lte],
        SmartFieldKind.days => const [SmartOp.within, SmartOp.notWithin],
        SmartFieldKind.flag => const [SmartOp.isOp],
      };
}

enum SmartOp {
  isOp('is'),
  isNot('is not'),
  contains('contains'),
  notContains('does not contain'),
  eq('='),
  neq('≠'),
  gt('>'),
  gte('≥'),
  lt('<'),
  lte('≤'),
  within('in the last'),
  notWithin('not in the last');

  final String label;
  const SmartOp(this.label);
}

enum SmartSort {
  title('Title'),
  artist('Artist'),
  year('Year'),
  added('Date added'),
  lastPlayed('Last played'),
  playCount('Play count'),
  recentPlays('Plays, last 30 days'),
  length('Length'),
  random('Random');

  final String label;
  const SmartSort(this.label);
}

/// A rule or a nested group.
sealed class SmartNode {
  const SmartNode();
  Map<String, dynamic> toJson();

  static SmartNode? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return raw.containsKey('children') ? SmartGroup.fromJson(raw) : SmartRule.fromJson(raw);
  }
}

class SmartRule extends SmartNode {
  final SmartField field;
  final SmartOp op;

  /// Text, a number, a flag ('true' / 'false') or a count of days, as typed.
  final String value;

  /// [SmartField.recentPlays] only: how many days back plays are counted.
  final int window;

  const SmartRule({required this.field, required this.op, this.value = '', this.window = 30});

  /// A sensible blank rule for [field], so the editor never shows an
  /// operator the field can't use.
  factory SmartRule.blank(SmartField field) => SmartRule(
        field: field,
        op: field.ops.first,
        value: switch (field.kind) {
          SmartFieldKind.flag => 'true',
          SmartFieldKind.days => '30',
          _ => '',
        },
      );

  SmartRule copyWith({SmartField? field, SmartOp? op, String? value, int? window}) =>
      SmartRule(field: field ?? this.field, op: op ?? this.op, value: value ?? this.value, window: window ?? this.window);

  /// A rule with nothing to compare yet matches everything instead of
  /// emptying the playlist while the person is still typing.
  bool get isComplete => field.kind == SmartFieldKind.flag || value.trim().isNotEmpty;

  @override
  Map<String, dynamic> toJson() => {'f': field.name, 'o': op.name, 'v': value, 'w': window};

  static SmartRule? fromJson(Map raw) {
    final field = SmartField.values.where((f) => f.name == raw['f']).firstOrNull;
    final op = SmartOp.values.where((o) => o.name == raw['o']).firstOrNull;
    if (field == null || op == null) return null;
    return SmartRule(
      field: field,
      op: op,
      value: raw['v']?.toString() ?? '',
      window: (raw['w'] as num?)?.toInt() ?? 30,
    );
  }
}

class SmartGroup extends SmartNode {
  /// true: every child must match (AND). false: any child (OR).
  final bool matchAll;
  final List<SmartNode> children;

  const SmartGroup({this.matchAll = true, this.children = const []});

  SmartGroup copyWith({bool? matchAll, List<SmartNode>? children}) =>
      SmartGroup(matchAll: matchAll ?? this.matchAll, children: children ?? this.children);

  /// Rules in this group and its subgroups.
  int get ruleCount => children.fold(0, (n, c) => n + (c is SmartGroup ? c.ruleCount : 1));

  @override
  Map<String, dynamic> toJson() => {'all': matchAll, 'children': [for (final c in children) c.toJson()]};

  factory SmartGroup.fromJson(Map raw) => SmartGroup(
        matchAll: raw['all'] != false,
        children: [for (final c in (raw['children'] as List? ?? const [])) ?SmartNode.fromJson(c)],
      );
}

class SmartPlaylist {
  /// Always 'smart:' plus a number, so it can't collide with a server playlist id and
  /// the same folder store holds both kinds.
  final String id;
  final String name;
  final SmartGroup rules;
  final SmartSort sort;
  final bool ascending;

  /// The most songs to keep after sorting; null keeps every match.
  final int? limit;
  final int createdAt;

  /// The Navidrome playlist last written by "Save as playlist", if any.
  final String? savedPlaylistId;

  static const idPrefix = 'smart:';
  static bool isSmartId(String id) => id.startsWith(idPrefix);

  const SmartPlaylist({
    required this.id,
    required this.name,
    this.rules = const SmartGroup(),
    this.sort = SmartSort.title,
    this.ascending = true,
    this.limit,
    required this.createdAt,
    this.savedPlaylistId,
  });

  SmartPlaylist copyWith({
    String? name,
    SmartGroup? rules,
    SmartSort? sort,
    bool? ascending,
    Object? limit = _keep,
    Object? savedPlaylistId = _keep,
  }) =>
      SmartPlaylist(
        id: id,
        name: name ?? this.name,
        rules: rules ?? this.rules,
        sort: sort ?? this.sort,
        ascending: ascending ?? this.ascending,
        limit: identical(limit, _keep) ? this.limit : limit as int?,
        createdAt: createdAt,
        savedPlaylistId: identical(savedPlaylistId, _keep) ? this.savedPlaylistId : savedPlaylistId as String?,
      );

  static const _keep = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rules': rules.toJson(),
        'sort': sort.name,
        'asc': ascending,
        'limit': limit,
        'createdAt': createdAt,
        'saved': savedPlaylistId,
      };

  static SmartPlaylist? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString() ?? '';
    if (!isSmartId(id)) return null;
    return SmartPlaylist(
      id: id,
      name: raw['name']?.toString() ?? 'Smart Playlist',
      rules: raw['rules'] is Map ? SmartGroup.fromJson(raw['rules'] as Map) : const SmartGroup(),
      sort: SmartSort.values.where((s) => s.name == raw['sort']).firstOrNull ?? SmartSort.title,
      ascending: raw['asc'] != false,
      limit: (raw['limit'] as num?)?.toInt(),
      createdAt: (raw['createdAt'] as num?)?.toInt() ?? 0,
      savedPlaylistId: raw['saved']?.toString(),
    );
  }
}
