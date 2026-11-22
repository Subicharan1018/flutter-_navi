import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/screens/settings_screen.dart';
import 'package:navivibe/widgets/ui/grouped_list.dart';

void main() {
  GroupedSection section(String header, List<String> titles) => GroupedSection(
        header: header,
        children: [for (final t in titles) GroupedRow(title: t)],
      );

  // Source order is deliberately not display order.
  final items = <Widget>[
    const SettingsCategory('Server'),
    section('Account', ['Username']),
    const SettingsCategory('Advanced & diagnostics'),
    section('About', ['Version']),
    const SettingsCategory('Playback'),
    section('Audio Quality', ['Convert While Streaming']),
    const SettingsCategory('Social & Jam'),
    section('Social', ['Jam']),
    const SettingsCategory('Playback'),
    section('Smart Shuffle', ['Recommendations']),
    const SettingsCategory('Downloads & storage'),
    section('Storage', ['Cache Artwork']),
    const SettingsCategory('Appearance'),
    section('Look', ['Motion']),
    const SettingsCategory('Accounts & scrobbling'),
    section('ListenBrainz', ['Token']),
  ];

  test('categories come out most-used first, same on every platform', () {
    final g = groupSettings(items);
    expect(g.keys.toList(), [
      'Playback',
      'Downloads & storage',
      'Appearance',
      'Accounts & scrobbling',
      'Social & Jam',
      'Server',
      'Advanced & diagnostics',
    ]);
    // A category marked twice keeps both sections in source order.
    expect(g['Playback'], hasLength(2));
  });

  test('search keeps matching rows across categories', () {
    final g = groupSettings(items);
    final r = searchSettings(g, 'motion');
    expect(r.keys, ['Appearance']);
    final shrunk = r['Appearance']!.single as GroupedSection;
    expect(shrunk.children, hasLength(1));
  });

  test('a category name keeps all its sections; no match is empty', () {
    final g = groupSettings(items);
    expect(searchSettings(g, 'playback')['Playback'], hasLength(2));
    expect(searchSettings(g, 'zzzz'), isEmpty);
  });
}
