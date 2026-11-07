import 'package:flutter/foundation.dart';

import '../../../core/hive_boxes.dart';

/// The desktop shell's own, remembered layout: how wide the library rail and the
/// right panel are, and whether the rail is collapsed to icons. Each is a
/// [ValueNotifier] so only the pane that uses it rebuilds while it is dragged;
/// the value is saved when a drag ends.
abstract final class DesktopLayout {
  static const railDefault = 264.0, railMin = 208.0, railMax = 420.0, railIcons = 72.0;
  static const panelDefault = 340.0, panelMin = 280.0, panelMax = 560.0;

  static const _kRail = 'desktop_rail_width';
  static const _kCollapsed = 'desktop_rail_collapsed';
  static const _kPanel = 'desktop_panel_width';
  static const _kLibraryGrid = 'desktop_library_grid';

  static final railWidth = ValueNotifier<double>(_readDouble(_kRail, railDefault, railMin, railMax));
  static final railCollapsed = ValueNotifier<bool>(_readBool(_kCollapsed));
  /// The Library page: tiles (true) or a list (false).
  static final libraryGrid = ValueNotifier<bool>(_readBool(_kLibraryGrid, true));
  static void setLibraryGrid(bool v) {
    libraryGrid.value = v;
    _save(_kLibraryGrid, v);
  }

  static const _kHiddenColumns = 'desktop_table_hidden_columns';

  /// Song-table columns the person turned off ("album", "added"); the choice is
  /// shared by every song table and remembered.
  static final hiddenColumns = ValueNotifier<Set<String>>(_readSet(_kHiddenColumns));

  static Set<String> _readSet(String key) {
    try {
      final v = HiveBoxes.prefs.get(key);
      if (v is List) return {for (final e in v) e.toString()};
    } catch (_) {}
    return {};
  }

  static void toggleColumn(String name) {
    final next = {...hiddenColumns.value};
    if (!next.remove(name)) next.add(name);
    hiddenColumns.value = next;
    _save(_kHiddenColumns, next.toList());
  }

  static final panelWidth =ValueNotifier<double>(_readDouble(_kPanel, panelDefault, panelMin, panelMax));

  static double _readDouble(String key, double fallback, double min, double max) {
    try {
      final v = HiveBoxes.prefs.get(key);
      if (v is num) return v.toDouble().clamp(min, max);
    } catch (_) {}
    return fallback;
  }

  static bool _readBool(String key, [bool fallback = false]) {
    try {
      final v = HiveBoxes.prefs.get(key);
      return v is bool ? v : fallback;
    } catch (_) {
      return fallback;
    }
  }

  static void _save(String key, Object value) {
    try {
      HiveBoxes.prefs.put(key, value).ignore();
    } catch (_) {}
  }

  /// While dragging: change the width, don't save yet.
  static void dragRail(double width) => railWidth.value = width.clamp(railMin, railMax);
  static void dragPanel(double width) => panelWidth.value = width.clamp(panelMin, panelMax);

  /// A drag ended (or the key was released): remember it.
  static void saveRail() => _save(_kRail, railWidth.value);
  static void savePanel() => _save(_kPanel, panelWidth.value);

  static void resetRail() {
    railWidth.value = railDefault;
    saveRail();
  }

  static void resetPanel() {
    panelWidth.value = panelDefault;
    savePanel();
  }

  static void setCollapsed(bool v) {
    railCollapsed.value = v;
    _save(_kCollapsed, v);
  }

  /// For tests: back to the defaults, nothing saved.
  @visibleForTesting
  static void debugReset() {
    railWidth.value = railDefault;
    panelWidth.value = panelDefault;
    railCollapsed.value = false;
    hiddenColumns.value = {};
  }
}
