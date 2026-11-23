import '../data/exportify_models.dart';

/// Decides which finished imports the person has not been told about yet.
///
/// The server's status carries an optional `finished` record per import; each
/// run's identity is `<import id>:<finished_at>`. The first time this runs on a
/// device ([seen] null) everything already finished is remembered without a
/// notification, so an update of the app does not announce old imports.
class ImportFinishedCheck {
  final List<String> seen;
  final int fetched;
  final int failed;

  /// Imports newly finished (none: nothing to announce).
  final int imports;
  const ImportFinishedCheck({required this.seen, required this.fetched, required this.failed, required this.imports});

  bool get announce => imports > 0;
}

ImportFinishedCheck checkFinishedImports(List<ExportifySummary> all, List<String>? seen) {
  String key(ExportifySummary s) => '${s.id}:${s.finished!.finishedAt}';
  final finished = [for (final s in all) if (s.finished != null) s];
  final known = {...?seen};
  final fresh = [for (final s in finished) if (!known.contains(key(s))) s];
  final next = [...?seen, for (final s in fresh) key(s)];
  // Keep the list short: only recent runs can come back.
  final trimmed = next.length > 60 ? next.sublist(next.length - 60) : next;
  if (seen == null) return ImportFinishedCheck(seen: trimmed, fetched: 0, failed: 0, imports: 0);
  return ImportFinishedCheck(
    seen: trimmed,
    fetched: fresh.fold(0, (a, s) => a + s.finished!.fetched),
    failed: fresh.fold(0, (a, s) => a + s.finished!.failed),
    imports: fresh.length,
  );
}

/// The notification for [c]: songs added, and how many could not be.
({String title, String body}) importFinishedText(ImportFinishedCheck c) {
  String songs(int n) => n == 1 ? '1 song' : '$n songs';
  final added = c.fetched == 0 ? 'No new songs were added' : '${songs(c.fetched)} added';
  return (
    title: 'Your import finished',
    body: c.failed > 0 ? 'Your import finished: $added. ${songs(c.failed)} couldn’t be fetched.' : 'Your import finished: $added.',
  );
}
