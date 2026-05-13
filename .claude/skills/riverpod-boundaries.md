---
name: riverpod-boundaries
description: >
  Use this skill whenever adding, modifying, or reviewing Riverpod providers,
  notifiers, or state in NaviVibe. Triggers include: adding a new provider,
  modifying PlayerProvider, SettingsProvider, LibraryProvider, adding ref.watch
  or ref.read anywhere, any state management change, or any file in lib/providers/.
---

# Riverpod Boundaries Skill

## The Law (never violate)

```dart
// CORRECT — ref.watch only in build()
Widget build(BuildContext context, WidgetRef ref) {
  final state = ref.watch(playerProvider); // ✅
}

// WRONG — ref.watch in callback
onPressed: () {
  final state = ref.watch(playerProvider); // ❌ NEVER
}

// CORRECT — ref.read in callbacks
onPressed: () {
  ref.read(playerProvider.notifier).play(); // ✅
}

// WRONG — ref.read in build
Widget build(BuildContext context, WidgetRef ref) {
  final state = ref.read(playerProvider); // ❌ NEVER in build
}
```

## Provider Hierarchy (from graph)

`flutter_riverpod` is god node #3 with 46 edges bridging 43 communities.
Every provider in this app is a dependency of this node.

```
SettingsProvider (29 edges — god node)
    ↓
PlayerProvider (40 edges — god node)
    ↓
AudioHandler (Community 61 — service boundary)
    ↓
SubsonicService (46 edges — god node, 11 communities)
    ↓
OfflineService (Community 61 — service boundary)
```

## Adding a New Provider — Rules

1. Use `@riverpod` codegen annotation (Riverpod 2.x)
2. Place in `lib/providers/` with `*_provider.dart` naming
3. Run `flutter pub run build_runner build --delete-conflicting-outputs` after
4. Never place in Community 0 (cohesion 0.07) or Community 1 (cohesion 0.05)
5. New provider must connect to at least one existing provider — no orphans
6. After adding, run `/graphify . --update` and verify it is NOT isolated

## Modifying Existing Providers — Rules

### PlayerProvider (40 edges)
- Most connected provider in the app
- Any change here requires checking all 40 dependents
- Run `/graphify query "what connects to PlayerProvider?"` first
- Never remove the `ListeningEventCollector` call — play events feed telemetry

### SettingsProvider (29 edges)
- Central configuration store
- Changes here affect almost all UI and service layers
- Add fields with `copyWith` only — never make fields mutable
- Always provide sensible defaults

### LibraryProvider
- Connected to `SubsonicService` — changes need network impact check
- Must handle all `AsyncValue` states: loading, error, data

## ProviderContainer in Tests

```dart
// Correct test setup pattern (from graph Communities 13, 18, 20, 34, 35)
final container = ProviderContainer(
  overrides: [
    subsonicServiceProvider.overrideWithValue(MockSubsonicService()),
    offlineServiceProvider.overrideWithValue(MockOfflineService()),
    audioHandlerProvider.overrideWithValue(MockAudioPlayer()),
  ],
);
addTearDown(container.dispose);
```

Always override platform-channel-touching providers to prevent `MissingPluginException`.

## After Any Provider Change
```bash
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
/graphify . --update
```

Verify the modified provider did not become isolated and still connects to its community.
