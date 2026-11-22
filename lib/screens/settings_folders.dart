import '../widgets/art/navi_icons.dart';

/// Every block of settings, by identity. A section is one `GroupedSection` (or
/// a feature's own section widget); the screen builds each one once and the
/// [SettingsFolder] that lists it decides where it shows.
enum SettingsSection {
  audioQuality('Audio quality convert streaming wi-fi cellular bitrate format switch automatically'),
  playback('Playback autoplay volume normalisation replay gain crossfade gapless shuffle style spread songs'),
  lyrics('Lyrics sources synced words lrc'),
  storage('Downloaded songs cache artwork music tempo storage'),
  playCache('Cached songs cache size limit clear listen again'),
  autoDownload('Auto downloads replay wi-fi only charging storage limit offline'),
  downloadLocation('Download location folder save downloads free space'),
  localMusic('Local music device folder files scan'),
  deleteDownloads('Delete all downloads'),
  smartShuffle('Smart Shuffle recommendations learned'),
  flowLanguages('Flow languages mood radio new languages'),
  tasteMonth('Taste never recommend your month top songs artists minutes'),
  clearRecommendations('Clear recommendation data'),
  weeklyExploration('Weekly exploration playlist discover previews downloads a week'),
  albumOvernight('Album overnight film albums songs a night queue'),
  scrobbling('Scrobbling listenbrainz last.fm lastfm account token'),
  importData('Import exportify spotify playlist listening history csv'),
  listeningData('Your listening data export csv remove skipped plays'),
  look('Look motion living artwork'),
  mascot('Mascot microduck name colour talks'),
  social('Social friends jam profile sharing listen together hide activity alerts quiet hours muted'),
  notifications('Notifications alerts system settings'),
  windows('Windows tray startup shortcut global'),
  account('Account server username password allow http sign in another device who’s listening profile sign out'),
  about('About version connection status updates last error');

  const SettingsSection(this.words);

  /// Words that find the section in the search box, on top of its own text.
  final String words;
}

/// The top level of Settings: a short list of folders, most-used first, then
/// the rarely-touched and technical ones. Each folder holds every setting of
/// its topic; a section lives in exactly one folder.
enum SettingsFolder {
  playback('Playback', NaviGlyph.headphones, [
    SettingsSection.playback,
    SettingsSection.audioQuality,
    SettingsSection.lyrics,
  ]),
  downloads('Downloads & storage', NaviGlyph.downloadCircle, [
    SettingsSection.autoDownload,
    SettingsSection.storage,
    SettingsSection.downloadLocation,
    SettingsSection.localMusic,
    SettingsSection.playCache,
    SettingsSection.deleteDownloads,
  ]),
  flow('Smart Shuffle & Flow', NaviGlyph.flow, [
    SettingsSection.smartShuffle,
    SettingsSection.flowLanguages,
    SettingsSection.weeklyExploration,
    SettingsSection.albumOvernight,
    SettingsSection.tasteMonth,
    SettingsSection.clearRecommendations,
  ]),
  replay('Replay & history', NaviGlyph.rewind, [
    SettingsSection.scrobbling,
    SettingsSection.importData,
    SettingsSection.listeningData,
  ]),
  appearance('Appearance', NaviGlyph.sun, [
    SettingsSection.look,
    SettingsSection.mascot,
  ]),
  social('Social & Jam', NaviGlyph.group, [
    SettingsSection.social,
  ]),
  notifications('Notifications & system', NaviGlyph.bell, [
    SettingsSection.notifications,
    SettingsSection.windows,
  ]),
  account('Account & server', NaviGlyph.cloud, [
    SettingsSection.account,
  ]),
  about('About & advanced', NaviGlyph.info, [
    SettingsSection.about,
  ]);

  const SettingsFolder(this.title, this.icon, this.sections);

  final String title;
  final NaviGlyph icon;
  final List<SettingsSection> sections;

  /// The folder that holds [section].
  static SettingsFolder of(SettingsSection section) =>
      values.firstWhere((f) => f.sections.contains(section));
}
