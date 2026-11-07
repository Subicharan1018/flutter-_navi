import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' hide PlayerState;
import 'package:navivibe/core/pointer_anchor.dart';
import 'package:navivibe/core/theme.dart';
import 'package:navivibe/models/song.dart';
import 'package:navivibe/providers/catalog_provider.dart';
import 'package:navivibe/providers/player_provider.dart';
import 'package:navivibe/providers/settings_provider.dart';
import 'package:navivibe/services/subsonic_service.dart';
import 'package:navivibe/utils/platform_utils.dart';
import 'package:navivibe/widgets/table/song_table.dart';

Song _s(int i, {int dur = 200, String? album}) => Song(
      id: 's$i',
      title: 'Song ${String.fromCharCode(64 + i)}',
      artist: 'Artist $i',
      album: album ?? 'Album ${(i % 3) + 1}',
      coverArt: 's$i',
      duration: dur + i * 10,
      track: i,
      year: 2024,
      suffix: 'flac',
      bitRate: 900,
      created: DateTime(2024, i, 5),
    );

class _FakePlayer extends StateNotifier<PlayerState> implements PlayerNotifier {
  _FakePlayer()
      : super(const PlayerState(
          queue: [],
          currentIndex: -1,
          isPlaying: false,
          shuffleMode: false,
          autoplayMode: false,
          repeatMode: LoopMode.off,
          starredIds: [],
          history: [],
          syncMode: SyncMode.activeHere,
        ));
  @override
  dynamic noSuchMethod(Invocation i) => i.isMethod ? Future<void>.value() : null;
}

class _FakeSubsonic extends Fake implements SubsonicService {
  @override
  String getCoverArtUrl(String? id, {int? size}) => '';
}

class _Harness {
  final played = <String>[];
  List<String> playedQueue = [];
  final removed = <String>[];
  final moves = <(List<int>, int)>[];
}

Widget _app(
  _Harness h,
  List<Song> songs, {
  bool remove = true,
  bool reorder = true,
  String? playlistId = 'pl',
  bool dates = true,
}) =>
    PointerAnchor(
      child: ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => _FakePlayer()),
          subsonicServiceProvider.overrideWithValue(_FakeSubsonic()),
          catalogSongProvider.overrideWith((ref, id) => null),
        ],
        child: MaterialApp(
          theme: AppTheme.build(AppThemeTokens.fallback),
          builder: (c, child) => ThemeTokens(tokens: AppThemeTokens.fallback, child: child!),
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SongTableSliver(
                        songs: songs,
                        playlistId: playlistId,
                        showDateAdded: dates,
                        onPlay: (s, ordered) {
                          h.played.add(s.id);
                          h.playedQueue = [for (final o in ordered) o.id];
                        },
                        onRemove: remove ? (l) => h.removed.addAll([for (final s in l) s.id]) : null,
                        onReorder: reorder ? (from, before) => h.moves.add((from, before)) : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

Future<void> _size(WidgetTester tester, double w, double h) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, h);
  addTearDown(tester.view.reset);
}

Finder _row(String title) => find.text(title);

Future<void> _click(WidgetTester tester, Finder f, {bool ctrl = false, bool shift = false}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 350)); // let the double-tap window close
  await tester.pump();
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

bool _selected(WidgetTester tester, String title) {
  final sem = tester.getSemantics(find.ancestor(of: find.text(title), matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.selected != null)).first);
  return sem.flagsCollection.isSelected.toBoolOrNull() ?? false;
}

void main() {
  late _Harness h;
  late List<Song> songs;

  setUp(() {
    PlatformUtils.debugDesktopOverride = true;
    h = _Harness();
    songs = [for (var i = 1; i <= 6; i++) _s(i)];
  });
  tearDown(() {
    PlatformUtils.debugDesktopOverride = null;
    PointerAnchor.reset();
  });

  group('selection', () {
    testWidgets('a click selects one row, Ctrl adds, Shift takes a range', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      await _click(tester, _row('Song A'));
      expect(_selected(tester, 'Song A'), isTrue);
      expect(_selected(tester, 'Song B'), isFalse);
      await _click(tester, _row('Song C'), ctrl: true);
      expect(_selected(tester, 'Song A'), isTrue);
      expect(_selected(tester, 'Song C'), isTrue);
      expect(_selected(tester, 'Song B'), isFalse);
      await _click(tester, _row('Song E'), shift: true);
      for (final t in ['Song C', 'Song D', 'Song E']) {
        expect(_selected(tester, t), isTrue, reason: t);
      }
      expect(h.played, isEmpty, reason: 'a single click only selects');
    });

    testWidgets('Ctrl+A selects everything, Esc clears it', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      await _click(tester, _row('Song B'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      for (final s in songs) {
        expect(_selected(tester, s.title), isTrue, reason: s.title);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_selected(tester, 'Song A'), isFalse);
    });

    testWidgets('arrow keys move the selection, Shift+arrow extends it', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      await _click(tester, _row('Song B'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_selected(tester, 'Song C'), isTrue);
      expect(_selected(tester, 'Song B'), isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(_selected(tester, 'Song C'), isTrue);
      expect(_selected(tester, 'Song D'), isTrue);
    });
  });

  group('playing and removing', () {
    testWidgets('double-click plays that row with the rows as shown', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      await tester.tap(_row('Song C'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_row('Song C'));
      await tester.pumpAndSettle();
      expect(h.played, ['s3']);
      expect(h.playedQueue.length, 6);
    });

    testWidgets('Enter plays the selected row', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      await _click(tester, _row('Song D'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.played, ['s4']);
    });

    testWidgets('Delete removes the selection from a playlist', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      await _click(tester, _row('Song B'));
      await _click(tester, _row('Song D'), ctrl: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(h.removed, ['s2', 's4']);
    });

    testWidgets('Delete does nothing where songs cannot be removed', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs, remove: false));
      await _click(tester, _row('Song B'));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(h.removed, isEmpty);
    });
  });

  group('sorting and finding', () {
    List<String> order(WidgetTester tester) {
      final ys = {for (final s in songs) s.title: tester.getTopLeft(find.text(s.title)).dy};
      return (ys.entries.toList()..sort((a, b) => a.value.compareTo(b.value))).map((e) => e.key).toList();
    }

    testWidgets('a header click sorts, again reverses, a third restores the order', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs.reversed.toList()));
      expect(order(tester).first, 'Song F');
      await tester.tap(find.text('Title'));
      await tester.pump();
      expect(order(tester).first, 'Song A');
      await tester.tap(find.text('Title'));
      await tester.pump();
      expect(order(tester).first, 'Song F');
      await tester.tap(find.text('Title'));
      await tester.pump();
      expect(order(tester).first, 'Song F');
    });

    testWidgets('sorting by time puts the shortest first', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs.reversed.toList()));
      await tester.tap(find.text('Time'));
      await tester.pump();
      expect(order(tester).first, 'Song A');
    });

    testWidgets('playing from a sorted table queues the sorted order', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs.reversed.toList()));
      await tester.tap(find.text('Title'));
      await tester.pump();
      await _click(tester, _row('Song B'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(h.playedQueue.first, 's1');
      expect(h.played, ['s2']);
    });

    testWidgets('Ctrl+F opens find and narrows the rows', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      await _click(tester, _row('Song A'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'song c');
      await tester.pump();
      expect(find.text('Song C'), findsOneWidget);
      expect(find.text('Song A'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Song A'), findsOneWidget);
    });

    testWidgets('the global Ctrl+F hook finds the table on screen', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      expect(SongTableSliver.tryFind(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('right-click', () {
    testWidgets('on one row opens the song menu at the cursor', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      final at = tester.getCenter(_row('Song B'));
      await tester.tapAt(at, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Play Next'), findsOneWidget);
    });

    testWidgets('on a multi-selection opens a group menu', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      await _click(tester, _row('Song B'));
      await _click(tester, _row('Song D'), ctrl: true);
      await tester.tapAt(tester.getCenter(_row('Song D')), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Play 2 Songs'), findsOneWidget);
      expect(find.text('Remove 2 from Playlist'), findsOneWidget);
      await tester.tap(find.text('Remove 2 from Playlist'));
      await tester.pumpAndSettle();
      expect(h.removed, ['s2', 's4']);
    });

    testWidgets('a held mouse button does not open a menu', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      final g = await tester.startGesture(tester.getCenter(_row('Song B')), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(seconds: 1));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('Play Next'), findsNothing);
    });
  });

  group('drag', () {
    testWidgets('dragging a row onto another reorders, with its index and the drop place', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      final g = await tester.startGesture(tester.getCenter(_row('Song B')), kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(0, 20));
      await g.moveTo(tester.getCenter(_row('Song E')) + const Offset(0, 14)); // lower half of E
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(h.moves.single.$1, [1]);
      expect(h.moves.single.$2, 5);
    });

    testWidgets('no reordering in a list that has no playlist (Songs, Favorites)', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs, reorder: false, playlistId: null));
      final g = await tester.startGesture(tester.getCenter(_row('Song B')), kind: PointerDeviceKind.mouse);
      await g.moveBy(const Offset(0, 20));
      await g.moveTo(tester.getCenter(_row('Song E')));
      await g.up();
      await tester.pumpAndSettle();
      expect(h.moves, isEmpty);
    });
  });

  group('width', () {
    testWidgets('columns drop as the window narrows; the table never overflows', (tester) async {
      for (final w in [1920.0, 1366.0, 1100.0, 860.0, 600.0, 420.0]) {
        await _size(tester, w, 700);
        await tester.pumpWidget(_app(h, songs));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'width $w');
        expect(find.text('Added').evaluate().isNotEmpty, w - 0 >= 900, reason: 'Added at $w');
        expect(find.text('Album').evaluate().isNotEmpty, w >= 640, reason: 'Album at $w');
        expect(find.text('Title'), findsOneWidget);
      }
    });

    testWidgets('hovering a row shows its play button in the # column', (tester) async {
      await _size(tester, 1366, 768);
      await tester.pumpWidget(_app(h, songs));
      expect(find.byTooltip('Play'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(_row('Song C')));
      await tester.pump();
      expect(find.byTooltip('Play'), findsOneWidget);
    });
  });
}
