/// One downloadable file listed in latest.json.
class UpdateFile {
  final String name;
  final int size;
  final String sha256;
  const UpdateFile({required this.name, required this.size, required this.sha256});

  factory UpdateFile.fromJson(Map<String, dynamic> j) => UpdateFile(
        name: j['name'] as String,
        size: (j['size'] as num).toInt(),
        sha256: (j['sha256'] as String).toLowerCase(),
      );
}

/// A binary patch that turns one exact earlier APK into [UpdateAbi.full].
class UpdatePatch extends UpdateFile {
  final int fromBuild;
  final String fromSha256;
  const UpdatePatch({
    required super.name,
    required super.size,
    required super.sha256,
    required this.fromBuild,
    required this.fromSha256,
  });

  factory UpdatePatch.fromJson(Map<String, dynamic> j) {
    final f = UpdateFile.fromJson(j);
    return UpdatePatch(
      name: f.name,
      size: f.size,
      sha256: f.sha256,
      fromBuild: (j['fromBuild'] as num).toInt(),
      fromSha256: (j['fromSha256'] as String).toLowerCase(),
    );
  }
}

class UpdateAbi {
  final UpdateFile full;
  final List<UpdatePatch> patches;
  const UpdateAbi({required this.full, required this.patches});

  factory UpdateAbi.fromJson(Map<String, dynamic> j) => UpdateAbi(
        full: UpdateFile.fromJson(j),
        patches: [
          for (final p in (j['patches'] as List? ?? const [])) UpdatePatch.fromJson(p as Map<String, dynamic>),
        ],
      );
}

/// latest.json, written by tool/release/package_release.py.
class UpdateManifest {
  final String version;
  final int build;
  final String tag;
  final String notes;
  final DateTime? published;

  /// Where the files live for public repositories; empty otherwise.
  final String assetBase;
  final Map<String, UpdateAbi> abis;
  final UpdateFile? universal;
  final UpdateFile? windowsSetup;

  const UpdateManifest({
    required this.version,
    required this.build,
    required this.tag,
    required this.notes,
    required this.published,
    required this.assetBase,
    required this.abis,
    required this.universal,
    required this.windowsSetup,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> j) {
    final android = (j['android'] as Map?)?.cast<String, dynamic>() ?? const {};
    final abis = (android['abis'] as Map?)?.cast<String, dynamic>() ?? const {};
    final win = (j['windows'] as Map?)?.cast<String, dynamic>();
    return UpdateManifest(
      version: j['version'] as String,
      build: (j['build'] as num).toInt(),
      tag: (j['tag'] as String?) ?? 'v${j['version']}+${j['build']}',
      notes: (j['notes'] as String?)?.trim() ?? '',
      published: DateTime.tryParse((j['published'] as String?) ?? ''),
      assetBase: (j['assetBase'] as String?) ?? '',
      abis: {
        for (final e in abis.entries) e.key: UpdateAbi.fromJson((e.value as Map).cast<String, dynamic>()),
      },
      universal: android['universal'] is Map
          ? UpdateFile.fromJson((android['universal'] as Map).cast<String, dynamic>())
          : null,
      windowsSetup: win?['setup'] is Map ? UpdateFile.fromJson((win!['setup'] as Map).cast<String, dynamic>()) : null,
    );
  }
}

/// What to download to get from the installed build to [UpdateManifest].
class UpdatePlan {
  final UpdateManifest manifest;
  final UpdateFile full;

  /// Null when no patch matches the installed APK.
  final UpdatePatch? patch;

  const UpdatePlan({required this.manifest, required this.full, required this.patch});

  /// Bytes the user will actually download.
  int get downloadSize => patch?.size ?? full.size;
  bool get isDelta => patch != null;
}

/// Picks the download for an Android device.
///
/// [abis] is the device's ABI list, best first. [installedSha256] is the
/// SHA-256 of the installed base APK (null when unknown). A patch is only
/// chosen when it was cut from exactly that file and is clearly smaller; a
/// device far behind the newest build falls back to the full APK.
UpdatePlan? planAndroidUpdate(
  UpdateManifest m, {
  required int installedBuild,
  required List<String> abis,
  String? installedSha256,
  int maxBuildsBehindForPatch = 10,
}) {
  if (m.build <= installedBuild) return null;
  UpdateAbi? abi;
  for (final a in abis) {
    abi = m.abis[a];
    if (abi != null) break;
  }
  if (abi == null) return null;

  UpdatePatch? patch;
  if (installedSha256 != null && m.build - installedBuild <= maxBuildsBehindForPatch) {
    for (final p in abi.patches) {
      if (p.fromSha256 == installedSha256.toLowerCase() && p.size < abi.full.size) {
        patch = p;
        break;
      }
    }
  }
  return UpdatePlan(manifest: m, full: abi.full, patch: patch);
}
