---
name: flutter-production-build-and-audit
description: >
  Use this skill whenever building, modifying, or auditing a Flutter application
  at production quality. Triggers include: implementing any feature in Flutter,
  fixing bugs in Flutter, reviewing Flutter code for correctness, auditing a
  Flutter codebase, or any request involving Flutter screens, providers, services,
  or state management. This skill enforces zero-placeholder, zero-broken-logic,
  production-stable output and mandates a structured audit and test pass after
  every task. Do NOT skip the audit or test phases — they are mandatory steps,
  not optional suggestions.
---

# Flutter Production Build & Audit Skill

## Purpose

This skill exists because AI-generated Flutter code is routinely:
- Logically broken in ways that compile fine but behave wrong at runtime
- Full of placeholders (`// TODO`, `throw UnimplementedError()`, hardcoded test data)
- Missing edge case handling that a real user will hit within minutes
- Inconsistent across files (a field added in one place, not wired in another)
- Untested, meaning bugs only surface in production

Every task — no matter how small — follows the same three-phase loop:

```
BUILD → SELF-AUDIT → TEST
```

Never deliver output from only the first phase.

---

## Phase 1: BUILD — Production-Only Standards

### 1.1 Before Writing Any Code

Ask these questions and resolve them before opening a file:

**Architecture questions:**
- What state management does this app use? (Riverpod / BLoC / Provider / etc.) Use it exclusively. Never mix.
- What HTTP client does this app use? (Dio / http / etc.) Use the same one. Never introduce a second.
- What storage does this app use? (Hive / SharedPreferences / SQLite / etc.) Use the same one. Never mix.
- What navigation does this app use? (GoRouter / Navigator 2 / etc.) Follow the existing pattern exactly.

**Dependency questions:**
- Is every package I'm about to use already in `pubspec.yaml`? If not, justify adding it.
- Am I about to add a package that duplicates something already present? (e.g. adding `shimmer` when the app has a custom skeleton loader)

**Data flow questions:**
- Where does this data come from? (API / local DB / cache / user input)
- Where does this data go? (UI / another service / persisted to disk)
- What happens when the data is null, empty, or malformed?
- What happens when the network is unreachable?
- What happens when the user is not authenticated?

Resolve ALL of these before writing line one.

---

### 1.2 Code Quality Non-Negotiables

Every line of code produced must meet all of the following. These are not guidelines — they are hard rules. Violating any one is a build failure.

#### No Placeholders
```dart
// ❌ NEVER — these are build failures
throw UnimplementedError();
// TODO: implement this
return Container(); // placeholder
print('debug');    // left in production code
```

```dart
// ✅ REQUIRED — real implementation or explicit documented stub
// If a method cannot be implemented yet, it must throw a typed exception
// with a clear message, logged to your error service, not a bare UnimplementedError.
throw UnsupportedOperationException('Feature requires server version >= 2.0');
```

#### No Hardcoded Values
```dart
// ❌ NEVER
final url = 'http://192.168.1.10:5000';
final color = Color(0xFF6200EE);
final timeout = 10; // magic number
```

```dart
// ✅ REQUIRED
final url = ref.read(settingsProvider).localShuffleUrl;
final color = Theme.of(context).colorScheme.primary;
const _kRequestTimeout = Duration(seconds: 10);
```

#### No Unsafe Casts
```dart
// ❌ NEVER — crashes when server returns int instead of double, or null
final score = json['score'] as double;
final count = json['count'] as int;
```

```dart
// ✅ REQUIRED — handles int, double, String-encoded numbers, and null
double _parseDouble(dynamic v) =>
    v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;

int _parseInt(dynamic v) =>
    v == null ? 0 : int.tryParse(v.toString()) ?? 0;
```

#### No Silent Error Swallowing
```dart
// ❌ NEVER — errors disappear silently
try {
  await riskyCall();
} catch (e) {
  // ignore
}

// ❌ ALSO NEVER — catches but doesn't surface to UI
try {
  await riskyCall();
} catch (e) {
  debugPrint('error: $e');
}
```

```dart
// ✅ REQUIRED — catch, log, rethrow typed, surface to UI
try {
  await riskyCall();
} on DioException catch (e) {
  throw NetworkException('Failed to load recommendations: ${e.message}');
} catch (e, stack) {
  log.error('Unexpected error in fetchNext', error: e, stackTrace: stack);
  rethrow;
}
```

#### No ref.read() Inside build()
```dart
// ❌ NEVER — non-reactive, stale data
Widget build(BuildContext context) {
  final state = ref.read(playerProvider); // wrong
}
```

```dart
// ✅ REQUIRED — reactive
Widget build(BuildContext context) {
  final state = ref.watch(playerProvider); // correct
}

// ref.read() is ONLY correct inside callbacks, event handlers, and non-build methods
void _onTap() {
  ref.read(playerProvider.notifier).play(); // correct
}
```

#### No StateNotifier in New Code (Riverpod 3.0+)
```dart
// ❌ NEVER in new files
class MyNotifier extends StateNotifier<MyState> { }
final myProvider = StateNotifierProvider<MyNotifier, MyState>(...);
```

```dart
// ✅ REQUIRED
class MyNotifier extends AsyncNotifier<MyState> { }
final myProvider = AsyncNotifierProvider<MyNotifier, MyState>(...);
```

#### Immutable Models
```dart
// ❌ NEVER — mutable model causes unpredictable state bugs
class Song {
  String title;
  String artist;
  Song({required this.title, required this.artist});
}
```

```dart
// ✅ REQUIRED — immutable with copyWith
class Song {
  final String title;
  final String artist;
  const Song({required this.title, required this.artist});

  Song copyWith({String? title, String? artist}) => Song(
    title: title ?? this.title,
    artist: artist ?? this.artist,
  );
}
```

---

### 1.3 The Music Player Logic Test — Spot Every Illogical Behaviour

A music player is a perfect reference because it has rich, interlocking state that breaks in non-obvious ways. Use this mental model for ANY complex feature.

When implementing or reviewing ANY stateful feature, mentally run it through the "music player stress test": every state transition that seems obvious has edge cases that silently break things.

#### State Transition Logic

**Track change:**
```
User presses Next →
  Was a scrobble due? → submit before clearing state
  Was position > 30s? → add current to history
  Were we fetching lookahead? → cancel or guard it
  Is new index valid? → check queue bounds
  Did queue change during seek? → index may now point to wrong song
```

A broken implementation does this:
```dart
// ❌ ILLOGICAL — does not check if index is still valid after async gap
await heavyAsyncOperation(); // queue may have changed during this
final song = queue[currentIndex]; // currentIndex may now be out of bounds
```

A correct implementation does this:
```dart
// ✅ CORRECT — re-read state after every await
await heavyAsyncOperation();
final freshState = state; // re-read state post-await
if (freshState.currentIndex >= freshState.queue.length) return;
final song = freshState.queue[freshState.currentIndex];
```

**Shuffle toggle:**
```
User enables shuffle →
  Save current song identity (not index — index will change after shuffle)
  Shuffle the remaining songs around the current song
  Update currentIndex to point to the same song in the new order
  Do NOT reset position
  Do NOT interrupt playback
```

Broken:
```dart
// ❌ ILLOGICAL — uses savedIndex captured before shuffle
// The shuffle reordered the queue so savedIndex now points to the WRONG song
final savedIndex = player.currentIndex;
await shuffleQueue();
state = state.copyWith(currentIndex: savedIndex); // WRONG
```

Correct:
```dart
// ✅ CORRECT — read index AFTER shuffle from the player itself
await shuffleQueue();
final postShuffleIndex = player.currentIndex ?? 0; // what the player says NOW
state = state.copyWith(currentIndex: postShuffleIndex);
```

**Scrobble threshold:**
```
Song starts →
  Record start time
  Calculate threshold = min(50% of duration, 4 minutes)
  On every position tick, check: position >= threshold?
  On pause/resume, accumulate wall-clock listen time separately
  Scrobble when EITHER: position >= 50% OR wall-clock >= 4 minutes
  Guard: only scrobble ONCE per song, not once per tick that crosses threshold
```

Broken:
```dart
// ❌ ILLOGICAL — scrobbles on EVERY tick after threshold
// Also uses DateTime.now() per tick which drifts on pause
player.positionStream.listen((pos) {
  if (pos >= threshold) {
    scrobbleService.submit(songId); // called ~4 times per second after threshold
  }
});
```

Correct:
```dart
// ✅ CORRECT — one-shot guard
player.positionStream.listen((pos) {
  if (!_hasScrobbled && pos >= _scrobbleThreshold) {
    _hasScrobbled = true; // set BEFORE the async call
    scrobbleService.submit(songId);
  }
});
```

**History deduplication:**
```
Track changes to index 1 →
  Add song at index 0 to history
Track changes to index 1 AGAIN (stream fires duplicate) →
  Do NOT add song at index 0 to history again
  Guard: if history.last.id == song.id, skip
```

**Queue mutation during async operation:**
```
Autoplay fetch starts (async, takes 500ms) →
  User clears queue during the fetch →
  Fetch completes, tries to append to queue →
  Queue is now empty or different — appending is wrong
  Guard: check if queue identity has changed after every await
```

**Persist deduplication:**
```
Position stream fires ~4 times/second →
  At second 5: ticks at 4.8s, 5.0s, 5.2s, 5.4s all have posSec=5
  Without guard: _persistState() called 4 times for the same second
  With guard: only fire when posSec != _lastPersistSecond
```

---

### 1.4 Common Flutter Illogical Patterns — Full Reference

Use this as a checklist when reading or writing any Flutter code.

#### Async State Races
```dart
// ❌ ILLOGICAL — state read before async gap may be stale after
final index = state.currentIndex;
await someAsyncOperation(); // state may have been mutated by another event
queue[index]; // index may now be out of bounds
```

#### Index Out of Bounds
```dart
// ❌ ILLOGICAL — no guard
final song = queue[currentIndex];

// ✅ CORRECT
if (queue.isEmpty || currentIndex >= queue.length) return;
final song = queue[currentIndex];
```

#### Provider Rebuild Scope Too Wide
```dart
// ❌ ILLOGICAL — rebuilds entire widget tree when ANY setting changes
final settings = ref.watch(settingsProvider);
final url = settings.localShuffleUrl;

// ✅ CORRECT — rebuilds only when this specific value changes
final url = ref.watch(settingsProvider.select((s) => s.localShuffleUrl));
```

#### Timer Leak
```dart
// ❌ ILLOGICAL — timer keeps firing after widget/notifier is disposed
Timer.periodic(Duration(seconds: 30), (_) => pollHealth());

// ✅ CORRECT
Timer? _timer;
_timer = Timer.periodic(Duration(seconds: 30), (_) => pollHealth());

@override
void dispose() {
  _timer?.cancel();
  super.dispose();
}
```

#### Stream Subscription Leak
```dart
// ❌ ILLOGICAL — subscription never cancelled
player.positionStream.listen((pos) { ... });

// ✅ CORRECT
final _sub = player.positionStream.listen((pos) { ... });
@override
void dispose() { _sub.cancel(); super.dispose(); }
```

#### fromJson Missing Null Safety
```dart
// ❌ ILLOGICAL — crashes when field is absent or wrong type
factory Song.fromJson(Map<String, dynamic> json) => Song(
  title: json['title'] as String,
  duration: json['duration'] as int,
);

// ✅ CORRECT
factory Song.fromJson(Map<String, dynamic> json) => Song(
  title: (json['title'] as String?) ?? 'Unknown',
  duration: _parseInt(json['duration']),
);
```

#### Navigator After Dispose
```dart
// ❌ ILLOGICAL — widget may be unmounted by the time async completes
await someAsyncOp();
Navigator.of(context).pop(); // context may no longer be valid

// ✅ CORRECT
await someAsyncOp();
if (!mounted) return;
Navigator.of(context).pop();
```

#### setState After Dispose
```dart
// ❌ ILLOGICAL — classic Flutter error
void _onData(data) {
  setState(() { _data = data; }); // may fire after dispose
}

// ✅ CORRECT
void _onData(data) {
  if (!mounted) return;
  setState(() { _data = data; });
}
```

#### Double Submission
```dart
// ❌ ILLOGICAL — user taps button twice before first completes
Future<void> _submit() async {
  await api.submit(data); // second call starts before first finishes
}

// ✅ CORRECT
bool _isSubmitting = false;
Future<void> _submit() async {
  if (_isSubmitting) return;
  setState(() => _isSubmitting = true);
  try {
    await api.submit(data);
  } finally {
    if (mounted) setState(() => _isSubmitting = false);
  }
}
```

#### Autoplay/Lookahead Guard — Growing Set
```dart
// ❌ ILLOGICAL — Set grows forever, never cleared on queue reset
final _triggeredFor = <String>{};
if (_triggeredFor.contains(song.id)) return;
_triggeredFor.add(song.id);

// ✅ CORRECT — single ID, reset on queue clear
String? _lastFetchedForSongId;
if (_lastFetchedForSongId == song.id) return;
_lastFetchedForSongId = song.id;
// In clearQueue():
_lastFetchedForSongId = null;
```

#### Hardcoded Color in Theme-Aware App
```dart
// ❌ ILLOGICAL — breaks dark mode, breaks theme changes
Container(color: Colors.green)
Text('error', style: TextStyle(color: Colors.red))

// ✅ CORRECT
Container(color: Theme.of(context).colorScheme.tertiary)
Text('error', style: TextStyle(color: Theme.of(context).colorScheme.error))
```

#### Platform Channel in Test
```dart
// ❌ ILLOGICAL — MissingPluginException in tests
// Caused by: provider not overridden, real DB/path_provider initialized
final container = ProviderContainer(overrides: [
  audioHandlerProvider.overrideWithValue(mockHandler),
  // Missing: listenerCollectorProvider override → real DB → path_provider → crash
]);

// ✅ CORRECT — override every provider that touches platform channels
final container = ProviderContainer(overrides: [
  audioHandlerProvider.overrideWithValue(mockHandler),
  listenerCollectorProvider.overrideWithValue(mockCollector), // add this
]);
```

---

## Phase 2: SELF-AUDIT — Mandatory After Every Task

After writing code and before delivering it, run through this checklist completely. Every ❌ must be fixed before the output is considered done.

### Audit Checklist

#### File Consistency
- [ ] Every field added to a model also has a corresponding `fromJson` entry, a `copyWith` parameter, and is used somewhere in the UI or logic.
- [ ] Every provider declared is imported where it is used.
- [ ] Every import at the top of a file actually resolves to a real file that exists.
- [ ] If a new Hive key was added to `hive_boxes.dart`, it is read in `_loadFromHive` and written in `saveSettings`.
- [ ] If a new settings field was added to `SettingsState`, it appears in the settings screen UI.
- [ ] If a new settings field affects a service (e.g. a URL), the service is rebuilt or notified when the setting changes.

#### State Management
- [ ] No `StateNotifier` in new code.
- [ ] `ref.watch` inside `build`, `ref.read` inside callbacks.
- [ ] Every `AsyncNotifier` handles all three `AsyncValue` states in the UI: loading, error, data.
- [ ] No provider is read with `ref.read` in a `build` method for reactive data.
- [ ] Providers that depend on settings use `.select` to avoid unnecessary rebuilds.

#### Error Handling
- [ ] Every `async` method has a `try/catch`.
- [ ] Every `catch` block either rethrows a typed exception or surfaces to the UI — never empty, never print-only.
- [ ] Every `AsyncValue.error` state in the UI has a visible error message AND a retry button.
- [ ] Network failures leave the last known good state visible — they do not blank the screen.

#### Resource Management
- [ ] Every `Timer` is cancelled in `dispose`.
- [ ] Every `StreamSubscription` is cancelled in `dispose`.
- [ ] Every `TextEditingController` is disposed in `dispose`.
- [ ] Every `ScrollController` is disposed in `dispose`.
- [ ] `Completer` futures are completed in `finally` blocks, not `try` blocks.

#### Logic Correctness
- [ ] Every list access `list[index]` is guarded by a bounds check.
- [ ] Every `as Type` cast on a dynamic/JSON value is replaced with safe parsing.
- [ ] Every state read after an `await` is re-read from the current state, not from a pre-await variable.
- [ ] Every one-shot action (scrobble, submit, analytics event) has a boolean guard to prevent double-firing.
- [ ] Every queue mutation checks that the index is still valid after the mutation.
- [ ] `Navigator.of(context)` after `await` is guarded by `if (!mounted) return`.
- [ ] `setState` after `await` is guarded by `if (!mounted) return`.

#### UI Correctness
- [ ] No hardcoded colors (`Colors.*`) — all from `Theme.of(context).colorScheme.*`.
- [ ] No hardcoded text styles — all from `Theme.of(context).textTheme.*`.
- [ ] No hardcoded strings that should be localized (if the app uses l10n).
- [ ] Every loading state shows a skeleton or spinner — never a blank white screen.
- [ ] Every empty state shows a meaningful illustration or message — never a blank white screen.
- [ ] Every error state shows the error message AND a retry button — no dialogs for recoverable errors.
- [ ] Cold start / first launch is handled — the app does not crash on empty data.

#### Test Readiness
- [ ] Every new provider can be overridden in a `ProviderContainer`.
- [ ] Every service takes its dependencies as constructor parameters (not `get_it` singletons hardwired inside).
- [ ] No platform channels are called from within a service constructor (they make tests impossible without mocking).

---

## Phase 3: TEST — Mandatory Test Plan Per Task

After every task, identify and write the tests for it. Use this matrix to determine what kind of test each component needs.

### Test Type Matrix

| Component Type | Test Type | What to Test |
|---|---|---|
| Data model `fromJson` | Unit test | Valid input, null fields, wrong numeric types, missing keys |
| Service (API client) | Unit test with mock HTTP | Each endpoint method, error mapping, timeout handling |
| Repository | Unit test with mock service | Cache hit, cache miss, cache expiry, error propagation |
| Riverpod provider | Unit test with ProviderContainer | Initial state, state transitions, provider rebuilds on dep change |
| StateNotifier / AsyncNotifier | Unit test with ProviderContainer | Each public method, loading/error/data transitions |
| Widget | Widget test | Renders correctly for each state, user interactions fire callbacks |
| Screen | Widget test | All three AsyncValue states render, navigation fires on correct actions |
| Integration (screen + provider) | Widget test with overridden container | End-to-end: user action → provider update → UI change |

### Minimum Test Coverage Per Task

**If you added a model:**
```dart
// Required tests:
test('fromJson parses valid response', () { ... });
test('fromJson handles null optional fields', () { ... });
test('fromJson handles String-encoded numbers', () { ... });
test('fromJson handles missing keys gracefully', () { ... });
```

**If you added a service:**
```dart
// Required tests:
test('getX() calls correct endpoint with correct params', () { ... });
test('getX() maps DioException to NetworkError', () { ... });
test('getX() maps 500 response to ServerError', () { ... });
test('getX() parses response into typed model', () { ... });
```

**If you added a repository:**
```dart
// Required tests:
test('getStats() returns cached value within TTL', () { ... });
test('getStats() makes network call after TTL expires', () { ... });
test('getNext() propagates ShuffleNetworkError on failure', () { ... });
```

**If you added a provider:**
```dart
// Required tests:
test('provider starts in correct initial state', () { ... });
test('fetchNext() transitions loading → data', () { ... });
test('fetchNext() transitions loading → error on failure', () { ... });
test('clearQueue() resets to AsyncData([])', () { ... });
test('provider rebuilds when dependency setting changes', () { ... });
```

**If you added a widget:**
```dart
// Required tests:
testWidgets('shows skeleton during loading', (tester) async { ... });
testWidgets('shows error banner with retry on error', (tester) async { ... });
testWidgets('shows content on data', (tester) async { ... });
testWidgets('retry button calls correct notifier method', (tester) async { ... });
```

**If you fixed a bug:**
```dart
// Required: a regression test that reproduces the exact bug scenario
test('REGRESSION: scrobble fires only once when position crosses threshold', () {
  // Set up the exact conditions that triggered the bug
  // Verify the bug does not recur
});
```

### Test Setup Template

Every test file for a Riverpod app must have this boilerplate to avoid `MissingPluginException`:

```dart
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    // If the test touches Hive:
    final dir = Directory.systemTemp.createTempSync('hive_test_${testName}');
    Hive.init(dir.path);
    HiveBoxes.auth    = await Hive.openBox('auth');
    HiveBoxes.session = await Hive.openBox('session');
    HiveBoxes.prefs   = await Hive.openBox('prefs');
    HiveBoxes.audio   = await Hive.openBox('audio');

    // Register fallback values for mocktail:
    registerFallbackValue(Song(id: '', title: '', artist: '', album: '',
        coverArt: '', duration: 0, track: 0, year: 0));
  });

  // Every ProviderContainer MUST override every provider that touches
  // platform channels, databases, or network. No exceptions.
  final container = ProviderContainer(overrides: [
    audioHandlerProvider.overrideWithValue(mockHandler),
    subsonicServiceProvider.overrideWithValue(mockService),
    listenerCollectorProvider.overrideWithValue(mockCollector), // NEVER forget this
    scrobbleServiceProvider.overrideWithValue(mockScrobble),
  ]);
  addTearDown(container.dispose);
}
```

---

## Full Task Execution Flow

When given any Flutter task, execute in this exact order. Do not skip steps.

```
STEP 1: READ
  Read every file that will be touched or that the touched file imports.
  Do not write code based on assumptions about what a file contains.

STEP 2: PLAN
  List every file that will be created or modified.
  For each file, state what will change and why.
  Identify which Phase 1 rules apply.

STEP 3: IMPLEMENT
  Write complete, production code.
  Apply every rule in Section 1.2 and 1.4.
  No placeholders. No TODOs. No hardcoded values.

STEP 4: SELF-AUDIT
  Run every item in the Phase 2 checklist against your output.
  Fix every ❌ before proceeding.
  Re-run the checklist after fixes.

STEP 5: TEST PLAN
  Identify every test required by the Phase 3 matrix.
  Write the test code.
  Confirm that the test setup includes all necessary provider overrides.

STEP 6: CROSS-FILE CONSISTENCY CHECK
  For every field/method/constant added, verify it is:
    - Declared in one place
    - Imported correctly in every file that uses it
    - Not duplicated under a different name elsewhere
    - Reflected in the UI if it is a settings/config value
  This step catches the most common AI-generated bugs.

STEP 7: DELIVER
  Output the complete file contents (not diffs unless the file is very large).
  State which files were created and which were modified.
  State which tests are new and what each one verifies.
  State any remaining known limitations explicitly — never hide them.
```

---

## Post-Task Audit Report Format

After completing a task, produce a brief audit report in this format:

```
## Task Audit: [Task Name]

### Files Changed
| File | Created/Modified | Summary of Change |
|------|-----------------|-------------------|
| lib/features/x/y.dart | Modified | Added fetchNext() method |

### Self-Audit Results
| Check | Result | Notes |
|-------|--------|-------|
| No placeholders | ✅ PASS | |
| No hardcoded URLs | ✅ PASS | |
| All AsyncValue states handled | ✅ PASS | |
| Timers cancelled in dispose | ✅ PASS | |
| Bounds checks on list access | ⚠️ PARTIAL | Line 47 — added guard, verify in review |
| ref.watch in build only | ✅ PASS | |

### Tests Written
| Test File | Tests Added | Covers |
|-----------|-------------|--------|
| test/features/x/y_test.dart | 4 | fromJson valid, null fields, type coercion, missing keys |

### Known Limitations
- None. / [List any genuine limitations that could not be resolved]

### Cross-File Consistency
- ✅ New Hive key `kLocalShufflePort` declared in hive_boxes.dart, read in settings_provider.dart, written in saveSettings(), exposed in settings_screen.dart
- ✅ `shuffleApiServiceProvider` watches settings with .select — rebuilds only on URL change
```

---

## Quick Reference — The 15 Most Common Flutter Logic Bugs

| # | Bug | Symptom | Fix |
|---|-----|---------|-----|
| 1 | Index read before bounds check | RangeError at runtime | Always guard `list[i]` with `i < list.length` |
| 2 | State read pre-await used post-await | Wrong song plays, wrong index shown | Re-read `state` after every `await` |
| 3 | Scrobble fires multiple times | Last.fm shows 4x plays per song | One-shot `_hasScrobbled` boolean guard |
| 4 | Shuffle updates wrong index | Current song jumps to wrong track after shuffle | Read `player.currentIndex` AFTER shuffle completes |
| 5 | Timer/stream not cancelled on dispose | Memory leak, crash on hot reload | Cancel in `dispose()`, store reference |
| 6 | `mounted` not checked after await | `setState called after dispose` error | `if (!mounted) return;` after every await in StatefulWidget |
| 7 | Provider watched too broadly | Entire screen rebuilds on unrelated setting change | Use `.select((s) => s.specificField)` |
| 8 | `StateNotifier` used in Riverpod 3.0 app | Legacy import required, deprecated API | Use `AsyncNotifier` / `Notifier` |
| 9 | `as Type` cast on JSON field | Crash when API returns int instead of double | Use `_parseInt()` / `_parseDouble()` helpers |
| 10 | Empty catch block | Bug disappears silently, impossible to debug | Always rethrow typed or surface to UI |
| 11 | Hardcoded color | Broken dark mode, theme inconsistency | Use `colorScheme.*` tokens |
| 12 | `ref.read` in `build` for reactive data | UI never updates when state changes | Use `ref.watch` in `build` |
| 13 | Missing provider override in test | `MissingPluginException` / Drift multiple instances | Override every provider that touches DB or platform channels |
| 14 | Growing guard Set never cleared | Autoplay/lookahead stops triggering after queue clear | Use single ID field, reset in `clearQueue()` |
| 15 | Double submission on fast tap | API called twice, duplicate records | `isLoading` boolean guard before async call |