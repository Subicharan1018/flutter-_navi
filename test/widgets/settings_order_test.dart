import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/screens/settings_folders.dart';
import 'package:navivibe/screens/settings_screen.dart';
import 'package:navivibe/widgets/ui/grouped_list.dart';

void main() {
  GroupedSection section(String header, List<String> titles) => GroupedSection(
        header: header,
        children: [for (final t in titles) GroupedRow(title: t)],
      );

  test('every setting section is reachable from exactly one folder', () {
    final seen = <SettingsSection>[for (final f in SettingsFolder.values) ...f.sections];
    expect(seen.toSet(), SettingsSection.values.toSet(), reason: 'a section no folder lists is lost');
    expect(seen.length, SettingsSection.values.length, reason: 'a section listed twice shows twice');
    for (final s in SettingsSection.values) {
      expect(SettingsFolder.of(s).sections, contains(s));
    }
  });

  test('folders run most-used first and the technical ones last', () {
    expect(SettingsFolder.values.first, SettingsFolder.playback);
    expect(SettingsFolder.values.last, SettingsFolder.about);
    expect(SettingsFolder.values.length, lessThanOrEqualTo(9));
    // Lyrics sit with playback, not third in a long list.
    expect(SettingsFolder.of(SettingsSection.lyrics), SettingsFolder.playback);
    expect(SettingsFolder.of(SettingsSection.autoDownload), SettingsFolder.downloads);
    expect(SettingsFolder.of(SettingsSection.importData), SettingsFolder.replay);
    expect(SettingsFolder.of(SettingsSection.albumOvernight), SettingsFolder.flow);
  });

  final items = <SettingsSection, Widget>{
    SettingsSection.about: section('About', ['Version']),
    SettingsSection.playback: section('Playback', ['Autoplay']),
    SettingsSection.look: section('Look', ['Motion', 'Living Artwork']),
  };

  test('groups come out in folder order and skip folders with nothing', () {
    final g = groupSettings(items);
    expect(g.keys.toList(), [SettingsFolder.playback, SettingsFolder.appearance, SettingsFolder.about]);
  });

  test('search keeps matching rows across folders', () {
    final r = searchSettings(items, 'motion');
    expect(r.keys, [SettingsFolder.appearance]);
    expect((r[SettingsFolder.appearance]!.single as GroupedSection).children, hasLength(1));
  });

  test('a folder name keeps all its sections; no match is empty', () {
    expect(searchSettings(items, 'appearance')[SettingsFolder.appearance], hasLength(1));
    expect(searchSettings(items, 'zzzz'), isEmpty);
  });

  test('the phone search finds the folder that holds a setting', () {
    expect(searchFolders('lrc'), [SettingsFolder.playback]);
    expect(searchFolders('listenbrainz'), [SettingsFolder.replay]);
    expect(searchFolders('zzzz'), isEmpty);
  });
}
