import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../core/hive_boxes.dart';

class TranscodeBitrate {
  static const int original = 0;
  static const int kbps64 = 64;
  static const int kbps128 = 128;
  static const int kbps192 = 192;
  static const int kbps256 = 256;
  static const int kbps320 = 320;

  static const List<int> options = [
    original,
    kbps64,
    kbps128,
    kbps192,
    kbps256,
    kbps320,
  ];

  static String getLabel(int bitrate) {
    if (bitrate == original) return 'Original (No Transcoding)';
    return '$bitrate kbps';
  }
}

class TranscodeFormat {
  static const String original = 'raw';
  static const String mp3 = 'mp3';
  static const String opus = 'opus';
  static const String aac = 'aac';

  static const List<String> options = [original, mp3, opus, aac];

  static String getLabel(String format) {
    switch (format) {
      case original:
        return 'Original';
      case mp3:
        return 'MP3';
      case opus:
        return 'Opus';
      case aac:
        return 'AAC';
      default:
        return format.toUpperCase();
    }
  }
}

enum ConnectionType { wifi, mobile }

class TranscodingService extends ChangeNotifier {
  int _wifiBitrate = TranscodeBitrate.original;
  int _mobileBitrate = TranscodeBitrate.kbps192;
  String _format = TranscodeFormat.mp3;
  bool _enabled = false;
  bool _smartEnabled = false;
  ConnectionType _currentConnectionType = ConnectionType.wifi;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  int get wifiBitrate => _wifiBitrate;
  int get mobileBitrate => _mobileBitrate;
  String get format => _format;
  bool get enabled => _enabled;
  bool get smartEnabled => _smartEnabled;
  ConnectionType get currentConnectionType => _currentConnectionType;

  TranscodingService() {
    _loadFromHive();
  }

  void _loadFromHive() {
    final box = HiveBoxes.audio;
    
    final wifiVal = box.get(HiveBoxes.kWifiBitrate, defaultValue: TranscodeBitrate.original);
    _wifiBitrate = wifiVal is int ? wifiVal : TranscodeBitrate.original;
    
    final mobileVal = box.get(HiveBoxes.kMobileBitrate, defaultValue: TranscodeBitrate.kbps192);
    _mobileBitrate = mobileVal is int ? mobileVal : TranscodeBitrate.kbps192;
    
    _format = box.get(HiveBoxes.kTranscodeFormat, defaultValue: TranscodeFormat.mp3)?.toString() ?? TranscodeFormat.mp3;
    
    final enabledVal = box.get(HiveBoxes.kTranscodingEnabled, defaultValue: false);
    _enabled = enabledVal is bool ? enabledVal : false;
    
    final smartVal = box.get(HiveBoxes.kSmartSwitchEnabled, defaultValue: false);
    _smartEnabled = smartVal is bool ? smartVal : false;
    
    final connVal = box.get(HiveBoxes.kConnectionType, defaultValue: 0);
    final connectionIndex = connVal is int ? connVal : 0;
    _currentConnectionType = ConnectionType.values[connectionIndex.clamp(0, ConnectionType.values.length - 1)];

    if (_smartEnabled) {
      _initConnectivityWatcher();
    }

    notifyListeners();
  }

  Future<void> _initConnectivityWatcher() async {
    final result = await Connectivity().checkConnectivity();
    _updateConnectionType(result);

    _connectivitySub?.cancel();
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_updateConnectionType);
  }

  void _updateConnectionType(List<ConnectivityResult> results) {
    final newType = results.contains(ConnectivityResult.wifi)
        ? ConnectionType.wifi
        : ConnectionType.mobile;

    if (newType != _currentConnectionType) {
      _currentConnectionType = newType;
      debugPrint(
        '[Transcoding] Network changed → ${newType.name} '
        '(bitrate: ${getCurrentBitrate() ?? "original"})',
      );
      notifyListeners();
    }
  }

  void _stopConnectivityWatcher() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await HiveBoxes.audio.put(HiveBoxes.kTranscodingEnabled, value);
    notifyListeners();
  }

  Future<void> setSmartEnabled(bool value) async {
    _smartEnabled = value;
    await HiveBoxes.audio.put(HiveBoxes.kSmartSwitchEnabled, value);
    if (value) {
      await _initConnectivityWatcher();
    } else {
      _stopConnectivityWatcher();
    }
    notifyListeners();
  }

  Future<void> setWifiBitrate(int bitrate) async {
    _wifiBitrate = bitrate;
    await HiveBoxes.audio.put(HiveBoxes.kWifiBitrate, bitrate);
    notifyListeners();
  }

  Future<void> setMobileBitrate(int bitrate) async {
    _mobileBitrate = bitrate;
    await HiveBoxes.audio.put(HiveBoxes.kMobileBitrate, bitrate);
    notifyListeners();
  }

  Future<void> setFormat(String format) async {
    _format = format;
    await HiveBoxes.audio.put(HiveBoxes.kTranscodeFormat, format);
    notifyListeners();
  }

  Future<void> setConnectionType(ConnectionType type) async {
    _currentConnectionType = type;
    await HiveBoxes.audio.put(HiveBoxes.kConnectionType, type.index);
    notifyListeners();
  }

  int? getCurrentBitrate() {
    if (!_enabled) return null;
    final bitrate = _currentConnectionType == ConnectionType.wifi
        ? _wifiBitrate
        : _mobileBitrate;
    return bitrate == TranscodeBitrate.original ? null : bitrate;
  }

  String? getCurrentFormat() {
    if (!_enabled) return null;
    return _format == TranscodeFormat.original ? null : _format;
  }

  @override
  void dispose() {
    _stopConnectivityWatcher();
    super.dispose();
  }
}
