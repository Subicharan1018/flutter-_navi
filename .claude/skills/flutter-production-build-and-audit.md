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
- Missing error states, loading states, or empty states
- Violating Riverpod rules (ref.watch in callbacks, ref.read in build)
- Breaking existing provider contracts silently

## Mandatory Steps (never skip)

### Step 1 — Before Writing Any Code
1. Read `CLAUDE.md` fully
2. Identify which god node or community the change touches
3. Run `/graphify query "what would break if I change X?"` if touching a god node
4. Check if the target file is in a fragile community (cohesion < 0.1)

### Step 2 — While Writing Code
- Zero placeholders. If logic is unknown, ask — do not write `// TODO`
- Every widget must handle: loading, error, empty, and data states
- Every async call must have error handling
- Every new provider must follow Riverpod 2.x `@riverpod` codegen pattern
- Never use `ref.watch()` outside `build()` 
- Never use `ref.read()` inside `build()`
- Models must remain immutable — use `copyWith`, never direct mutation

### Step 3 — After Writing Code (Mandatory Audit)
Run these in order:
```bash
flutter analyze
flutter pub run build_runner build --delete-conflicting-outputs
flutter test
```

Fix ALL errors before considering the task done. Zero warnings policy.

### Step 4 — Self-Audit Checklist
Before declaring done, verify:
- [ ] No `// TODO` or `throw UnimplementedError()` left
- [ ] No hardcoded test data in production code
- [ ] All `AsyncValue` states handled (loading/error/data)
- [ ] `flutter analyze` passes clean
- [ ] `build_runner` ran if annotations were added/changed
- [ ] `flutter test` passes
- [ ] No new isolated nodes added (run `/graphify . --update` to verify)
- [ ] God nodes not modified without graph check

## NaviVibe-Specific Rules

### Riverpod
- `ref.watch()` → ONLY inside `build()`
- `ref.read()` → ONLY inside callbacks/event handlers
- New providers go in `lib/providers/` with `@riverpod` annotation
- Never dump new providers into Community 0 or Community 1

### Audio
- Never manipulate the queue directly — always go through `AudioHandler`
- `PlayerProvider` is the only entry point for playback state from UI
- Gapless reordering uses `ConcatenatingAudioSource.move()` — do not replace with naive reassignment

### Networking
- All API calls go through `SubsonicService` — never bypass it
- `SubsonicService` bridges 11 communities — changes require broad impact assessment

### Database
- Drift tables are in `lib/database/`
- Hive is for simple KV only (auth tokens, preferences)
- Never store complex relational data in Hive

### Theme
- Never hardcode colors — use `ThemeTokens`
- PaletteCache feeds dynamic colors — do not bypass it
- FluidBackground shader parameters come from the theme system — changing theme rules affects GPU shader inputs
