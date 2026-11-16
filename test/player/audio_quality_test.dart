import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/player/audio_quality.dart';
import 'package:navivibe/player/player_controls.dart' show qualityLabel;

Song _s({String suffix = '', int bitRate = 0, int depth = 0, int rate = 0}) => Song(
      id: 'x',
      title: 't',
      artist: 'a',
      album: 'b',
      coverArt: 'x',
      duration: 200,
      track: 1,
      year: 2024,
      suffix: suffix,
      bitRate: bitRate,
      bitDepth: depth,
      samplingRate: rate,
    );

void main() {
  group('AudioQualityLabel', () {
    test('FLAC 24-bit / 96 kHz', () {
      expect(AudioQualityLabel.of(_s(suffix: 'flac', bitRate: 3000, depth: 24, rate: 96000)), 'Lossless · FLAC · 24-bit/96 kHz');
    });

    test('CD quality shows 44.1 kHz', () {
      expect(AudioQualityLabel.of(_s(suffix: 'flac', depth: 16, rate: 44100)), 'Lossless · FLAC · 16-bit/44.1 kHz');
    });

    test('lossless with no depth or rate is just the codec', () {
      expect(AudioQualityLabel.of(_s(suffix: 'flac', bitRate: 900)), 'Lossless · FLAC');
      expect(AudioQualityLabel.of(_s(suffix: 'flac', rate: 48000)), 'Lossless · FLAC · 48 kHz');
    });

    test('MP3 320', () {
      expect(AudioQualityLabel.of(_s(suffix: 'mp3', bitRate: 320)), 'MP3 · 320 kbps');
    });

    test('FLAC transcoded to MP3 192 says so and drops the lossless claim', () {
      final label = AudioQualityLabel.of(
        _s(suffix: 'flac', bitRate: 1411, depth: 24, rate: 96000),
        stream: const StreamQuality(format: 'mp3', maxBitRate: 192),
      );
      expect(label, 'MP3 · 192 kbps (converted)');
    });

    test('transcoding settings that change nothing do not say converted', () {
      final stream = const StreamQuality(format: 'mp3', maxBitRate: 320);
      expect(AudioQualityLabel.of(_s(suffix: 'mp3', bitRate: 256), stream: stream), 'MP3 · 256 kbps');
      expect(AudioQualityLabel.of(_s(suffix: 'flac', depth: 16, rate: 44100), stream: const StreamQuality()), 'Lossless · FLAC · 16-bit/44.1 kHz');
      expect(AudioQualityLabel.of(_s(suffix: 'flac'), stream: const StreamQuality(format: 'raw')), 'Lossless · FLAC');
    });

    test('a lossy file above the ceiling is converted down to it', () {
      expect(
        AudioQualityLabel.of(_s(suffix: 'mp3', bitRate: 320), stream: const StreamQuality(maxBitRate: 128)),
        '128 kbps (converted)',
      );
    });

    test('a file on this device is never called converted', () {
      expect(
        AudioQualityLabel.of(_s(suffix: 'flac', depth: 24, rate: 96000), stream: const StreamQuality.local()),
        'Lossless · FLAC · 24-bit/96 kHz',
      );
      expect(AudioQualityLabel.of(_s(suffix: 'm4a', bitRate: 256), stream: const StreamQuality.local()), 'M4A · 256 kbps');
    });

    test('a local file shows what the tags gave', () {
      expect(AudioQualityLabel.of(_s(suffix: 'wav')), 'Lossless · WAV');
      expect(AudioQualityLabel.of(_s(suffix: 'opus')), 'OPUS');
    });

    test('missing fields give no label', () {
      expect(AudioQualityLabel.of(_s()), isNull);
      expect(AudioQualityLabel.of(_s(), stream: const StreamQuality(format: 'mp3')), 'MP3 (converted)');
    });
  });

  group('Song audio fields', () {
    test('read OpenSubsonic bitDepth, samplingRate and channelCount, and round-trip', () {
      final song = Song.fromJson({'id': '1', 'suffix': 'flac', 'bitDepth': 24, 'samplingRate': 96000, 'channelCount': 2});
      expect((song.bitDepth, song.samplingRate, song.channelCount), (24, 96000, 2));
      final again = Song.fromJson(song.toMap());
      expect((again.bitDepth, again.samplingRate, again.channelCount), (24, 96000, 2));
      expect(song.copyWith(rating: 3).bitDepth, 24);
      expect(Song.fromJson({'id': '2'}).bitDepth, 0);
    });
  });

  testWidgets('the label shows between the times, and nothing when unknown', (tester) async {
    Widget host(String? text) => MaterialApp(
          home: Scaffold(body: Center(child: Text(text ?? '', key: const ValueKey('q')))),
        );
    // The Scrubber needs a live player; its text comes from qualityLabel.
    expect(qualityLabel(_s(suffix: 'flac', depth: 24, rate: 96000)), 'Lossless · FLAC · 24-bit/96 kHz');
    expect(qualityLabel(_s()), isNull);
    await tester.pumpWidget(host(qualityLabel(_s(suffix: 'mp3', bitRate: 320))));
    expect(find.text('MP3 · 320 kbps'), findsOneWidget);
  });
}
