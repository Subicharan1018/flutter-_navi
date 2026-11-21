/// Where a song should start when the app remembers a position from before it
/// was closed.
///
/// The remembered time belongs to one song. It resumes that song only: any
/// other song starts at zero (before this check, the first song played after a
/// restart began at the old song's position). A position within the last few
/// seconds counts as finished, so the song starts over.
int resumeSeekMs({
  required String? savedTrackId,
  required int savedMs,
  required String? startingTrackId,
  int? durationMs,
}) {
  if (savedTrackId == null || startingTrackId == null || savedTrackId != startingTrackId) return 0;
  if (savedMs <= 0) return 0;
  if (durationMs != null && durationMs > 0 && savedMs >= durationMs - 5000) return 0;
  return savedMs;
}
