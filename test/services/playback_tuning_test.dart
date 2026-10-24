import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/services/playback_tuning.dart';

Song _song({
  String id = 'a',
  String album = 'Album',
  int track = 1,
  double? trackGain,
  double? albumGain,
  double? trackPeak,
  double? albumPeak,
}) => Song(
  id: id,
  title: 't',
  artist: 'x',
  album: album,
  coverArt: id,
  duration: 200,
  track: track,
  year: 2020,
  trackGain: trackGain,
  albumGain: albumGain,
  trackPeak: trackPeak,
  albumPeak: albumPeak,
);

void main() {
  group('Song replayGain parsing', () {
    test('reads the nested Subsonic object and round-trips via toMap', () {
      final s = Song.fromJson({
        'id': '1',
        'replayGain': {
          'trackGain': -7.5,
          'albumGain': '-6.2',
          'trackPeak': 0.98,
        },
      });
      expect(s.trackGain, -7.5);
      expect(s.albumGain, -6.2);
      expect(s.trackPeak, 0.98);
      expect(s.albumPeak, isNull);
      final again = Song.fromJson(s.toMap());
      expect(again.trackGain, -7.5);
      expect(again.albumGain, -6.2);
    });

    test('is null when the tag is absent', () {
      final s = Song.fromJson({'id': '1'});
      expect(s.trackGain, isNull);
      expect(s.toMap().containsKey('replayGain'), isFalse);
    });
  });

  group('replayGainVolume', () {
    test('off and untagged songs play at full volume', () {
      expect(replayGainVolume(_song(trackGain: -6), ReplayGainMode.off), 1.0);
      expect(replayGainVolume(_song(), ReplayGainMode.track), 1.0);
    });

    test('negative gain attenuates by 10^(dB/20)', () {
      final v = replayGainVolume(_song(trackGain: -6), ReplayGainMode.track);
      expect(v, closeTo(math.pow(10, -6 / 20), 1e-9));
    });

    test('never exceeds 1.0 for positive gain', () {
      expect(replayGainVolume(_song(trackGain: 9), ReplayGainMode.track), 1.0);
    });

    test('album mode uses album gain and falls back to track gain', () {
      final both = _song(trackGain: -3, albumGain: -10);
      expect(
        replayGainVolume(both, ReplayGainMode.album),
        closeTo(math.pow(10, -10 / 20), 1e-9),
      );
      final onlyTrack = _song(trackGain: -3);
      expect(
        replayGainVolume(onlyTrack, ReplayGainMode.album),
        closeTo(math.pow(10, -3 / 20), 1e-9),
      );
    });

    test('peak above full scale caps the volume so it cannot clip', () {
      // -1 dB gain is 0.891, but a 1.5 peak needs <= 0.667.
      final v = replayGainVolume(
        _song(trackGain: -1, trackPeak: 1.5),
        ReplayGainMode.track,
      );
      expect(v, closeTo(1 / 1.5, 1e-9));
    });

    test('non-finite gain is ignored', () {
      expect(
        replayGainVolume(_song(trackGain: double.nan), ReplayGainMode.track),
        1.0,
      );
    });
  });

  group('clamps', () {
    test('speed stays within 0.5–2', () {
      expect(clampPlaybackSpeed(0.1), 0.5);
      expect(clampPlaybackSpeed(5), 2.0);
      expect(clampPlaybackSpeed(1.25), 1.25);
    });
    test('crossfade stays within 0–12', () {
      expect(clampCrossfadeSeconds(-3), 0);
      expect(clampCrossfadeSeconds(99), 12);
    });
  });

  group('crossfade scheduling', () {
    test('album-continuous tracks stay gapless', () {
      final a = _song(id: 'a', track: 3);
      final b = _song(id: 'b', track: 4);
      expect(isAlbumContinuous(a, b), isTrue);
      expect(shouldCrossfade(fadeSeconds: 6, current: a, next: b), isFalse);
    });

    test('different album or non-consecutive track crossfades', () {
      final a = _song(id: 'a', track: 3);
      expect(
        shouldCrossfade(
          fadeSeconds: 6,
          current: a,
          next: _song(id: 'b', album: 'Other', track: 4),
        ),
        isTrue,
      );
      expect(
        shouldCrossfade(
          fadeSeconds: 6,
          current: a,
          next: _song(id: 'c', track: 9),
        ),
        isTrue,
      );
    });

    test('no fade when disabled, at queue end, or repeating one song', () {
      final a = _song(id: 'a');
      final b = _song(id: 'b', album: 'Other');
      expect(shouldCrossfade(fadeSeconds: 0, current: a, next: b), isFalse);
      expect(shouldCrossfade(fadeSeconds: 6, current: a, next: null), isFalse);
      expect(shouldCrossfade(fadeSeconds: 6, current: a, next: a), isFalse);
    });

    double gain(int pos, {bool out = true, bool inn = true}) => crossfadeGain(
      positionMs: pos,
      durationMs: 200000,
      fadeSeconds: 6,
      fadeOut: out,
      fadeIn: inn,
    );

    test('full volume mid-track', () {
      expect(gain(100000), 1.0);
    });

    test('ramps down over the final half of the fade', () {
      expect(gain(197000), 1.0); // 3 s left == start of ramp
      expect(gain(198500), closeTo(math.sin(0.5 * math.pi / 2), 1e-9));
      expect(gain(200000), closeTo(0.0, 1e-9));
      expect(gain(199000), lessThan(gain(198000)));
    });

    test('ramps up over the first half when fading in', () {
      expect(gain(0), closeTo(0.0, 1e-9));
      expect(gain(1500), closeTo(math.sin(0.5 * math.pi / 2), 1e-9));
      expect(gain(3000), 1.0);
      expect(gain(0, inn: false), 1.0);
    });

    test('fade-out is skipped when not requested', () {
      expect(gain(199500, out: false), 1.0);
    });

    test('very short tracks never fade past half their length', () {
      final g = crossfadeGain(
        positionMs: 1000,
        durationMs: 2000,
        fadeSeconds: 12,
        fadeOut: true,
        fadeIn: true,
      );
      expect(g, closeTo(1.0, 1e-9)); // span 1000 ms: both ramps meet at peak
    });

    test('zero fade or unknown duration is a no-op', () {
      expect(
        crossfadeGain(
          positionMs: 10,
          durationMs: 1000,
          fadeSeconds: 0,
          fadeOut: true,
          fadeIn: true,
        ),
        1.0,
      );
      expect(
        crossfadeGain(
          positionMs: 10,
          durationMs: 0,
          fadeSeconds: 6,
          fadeOut: true,
          fadeIn: true,
        ),
        1.0,
      );
    });
  });
}
