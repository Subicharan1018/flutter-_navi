import 'package:flutter_test/flutter_test.dart';
import 'package:navivibe/features/social/data/social_models.dart';
import 'package:navivibe/features/social/logic/social_rules.dart';
import 'package:navivibe/services/notification_triggers.dart';

void main() {
  test('the notification names the friend, the song and, for an open room, how to join', () {
    final (title, body) = friendAlertText(const FriendAlert(
      'Arjun',
      song: FriendSong(songId: 's', title: 'Thaniye', artist: 'Anirudh Ravichander'),
      joinCode: 'K7QX2M',
      roomMode: JamMode.collab,
    ));
    expect(title, 'Arjun is listening');
    expect(body, 'Thaniye · Anirudh Ravichander · In a Collab room. Open People to join.');
  });

  test('a closed room is mentioned but never joinable, and a plain listener has just the song', () {
    expect(friendAlertText(const FriendAlert('Sana', roomMode: JamMode.jam)).$2, 'In a Jam room.');
    expect(friendAlertText(const FriendAlert('Dev', song: FriendSong(songId: 's', title: 'Alone'))).$2, 'Alone');
  });

  test('the room code is never put in the notification text', () {
    final (_, body) = friendAlertText(const FriendAlert('Arjun', joinCode: 'K7QX2M', roomMode: JamMode.jam));
    expect(body, isNot(contains('K7QX2M')));
  });

  test('opening the app within two minutes of an alert lands on People, once', () {
    final t = DateTime(2026, 11, 8, 14);
    FriendAlertOpen.mark(t);
    expect(FriendAlertOpen.consume(t.add(const Duration(seconds: 90))), isTrue);
    expect(FriendAlertOpen.consume(t.add(const Duration(seconds: 91))), isFalse); // used up
  });

  test('a later, ordinary launch is left alone', () {
    final t = DateTime(2026, 11, 8, 14);
    FriendAlertOpen.mark(t);
    expect(FriendAlertOpen.consume(t.add(const Duration(minutes: 5))), isFalse);
    expect(FriendAlertOpen.consume(t), isFalse); // nothing waiting
  });
}
