import 'package:flutter/foundation.dart';

// =============================================================================
// Library sort model
// Immutable, Hive-persisted sort preference for each library section.
// =============================================================================

/// Sort field for library sections.
enum LibrarySortField { name, recentlyAdded, playCount, duration, artistName }

/// Sort direction.
enum LibrarySortDirection { asc, desc }

/// Immutable sort preference for one library section.
@immutable
class LibrarySortPreference {
  const LibrarySortPreference({
    this.field = LibrarySortField.name,
    this.direction = LibrarySortDirection.asc,
  });

  final LibrarySortField field;
  final LibrarySortDirection direction;

  LibrarySortPreference copyWith({
    LibrarySortField? field,
    LibrarySortDirection? direction,
  }) => LibrarySortPreference(
    field: field ?? this.field,
    direction: direction ?? this.direction,
  );

  /// Flip direction if same field tapped again, otherwise reset to asc.
  LibrarySortPreference toggleField(LibrarySortField tapped) {
    if (tapped == field) {
      return copyWith(
        direction: direction == LibrarySortDirection.asc
            ? LibrarySortDirection.desc
            : LibrarySortDirection.asc,
      );
    }
    return LibrarySortPreference(field: tapped);
  }

  // ── Persistence keys ──────────────────────────────────────────────────────

  static const _fieldKey = 'library_sort_field_';
  static const _dirKey = 'library_sort_dir_';

  String fieldHiveKey(String section) => '$_fieldKey$section';
  String dirHiveKey(String section) => '$_dirKey$section';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibrarySortPreference &&
          runtimeType == other.runtimeType &&
          field == other.field &&
          direction == other.direction;

  @override
  int get hashCode => Object.hash(field, direction);
}
