import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/platform_utils.dart';

// =============================================================================
// desktop_registration.dart — NaviVibe as a music player on the desktop.
//
//  * [audioFilesFromArgs]: the audio files named on the command line (Explorer
//    "Open with", a file manager, `navivibe song.flac`).
//  * [windowsRegistrationReg]: the per-user registry entries (ProgId, file
//    types, Applications\ key, Capabilities, RegisteredApplications) that make
//    Windows list NaviVibe under Default apps and "Open with". HKCU only: no
//    admin rights, nothing to uninstall system-wide.
//
// How to check it: docs/platform-registration.md.
// =============================================================================

/// File types NaviVibe opens.
const audioExtensions = ['.mp3', '.flac', '.m4a', '.ogg', '.opus', '.wav'];

/// The ProgId all [audioExtensions] point at.
const windowsProgId = 'NaviVibe.Audio';

/// The existing audio files among [args] (flags and anything else ignored),
/// in order, without repeats.
List<String> audioFilesFromArgs(List<String> args, {bool Function(String path)? exists}) {
  final check = exists ?? (p) => File(p).existsSync();
  final seen = <String>{};
  return [
    for (final a in args)
      if (!a.startsWith('-') && _isAudio(a) && check(a) && seen.add(a)) a,
  ];
}

bool _isAudio(String path) {
  final dot = path.lastIndexOf('.');
  return dot >= 0 && audioExtensions.contains(path.substring(dot).toLowerCase());
}

/// The text of a `.reg` file registering NaviVibe for [exe]; `reg import`
/// applies it in one process and it is safe to apply on every launch.
String windowsRegistrationReg(String exe) {
  String q(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  final command = q('"$exe" "%1"');
  const classes = r'HKEY_CURRENT_USER\Software\Classes';
  const caps = r'HKEY_CURRENT_USER\Software\NaviVibe\Capabilities';
  final b = StringBuffer('Windows Registry Editor Version 5.00\r\n');
  void key(String path, Map<String, String> values) {
    b.write('\r\n[$path]\r\n');
    values.forEach((name, data) => b.write('${name == '@' ? '@' : '"$name"'}=$data\r\n'));
  }

  String s(String v) => '"${q(v)}"';
  key('$classes\\$windowsProgId', {'@': s('NaviVibe audio file'), 'FriendlyTypeName': s('NaviVibe audio file')});
  key('$classes\\$windowsProgId\\DefaultIcon', {'@': s('$exe,0')});
  key('$classes\\$windowsProgId\\shell\\open', {'FriendlyAppName': s('NaviVibe')});
  key('$classes\\$windowsProgId\\shell\\open\\command', {'@': '"$command"'});
  key('$classes\\Applications\\navivibe.exe', {'FriendlyAppName': s('NaviVibe')});
  key('$classes\\Applications\\navivibe.exe\\shell\\open\\command', {'@': '"$command"'});
  key('$classes\\Applications\\navivibe.exe\\SupportedTypes', {for (final e in audioExtensions) e: s('')});
  for (final e in audioExtensions) {
    // hex(0) is REG_NONE: the value name is the entry, so "Open with" lists us.
    key('$classes\\$e\\OpenWithProgids', {windowsProgId: 'hex(0):'});
  }
  key(caps, {
    'ApplicationName': s('NaviVibe'),
    'ApplicationDescription': s('NaviVibe music player'),
    'ApplicationIcon': s('$exe,0'),
  });
  key('$caps\\FileAssociations', {for (final e in audioExtensions) e: s(windowsProgId)});
  key(r'HKEY_CURRENT_USER\Software\RegisteredApplications', {'NaviVibe': s(r'Software\NaviVibe\Capabilities')});
  return b.toString();
}

/// Applies [windowsRegistrationReg] for the running exe. Release builds on
/// Windows only: a debug run must not claim file types for a build folder.
Future<void> registerWindowsFileTypes({String? exe, Future<ProcessResult> Function(List<String>)? run}) async {
  if (run == null && (!PlatformUtils.isWindows || !kReleaseMode)) return;
  File? file;
  try {
    file = File('${Directory.systemTemp.path}${Platform.pathSeparator}navivibe_register.reg');
    final text = windowsRegistrationReg(exe ?? Platform.resolvedExecutable);
    // reg.exe reads UTF-16 LE with a byte-order mark, so non-ASCII user names survive.
    final bytes = <int>[0xFF, 0xFE];
    for (final u in text.codeUnits) {
      bytes..add(u & 0xFF)..add(u >> 8);
    }
    await file.writeAsBytes(bytes, flush: true);
    final r = await (run ?? (a) => Process.run('reg', a))(['import', file.path]);
    if (r.exitCode != 0) debugPrint('[Register] reg import failed: ${r.stderr}');
  } catch (e) {
    debugPrint('[Register] file types not registered: $e');
  } finally {
    try {
      await file?.delete();
    } catch (_) {}
  }
}

/// Decodes the paths a second launch forwards (newline separated).
List<String> pathsFromForwarded(Object? raw) => raw is List
    ? [for (final p in raw) if (p is String && p.isNotEmpty) p]
    : raw is String
    ? const LineSplitter().convert(raw).where((p) => p.isNotEmpty).toList()
    : const [];
