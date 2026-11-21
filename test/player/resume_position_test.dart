import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/player/resume_position.dart';

void main() {
  test('the saved position resumes only the song it belongs to', () {
    expect(resumeSeekMs(savedTrackId: 'a', savedMs: 90000, startingTrackId: 'a'), 90000);
  });

  test('a different song starts from the beginning, not where the last one ended', () {
    expect(resumeSeekMs(savedTrackId: 'a', savedMs: 90000, startingTrackId: 'b'), 0);
  });

  test('nothing saved, an unknown song or a negative time starts from the beginning', () {
    expect(resumeSeekMs(savedTrackId: null, savedMs: 5000, startingTrackId: 'a'), 0);
    expect(resumeSeekMs(savedTrackId: 'a', savedMs: 5000, startingTrackId: null), 0);
    expect(resumeSeekMs(savedTrackId: 'a', savedMs: -1, startingTrackId: 'a'), 0);
  });

  test('a position at the very end of the song is not resumed', () {
    expect(resumeSeekMs(savedTrackId: 'a', savedMs: 199000, startingTrackId: 'a', durationMs: 200000), 0);
    expect(resumeSeekMs(savedTrackId: 'a', savedMs: 60000, startingTrackId: 'a', durationMs: 200000), 60000);
  });
}
