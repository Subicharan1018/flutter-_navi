import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for cover art. The default manager keeps 200 files for 30 days,
/// which a few screens of covers (each cover in several sizes) can fill, so
/// covers kept being fetched again. Covers are small; keep many, for longer.
final CacheManager coverCacheManager = CacheManager(
  Config(
    'naviCovers',
    stalePeriod: const Duration(days: 90),
    maxNrOfCacheObjects: 2000,
  ),
);
