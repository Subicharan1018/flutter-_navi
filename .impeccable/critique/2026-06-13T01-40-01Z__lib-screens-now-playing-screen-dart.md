---
target: lib/screens/now_playing_screen.dart
total_score: 26
p0_count: 1
p1_count: 3
timestamp: 2026-06-13T01-40-01Z
slug: lib-screens-now-playing-screen-dart
---
## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 3 | Sleep timer countdown visible; no loading indicator during reshuffle beyond a spinner replacing the shuffle icon |
| 2 | Match System / Real World | 4 | Music controls map perfectly to physical player conventions |
| 3 | User Control and Freedom | 3 | Drag-to-dismiss + close button; sleep timer "Off" label in hardcoded red raises alarm instead of neutrally describing the action |
| 4 | Consistency and Standards | 2 | Progress bar uses third-party `avpb.ProgressBar` while DESIGN.md mandates `SliderTheme+Slider`; `Colors.pinkAccent`/`Colors.redAccent` bypass the token system; bare `TextStyle()` throughout skips per-theme font families |
| 5 | Error Prevention | 3 | Cover art error widget falls back gracefully; reshuffle guard prevents double-trigger |
| 6 | Recognition Rather Than Recall | 3 | Bottom actions are labeled; shuffle long-press (smart shuffle) carries no visible affordance hint |
| 7 | Flexibility and Efficiency | 2 | No skip-gesture on cover art; long-press on shuffle is undiscoverable; swipe-to-dismiss is great but only one power-user shortcut |
| 8 | Aesthetic and Minimalist Design | 3 | Strong hierarchy: cover → title → controls; 9px bottom-action labels below recommended minimum; quality strip adds metadata noise |
| 9 | Error Recovery | 2 | Reshuffle failure shows `SnackBar` with raw exception text; cover error fallback silently swaps icon |
| 10 | Help and Documentation | 1 | No tooltip explaining long-press-shuffle; no label differentiating "Autoplay" from standard queue repeat |
| **Total** | | **26/40** | **Acceptable — significant improvements before all users are happy** |

## Anti-Patterns Verdict

**LLM assessment**: The screen avoids the most obvious AI-slop tells — no fake eyebrows, no numbered section markers, no generic card nesting. The cover-first layout and fluid shader give it genuine atmosphere. However, the bottom row is dense with five icon+label pairs that fight for equal weight, which reads as a generic "action tray" rather than a curated set of affordances. The progress bar substitute (`avpb.ProgressBar`) introduces an inconsistency in visual language between this screen and the system's own `SliderTheme` contract.

**Deterministic scan**: `detect.mjs` returned 0 findings on the Dart source tree (the tool's rules are HTML/CSS-focused and do not apply to Flutter widget code). No findings to report; manual review is the primary signal.

**Visual overlays**: Browser automation is not applicable for a Flutter/Dart file. Overlay injection was skipped.

## Overall Impression

The atmosphere is right — the fluid shader + album-derived palette delivers the "Album as Atmosphere" north star. The structural skeleton is clean and the cover leads. The three problems that undermine the experience are: (1) the progress bar violates the project's own spec by using a third-party widget instead of `SliderTheme+Slider`, breaking visual consistency with the mini player; (2) hardcoded `Colors.pinkAccent` and `Colors.redAccent` shatter the Themability Rule and produce unacceptable contrast on light themes; and (3) the per-theme font families (Playfair Display for Analog, Space Mono for Aura, Cormorant Garamond for Zen) never reach the Now Playing screen's text widgets because dozens of bare `TextStyle()` calls bypass `ThemeTokens.textStyle()`. On Analog the screen looks like Inter, not a vinyl sleeve.

## What's Working

1. **Cover-first hierarchy is solid.** The `AnimatedScale(scale: isPlaying ? 1.0 : 0.93)` pulse is subtle and satisfying. The cover dominates the top half of the screen exactly as the design north star intends.
2. **`disableAnimations` guard in `SoundBar` / `StaticBars`.** The `MediaQuery.disableAnimations` check at lines 186–206 and 201–205 properly degrades to static bars. Accessibility-first thinking already baked in.
3. **Sleep timer countdown and reshuffle guard.** `ValueNotifier<int?>` driving the countdown label is clean reactive design. The `_isReshuffling` guard prevents double-triggers and gives the user a visible in-progress indicator.

## Priority Issues

### [P0] Progress bar violates the mandatory `SliderTheme+Slider` rule
**Heuristic violated:** H4 Consistency and Standards  
**Evidence:** `lib/screens/now_playing_screen.dart:1421` — `return avpb.ProgressBar(...)` from the `audio_video_progress_bar` third-party package. The mini player (`lib/widgets/mini_player.dart:720`) uses a `CustomPaint` / `_ProgressPainter`. Neither uses `SliderTheme+Slider`.  
**Why it hurts:** DESIGN.md §5 and CLAUDE.md §9 are unambiguous: "Now Playing progress bar: `SliderTheme + Slider` … **Never** a custom painter — `_NeonTrackPainter` and `_GlassThumbShape` are forbidden here." The third-party `avpb.ProgressBar` renders a completely different thumb shape, track geometry, and interaction model that the `SliderTheme` from `AppTheme.buildTheme()` cannot override. This means the track color, thumb, and active-fill colors set in `sliderTheme:` inside `AppTheme.buildTheme()` have zero effect on the progress bar the user actually sees. The Neumorphic theme sets `enabledThumbRadius: 9` and `trackHeight: 6` — none of that reaches the progress bar.  
**Fix direction:** Replace `avpb.ProgressBar` in `_PositionStreamState.build()` with a `SliderTheme`-wrapped `Slider`, using `ThemeTokens.of(context)` for `activeTrackColor`, `thumbColor`, and `inactiveTrackColor`. The time labels (`_lastKnown` formatted, `widget.duration` formatted) can be placed in a `Row` above or below the `Slider` with `tokens.textStyle(11, FontWeight.w500, tokens.textSecondary)`. The volume slider at lines 463–499 already shows the correct pattern with a `SliderTheme` + custom `_AppleMusicThumb` — replicate that pattern for the position bar.  
**Suggested command:** `/impeccable harden`

---

### [P1] `Colors.pinkAccent` and `Colors.redAccent` violate The Themability Rule — contrast failure on light themes
**Heuristic violated:** H4 Consistency and Standards; H8 Aesthetic and Minimalist Design  
**Evidence:**  
- `now_playing_screen.dart:1092` — `color: Colors.pinkAccent` for the "favorited" heart icon  
- `now_playing_screen.dart:676` — `style: TextStyle(color: Colors.redAccent)` for the sleep timer "Off" label  
- `now_playing_screen.dart:1519` — `color: Colors.redAccent` for the Queue history "Clear" button  
- `now_playing_screen.dart:1873` — `Colors.redAccent.withValues(alpha: 0.80)` for the swipe-to-remove dismiss background  
**Why it hurts:** `Colors.pinkAccent` (`#FF4081`) on Analog's cream background (`#F5ECD7`) yields 2.83:1 — well below WCAG AA 4.5:1. This is the starred/favorite state, meaning the user's most emotionally resonant action (loving a track) renders inaccessibly. `Colors.redAccent` used for "Clear" and "Off" is also untokenized; on Neumorphic's light gray (`#E0E5EC`) its contrast ratio is 4.31:1 — just below AA. More importantly, using a Spotify-brand-neutral pink for hearts and raw red for destructive actions bypasses the entire themed color system — the Zen theme's monochromatic identity or Analog's warm palette have no influence here.  
**Fix direction:** The "favorited" state should use `ThemeTokens.of(context).gold` (the star/favourite semantic token). On all six themes `gold` is the warm signal for favourites; using `pinkAccent` creates a semantic mismatch and a cross-theme bleed. For destructive actions ("Off", "Clear", dismiss background) use `ThemeTokens.of(context).error` — the `AppThemeTokens` system doesn't currently expose an `error` token but `AppTheme.buildTheme()` passes `error: const Color(0xFFCF6679)` into the `ColorScheme`; add an `error` getter to `AppThemeTokens` and use it here.  
**Suggested command:** `/impeccable colorize`

---

### [P1] Bare `TextStyle()` throughout bypasses per-theme font families
**Heuristic violated:** H4 Consistency and Standards; H2 Match System / Real World  
**Evidence:** 20+ `TextStyle(fontSize: ..., fontWeight: ...)` calls throughout the file (lines 266, 382, 644, 655, 676, 766, 790, 798, 1034, 1048, 1062, 1430, 1499, 1518, 1549, 1755, 1766, 1913, 1923, 2008, 2020, 2041, 2072) — none call `ThemeTokens.of(context).textStyle(size, weight, color)`. Critical examples: song title at line 1034 (22px bold) and artist at line 1062 (16px) use bare `TextStyle`, which always renders Inter regardless of theme.  
**Why it hurts:** The Analog theme ships Playfair Display expressly to evoke vinyl-era warmth on the Now Playing screen. The Aura theme uses Space Mono to feel synthetic and electronic. The Zen theme uses Cormorant Garamond for editorial gravity. When the Now Playing screen renders the song title in Inter on every theme, 3 of the 6 theme identities are broken at the most emotionally prominent text on the screen. The per-theme typeface IS the theme atmosphere — bypassing it here kills the "room the record is playing in" effect.  
**Fix direction:** Replace every `TextStyle(fontSize: f, fontWeight: w, color: c)` with `ThemeTokens.of(context).textStyle(f, w, c)`. For the time label in `_PositionStreamState` at line 1430, use `tokens.technicalSm` or `tokens.labelMd`. For the `_BottomAction` labels at line 266 (fontSize 9) use `tokens.textStyle(9, FontWeight.w500, labelColor)`. For dialog titles (sleep timer, smart shuffle dialogs at lines 644–648 and 766–770) use `tokens.headingSm`.  
**Suggested command:** `/impeccable typeset`

---

### [P1] `textMuted` fails WCAG AA contrast on all three light themes — used for body/label text
**Heuristic violated:** H8 Aesthetic; PRODUCT.md accessibility rule (≥4.5:1 for body/placeholder)  
**Evidence:**  
- Neumorphic: `textMuted` (`#8FA8B8`) on `bgBase` (`#E0E5EC`) → **1.96:1** — catastrophic failure  
- Zen: `textMuted` (`#888888`) on `bgBase` (`#FAFAF8`) → **3.39:1** — fails 4.5  
- Analog: `textMuted` (`#9E7B5A`) on `bgBase` (`#F5ECD7`) → **3.29:1** — fails 4.5  
Used for: `_BottomAction` labels (lines 1258, 1259), empty-state label (line 2072), history "Last played" caption (line 2042), unselected queue tab labels (line 1548), drag handle icon (line 1628).  
**Why it hurts:** These are not decorative elements — they are interactive labels and navigational captions. On Neumorphic (the only theme with physical extruded depth) the bottom action labels are essentially invisible at 1.96:1. The PRODUCT.md explicitly states "contrast ratio ≥4.5:1 for body and placeholder texts" — this fails on three of six themes.  
**Fix direction:** This is a theme-token-layer problem, not a widget-layer problem. `textMuted` in `AppThemeTokens` for Neumorphic, Zen, and Analog needs to be darkened. Neumorphic `textMuted` should be at least `#6A7F8F` (achieves ~3.5:1) or better `#4E6070` (~5:1). Zen `textMuted` should be `#666666` (~5.7:1). Analog `textMuted` should be `#7A5A40` (~4.9:1). Do not work around this at the widget layer by substituting `textSecondary` — fix the tokens so the semantic meaning is preserved.  
**Suggested command:** `/impeccable harden`

---

### [P2] Bottom action tray: 9px labels violate minimum legible type size; tray has no visual differentiation
**Heuristic violated:** H8 Aesthetic and Minimalist Design  
**Evidence:** `_BottomAction` label at line 268: `fontSize: 9`. DESIGN.md §3 defines Label as the minimum viable size at 11px/600 weight. The bottom tray has five equal-weight icons (SoundBar/Playing, Autoplay, Sleep, Queue, Lyrics) with 9px labels — zero visual hierarchy differentiating primary from secondary utility actions.  
**Why it hurts:** "Lyrics" and "Queue" are high-frequency actions that deserve discoverability. "Playing/Paused" is a status badge not an action — it has the same visual weight as the two most useful tray items. 9px text is below Material Design's recommended 11pt minimum and is unreadable at normal arm's distance.  
**Fix direction:** Increase `_BottomAction` label `fontSize` to 10–11 (the system minimum). Visually differentiate the status badge (SoundBar+Playing/Paused) from the action buttons — either remove it from the tray or render it at lower opacity. Consider making Queue and Lyrics slightly larger icons (26 → 28) to reinforce their higher utility.  
**Suggested command:** `/impeccable typeset`

## Persona Red Flags

**Sam (Accessibility-Dependent User)**: The most vulnerable user on this screen.
- **Neumorphic: essentially invisible bottom-action labels** — 1.96:1 contrast ratio at 9px. Any Sam on Neumorphic cannot read "Sleep", "Queue", or "Lyrics" labels, making those features effectively hidden.
- **Favorite heart in `Colors.pinkAccent`** fails 4.5:1 on Analog (2.83:1). A screen-reader user depending on focus contrast cues will miss the starred-state change.
- **`_BottomAction` uses `GestureDetector` + `Semantics(button: true)`** — correctly labeled, which is good. But the 60px-wide, 9px-labeled tap target with no minimum-height constraint may be smaller than 44×44pt on narrow screens (the `SizedBox(width: 60)` has no height constraint; `Column` determines height from children).
- **No focus ring visible** — `GestureDetector`-based tap targets have no Material focus indicator. Keyboard-only navigation on Linux (a stated platform target) cannot tab to these actions.

**Casey (Distracted Mobile User)**: 
- **Progress bar thumb (6px `thumbRadius` from `avpb.ProgressBar`)** is very small for fat-finger seeking on the go. The standard `SliderTheme` thumb at 6px radius (12px diameter) is borderline — Neumorphic's 9px radius is better. However, because `avpb.ProgressBar` renders its own thumb, the `SliderTheme` enlargement on Neumorphic has no effect.
- **Five bottom tray actions at the very bottom of the screen** — thumb-zone placement is correct, but they are equally weighted. Casey will tap "Playing/Paused" expecting something to happen and be confused by the no-op `onTap: () {}` at line 1259.
- **Sleep timer long label during countdown** (`_formatSleepLabel` returns `'5m'`) could display `'5:00'` or `'4m59s'` — fine for short durations, but visually cuts off early in `maxLines: 1, overflow: TextOverflow.ellipsis` at 60px width.

**NaviVibe Power User ("Kai" — derived from product context: Subsonic/Navidrome power user who manages a private library)**:
- **Smart shuffle long-press is completely undiscoverable** — no tooltip, no hint text, no long-press indicator. Kai knows to look for power features but has no cue that the shuffle icon is long-pressable.
- **Cover art has no tap interaction** — tapping the art does nothing (`LayoutBuilder` with no `GestureDetector`). Common power-user expectation: tap cover → go to album.
- **No skip gesture on cover art** — the mini player has swipe-to-next but this screen relies entirely on the skip buttons. Swipe on the cover would be a natural accelerator.

## Minor Observations

- `_QualityPill` at line 384 uses `fontSize: 10.5` with bare `TextStyle` — sub-minimum label size and misses the theme font family. Should be `tokens.textStyle(11, FontWeight.w400, color)`.
- Sleep dialog title "Stop Audio In" duplicated: appears as both the `showPlatformSheet` `title:` argument (line 633) and hardcoded inside the sheet builder body (line 647). One source of truth.
- `_EmptyTab` at line 2066 renders icon at `alpha: 0.3` and text at full `textMuted` opacity — on Neumorphic the icon becomes near-invisible (1.96 * 0.3 = effectively 0 contrast).
- `_HistoryTile` subtitle at line 2020 applies `.withValues(alpha: 0.7)` on `textSecondary` — on Neumorphic, `textSecondary` at 70% opacity on `bgSurface` produces ~2.5:1, pushing it below AA.
- The `_AppleMusicThumb` at line 557 draws with `Paint()..color = color` where `color` comes from `ThemeTokens.of(context).textPrimary` (passed at line 473) — this is correct. But the `shadowColor` uses `ThemeTokens.of(context).bgOverlay.withValues(alpha: 0.35)` — on Frost where `bgOverlay` is 20% white, the shadow is nearly invisible. Minor, but noticeable.
- `_MiniSoundBars` in the Queue "Now Playing" strip (line 1831) always renders the animated bars regardless of `MediaQuery.disableAnimations` — the main `SoundBar` respects this flag but `_MiniSoundBars` does not.
- The progress bar `timeLabelTextStyle` at line 1430 uses bare `TextStyle` with no `fontFamily` — time labels will always render Inter on all themes.

## Questions to Consider

- "The bottom tray has a no-op 'Playing/Paused' status badge sitting alongside actionable buttons — does this status badge belong in the control tray, or should it move into the title row where it acts as ambient state rather than a competing affordance?"
- "Cover art occupies 85% of screen width with no tap interaction. Every other music player taps the cover to go to the album. Is NaviVibe deliberately removing that path, or is it missing?"
- "Three of six themes fail WCAG AA on `textMuted`. These are the themes (Neumorphic, Analog, Zen) that define NaviVibe's differentiation from Spotify. Is the contrast a token-definition problem or a signal that `textMuted` should be reserved for purely decorative purposes on light themes, with `textSecondary` used for all label text?"
