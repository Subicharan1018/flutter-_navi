/// The equalizer's settings: on/off, the curve, saved presets. Owned by the
/// audio handler so it is applied even when no screen is open.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/hive_boxes.dart';
import '../data/eq_engine.dart';
import 'eq_model.dart';

class EqualizerService extends ChangeNotifier {
  /// Null where there is no equalizer (web).
  final EqEngine? engine;
  final Object? Function(String key) _read;
  final Future<void> Function(String key, Object? value) _write;

  /// Told after the engine changed, so the player can re-apply its headroom.
  VoidCallback? onApplied;

  bool _enabled = false;
  List<double> _gains = flatGains();
  String _presetName = 'Flat';
  List<EqPreset> _custom = [];

  EqualizerService(
    this.engine, {
    Object? Function(String key)? read,
    Future<void> Function(String key, Object? value)? write,
  })  : _read = read ?? _readPrefs,
        _write = write ?? _writePrefs {
    engine?.onOutputChanged = () => unawaited(sync(force: true));
  }

  static Object? _readPrefs(String key) {
    try {
      return HiveBoxes.prefs.get(key);
    } catch (_) {
      return null; // tests and early start: nothing saved yet
    }
  }

  static Future<void> _writePrefs(String key, Object? value) async {
    try {
      await HiveBoxes.prefs.put(key, value);
    } catch (e) {
      debugPrint('⚠️ [Equalizer] could not save $key: $e');
    }
  }

  bool get isSupported => engine != null;
  bool get enabled => _enabled;
  List<double> get gains => List.unmodifiable(_gains);
  List<EqPreset> get customPresets => List.unmodifiable(_custom);

  /// True while the equalizer changes the sound. Off, or on with a flat
  /// curve, leaves the audio path alone.
  bool get isActive => isSupported && _enabled && !isFlat(_gains);

  /// Volume factor the player applies so boosts cannot clip (desktop).
  double get headroom => isActive ? (engine?.headroom ?? 1) : 1;

  /// The preset the curve matches, or null once it has been dragged elsewhere.
  EqPreset? get preset => matchingPreset(_gains, _custom, prefer: _presetName);
  bool get canDelete => _custom.any((p) => p.name == preset?.name);
  bool get canSave => preset == null;

  void load() {
    _enabled = _read(HiveBoxes.kEqualizerEnabled) == true;
    _gains = sanitizeGains(_read(HiveBoxes.kEqualizerCurve));
    _presetName = _read(HiveBoxes.kEqualizerPreset)?.toString() ?? 'Flat';
    final saved = _read(HiveBoxes.kEqualizerPresets);
    _custom = [
      if (saved is List)
        for (final e in saved)
          if (e is Map && e['name'] != null) EqPreset(e['name'].toString(), sanitizeGains(e['gains'])),
    ];
    notifyListeners();
    unawaited(sync());
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    await _write(HiveBoxes.kEqualizerEnabled, value);
    await sync();
  }

  /// One band while it is being dragged; [commitCurve] saves it.
  void setBand(int index, double db) {
    final next = sanitizeGains([..._gains]..[index] = db);
    if (sameGains(next, _gains)) return;
    _gains = next;
    notifyListeners();
    unawaited(sync());
  }

  Future<void> commitCurve() => _write(HiveBoxes.kEqualizerCurve, [..._gains]);

  Future<void> selectPreset(EqPreset p) async {
    _gains = sanitizeGains(p.gains);
    _presetName = p.name;
    notifyListeners();
    await commitCurve();
    await _write(HiveBoxes.kEqualizerPreset, p.name);
    await sync();
  }

  Future<void> reset() => selectPreset(kBuiltInPresets.first);

  /// Saves the curve as [name], replacing a saved preset of that name.
  /// Returns false for an empty name or a built-in one.
  Future<bool> savePreset(String name) async {
    final n = name.trim();
    if (n.isEmpty || isBuiltInPresetName(n)) return false;
    _custom = [
      ..._custom.where((p) => p.name.toLowerCase() != n.toLowerCase()),
      EqPreset(n, [..._gains]),
    ];
    await _writeCustom();
    _presetName = n;
    notifyListeners();
    await _write(HiveBoxes.kEqualizerPreset, n);
    return true;
  }

  /// Deletes the saved preset shown now. The curve stays as it is.
  Future<void> deletePreset() async {
    final name = preset?.name;
    if (name == null || !canDelete) return;
    _custom = _custom.where((p) => p.name != name).toList();
    notifyListeners();
    await _writeCustom();
  }

  Future<void> _writeCustom() => _write(HiveBoxes.kEqualizerPresets, [
        for (final p in _custom) {'name': p.name, 'gains': p.gains},
      ]);

  Future<void>? _syncing;
  bool _dirty = false;
  List<double>? _applied;

  /// Brings the engine in line with the settings. Calls that arrive while one
  /// is running collapse into a single follow-up with the newest curve.
  /// A refusal is retried by the next call.
  Future<void> sync({bool force = false}) {
    if (force) _applied = null;
    _dirty = true;
    return _syncing ??= _drain();
  }

  Future<void> _drain() async {
    // Yield first: if this ran to the end synchronously, the `finally` would
    // clear [_syncing] before [sync] had stored it.
    await null;
    try {
      while (_dirty) {
        _dirty = false;
        final engine = this.engine;
        if (engine == null) return;
        final want = isActive ? [..._gains] : null;
        final have = _applied;
        if (want == null ? have == null : have != null && sameGains(want, have)) continue;
        try {
          await engine.apply(want);
          _applied = want;
        } catch (e) {
          _applied = null;
          debugPrint('⚠️ [Equalizer] not applied: $e');
        }
        onApplied?.call();
      }
    } finally {
      _syncing = null;
    }
  }

  @override
  void dispose() {
    engine?.dispose();
    super.dispose();
  }
}
