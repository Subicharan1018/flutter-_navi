import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/services/desktop_registration.dart';

void main() {
  group('audioFilesFromArgs', () {
    test('keeps existing audio files in order, drops flags, other files and repeats', () {
      final args = ['--minimized', r'C:\m\a.FLAC', 'notes.txt', r'C:\m\b.opus', r'C:\m\a.FLAC', r'C:\m\gone.mp3', '-x.mp3'];
      final got = audioFilesFromArgs(args, exists: (p) => !p.contains('gone'));
      expect(got, [r'C:\m\a.FLAC', r'C:\m\b.opus']);
    });

    test('covers every registered type', () {
      for (final e in audioExtensions) {
        expect(audioFilesFromArgs(['song$e'], exists: (_) => true), ['song$e']);
      }
    });
  });

  group('windowsRegistrationReg', () {
    final reg = windowsRegistrationReg(r'C:\Users\a b\AppData\Local\NaviVibe\current\navivibe.exe');

    test('registers the ProgId with an escaped open command', () {
      expect(reg, startsWith('Windows Registry Editor Version 5.00'));
      expect(reg, contains(r'[HKEY_CURRENT_USER\Software\Classes\NaviVibe.Audio\shell\open\command]'));
      expect(reg, contains(r'@="\"C:\\Users\\a b\\AppData\\Local\\NaviVibe\\current\\navivibe.exe\" \"%1\""'));
    });

    test('every file type gets OpenWithProgids and a capability association', () {
      for (final e in audioExtensions) {
        final b = String.fromCharCode(92);
        expect(reg, contains('[HKEY_CURRENT_USER${b}Software${b}Classes$b$e${b}OpenWithProgids]${String.fromCharCodes([13, 10])}"$windowsProgId"=hex(0):'));
        expect(reg, contains('"$e"="$windowsProgId"'));
      }
    });

    test('is listed under Default apps', () {
      expect(reg, contains(r'"NaviVibe"="Software\\NaviVibe\\Capabilities"'));
      expect(reg, contains(r'[HKEY_CURRENT_USER\Software\NaviVibe\Capabilities\FileAssociations]'));
    });

    test('writes only under HKCU', () {
      final keys = RegExp(r'^\[(.+)\]$', multiLine: true).allMatches(reg).map((m) => m.group(1)!);
      expect(keys, isNotEmpty);
      expect(keys.every((k) => k.startsWith(r'HKEY_CURRENT_USER\')), isTrue);
    });
  });

  test('registerWindowsFileTypes imports a UTF-16 .reg file and removes it', () async {
    List<String>? args;
    List<int>? bytes;
    await registerWindowsFileTypes(
      exe: r'C:\n\navivibe.exe',
      run: (a) async {
        args = a;
        bytes = await File(a[1]).readAsBytes();
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(args!.first, 'import');
    expect(bytes!.take(2), [0xFF, 0xFE]);
    expect(File(args![1]).existsSync(), isFalse);
  });

  test('pathsFromForwarded splits a newline string and accepts a list', () {
    expect(pathsFromForwarded('a.mp3\nb.flac\n'), ['a.mp3', 'b.flac']);
    expect(pathsFromForwarded(['a.mp3', 3, '']), ['a.mp3']);
    expect(pathsFromForwarded(null), isEmpty);
  });
}
