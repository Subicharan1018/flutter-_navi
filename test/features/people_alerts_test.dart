import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/social/data/social_api.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/people_providers.dart';
import 'package:navivibe/features/social/logic/social_providers.dart';
import 'package:navivibe/features/social/logic/social_rules.dart';

/// The poller turns two People lists into alerts through the policy, honouring
/// the switches saved on this device.

class _Api extends Fake implements SocialApi {
  final List<PeopleList> script;
  int polls = 0;
  _Api(this.script);
  @override
  Future<PeopleList> people() async => script[(polls++).clamp(0, script.length - 1)];
}

class _Sink implements FriendAlertSink {
  final shown = <FriendAlert>[];
  @override
  Future<void> show(FriendAlert a) async => shown.add(a);
}

class _MemoryPrefs implements AlertPrefsStore {
  Map<String, Object?> saved = {};
  @override
  Map<String, Object?> read() => saved;
  @override
  void write(Map<String, Object?> value) => saved = value;
}

class _On extends SocialSettingsNotifier {
  @override
  Future<SocialSettings> build() async => const SocialSettings(enabled: true);
}

PeopleList list(PresenceState bob, {String? room}) => PeopleList(enabled: true, people: [
      Person(
        username: 'Bob',
        state: bob,
        nowPlaying: bob == PresenceState.active ? const FriendSong(songId: 's', title: 'Song') : null,
        room: room == null ? null : PersonRoom(mode: JamMode.jam, open: true, members: 2, code: room, joinable: true),
      ),
    ]);

({ProviderContainer c, _Sink sink, _MemoryPrefs prefs, _Api api}) setUp(List<PeopleList> script, {_MemoryPrefs? prefs}) {
  final sink = _Sink();
  final p = prefs ?? _MemoryPrefs();
  final api = _Api(script);
  final c = ProviderContainer(overrides: [
    socialApiProvider.overrideWithValue(api),
    socialSettingsProvider.overrideWith(_On.new),
    alertPrefsStoreProvider.overrideWithValue(p),
    friendAlertSinkProvider.overrideWithValue(sink),
  ]);
  addTearDown(c.dispose);
  return (c: c, sink: sink, prefs: p, api: api);
}

Future<void> ready(ProviderContainer c) async {
  await c.read(socialSettingsProvider.future);
  c.read(peopleProvider); // build
}

void main() {
  test('alerts are off until switched on, and the switch is remembered', () async {
    final r = setUp([list(PresenceState.offline), list(PresenceState.active)]);
    await ready(r.c);
    expect(r.c.read(friendAlertSettingsProvider).enabled, isFalse);
    await r.c.read(peopleProvider.notifier).refresh();
    await r.c.read(peopleProvider.notifier).refresh();
    expect(r.sink.shown, isEmpty); // listening started but alerts are off

    r.c.read(friendAlertSettingsProvider.notifier).setEnabled(true);
    expect(r.prefs.saved['enabled'], isTrue);
    // A new session reads it back.
    final again = setUp(const [], prefs: r.prefs);
    expect(again.c.read(friendAlertSettingsProvider).enabled, isTrue);
  });

  test('a friend starting to listen raises one alert with a Join code when their room is open', () async {
    final r = setUp([list(PresenceState.offline), list(PresenceState.active, room: 'K7QX2M'), list(PresenceState.active)]);
    await ready(r.c);
    r.c.read(friendAlertSettingsProvider.notifier).setEnabled(true);
    final n = r.c.read(peopleProvider.notifier);
    await n.refresh(); // baseline
    expect(r.sink.shown, isEmpty);
    await n.refresh(); // started
    expect(r.sink.shown.single.username, 'Bob');
    expect(r.sink.shown.single.joinCode, 'K7QX2M');
    await n.refresh(); // still listening: nothing more
    expect(r.sink.shown, hasLength(1));
    expect(r.c.read(peopleProvider).list!.people.single.state, PresenceState.active);
  });

  test('muting a friend silences them, and the mute is remembered', () async {
    final r = setUp([list(PresenceState.offline), list(PresenceState.active)]);
    await ready(r.c);
    final s = r.c.read(friendAlertSettingsProvider.notifier)..setEnabled(true)..setMuted('Bob', true);
    expect(r.prefs.saved['muted'], ['bob']);
    final n = r.c.read(peopleProvider.notifier);
    await n.refresh();
    await n.refresh();
    expect(r.sink.shown, isEmpty);
    s.setMuted('bob', false);
    expect(r.c.read(friendAlertSettingsProvider).isMuted('Bob'), isFalse);
  });

  test('someone hiding what they listen to never raises an alert', () async {
    final r = setUp([list(PresenceState.offline), list(PresenceState.hidden)]);
    await ready(r.c);
    r.c.read(friendAlertSettingsProvider.notifier).setEnabled(true);
    final n = r.c.read(peopleProvider.notifier);
    await n.refresh();
    await n.refresh();
    expect(r.sink.shown, isEmpty);
  });

  test('quiet hours are saved and cleared', () {
    final r = setUp(const []);
    final s = r.c.read(friendAlertSettingsProvider.notifier);
    s.setQuietHours(22 * 60, 7 * 60);
    expect(r.c.read(friendAlertSettingsProvider).quietFromMin, 22 * 60);
    expect(r.prefs.saved['quiet_to'], 7 * 60);
    s.setQuietHours(null, null);
    expect(r.c.read(friendAlertSettingsProvider).quietFromMin, isNull);
  });

  test('nothing is requested from the server while social features are off', () async {
    final api = _Api([list(PresenceState.active)]);
    final c = ProviderContainer(overrides: [socialApiProvider.overrideWithValue(api), alertPrefsStoreProvider.overrideWithValue(_MemoryPrefs())]);
    addTearDown(c.dispose);
    await c.read(peopleProvider.notifier).refresh();
    expect(api.polls, 0);
  });
}
