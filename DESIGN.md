---
name: NaviVibe
description: A theme-shifting Subsonic/Navidrome music client where the album art is the light source.
colors:
  # Normative palette = the default "Spotify" theme (lib/core/theme.dart legacy base).
  # The other five themes (Aura, Frost, Neumorphic, Analog, Zen) override these via
  # AppThemeTokens; see the Colors section for their accents. Never hardcode — read
  # ThemeTokens.of(context).
  bg-base: "#000000"
  bg-surface: "#121212"
  bg-elevated: "#181818"
  bg-overlay: "#282828"
  accent: "#1DB954"
  accent-dim: "#158A3E"
  gold: "#E8C547"
  text-primary: "#FFFFFF"
  text-secondary: "#B3B3B3"
  text-muted: "#7F7F7F"
  outline: "#2A2A2A"
  error: "#CF6679"
typography:
  display:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "32px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.5px"
  headline:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "-0.3px"
  title:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "16px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "normal"
  body:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "normal"
  label:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "1.2px"
rounded:
  sm: "4px"
  md: "8px"
  lg: "12px"
  xl: "16px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "#000000"
    rounded: "{rounded.pill}"
    padding: "12px 32px"
  button-primary-disabled:
    backgroundColor: "{colors.accent-dim}"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.pill}"
  chip:
    backgroundColor: "{colors.bg-overlay}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.pill}"
    padding: "6px 12px"
  chip-selected:
    backgroundColor: "{colors.accent}"
    textColor: "#000000"
    rounded: "{rounded.pill}"
  card:
    backgroundColor: "{colors.bg-surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.lg}"
    padding: "16px"
  song-row:
    backgroundColor: "transparent"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "8px 16px"
---

# Design System: NaviVibe

## 1. Overview

**Creative North Star: "The Album as Atmosphere"**

The cover is the light source. NaviVibe extracts a four-color palette from each album's artwork (`PaletteCache`, LRU, 50 entries) and lets that palette breathe behind the Now Playing screen through a custom fluid fragment shader (`FluidBackground`). The interface is not a frame around the music — it dissolves into the song's own world. Covers, titles, and playback affordances lead; chrome recedes. When a track is playing, the screen should feel less like an app and more like the room the record is playing in.

This atmosphere is delivered through six fully-committed themes — **Spotify, Aura, Frost, Neumorphic, Analog, Zen** — that re-skin the entire surface, not just an accent. Each ships a complete `AppThemeTokens` palette and its own typeface. The discipline that keeps this from becoming chaos is a single token contract: every widget reads `ThemeTokens.of(context)` and **never** hardcodes a color. Spotify's green must never leak onto Analog's warm vinyl; Zen's monochrome must never inherit Aura's purple. The themes are six atmospheres over one structural skeleton.

This system explicitly rejects **hardcoded brand colors** (generic green/blue gradients forced onto non-Spotify themes), **overloaded nested cards** with decorative borders, and **AI-scaffolding** (fake eyebrows, numbered markers that carry no information, generic marketing copy). NaviVibe is a private library elevated to commercial-streaming polish, not a SaaS dashboard wearing a music skin.

**Key Characteristics:**
- **Theme-agnostic by contract** — all color/type flows through `ThemeTokens.of(context)`.
- **Cover-first hierarchy** — album art drives both layout focus and the live palette.
- **Atmospheric depth** — fluid shaders and album-derived color, not flat fills, behind playback.
- **Tactile, restrained motion** — press-scale feedback (`CupertinoClickable`), 150–250ms state transitions, `easeOutCubic`.
- **Dense but breathable** — library and queue screens carry many rows; spacing rhythm keeps them legible.

## 2. Colors

A dark-default system (Spotify/Aura/Frost) with three light atmospheres (Neumorphic/Analog/Zen). The normative frontmatter palette is the default **Spotify** theme; the other five override every token below via `AppThemeTokens`. Color is never decorative — the accent marks the primary action, the current selection, and live state only.

### Primary
- **Vibrant Green** (`#1DB954`): The Spotify-theme accent. Play buttons, active progress track, current selection, focus. Used on ≤10% of any screen.
- **Per-theme accent override** — the accent is the one token most likely to change identity per theme:
  - Aura → **Electric Lavender** (`#BB86FC`)
  - Frost → **Ice Blue** (`#64D2FF`)
  - Neumorphic → **Calm Blue** (`#4A90D9`)
  - Analog → **Oxide Red** (`#B5451B`, vinyl-groove rust)
  - Zen → **Pure Black** (`#111111`, the accent IS the ink)

### Secondary
- **Accent Dim** (`#158A3E` in Spotify): Disabled and inactive states of the accent. Each theme supplies its own dimmed variant; never fake it by lowering opacity on the live accent.
- **Album-Derived Palette** (runtime, 4 colors): Extracted from cover art via `PaletteCache`, fed into the fluid shader behind Now Playing and into mesh gradients (Aura). Fallback when extraction fails: `#1A1A2E → #16213E → #0F3460 → #533483`.

### Tertiary
- **Gold** (`#E8C547` in Spotify): Stars, favourites, ratings only. A deliberate warm signal distinct from the accent. Zen flattens even this to monochrome (`#222222`) — proof the system honors theme identity over convention.

### Neutral
- **Bg Base** (`#000000`): Scaffold / page background. The darkest layer.
- **Bg Surface** (`#121212`): Cards, sheets, list backgrounds.
- **Bg Elevated** (`#181818`): Popovers, tooltips, raised rows.
- **Bg Overlay** (`#282828`): Modal scrims, chip backgrounds.
- **Text Primary** (`#FFFFFF`): Song titles, headings, primary labels.
- **Text Secondary** (`#B3B3B3`): Artist names, supporting metadata.
- **Text Muted** (`#7F7F7F`): Timestamps, technical captions, inactive nav.
- **Outline** (`#2A2A2A`): Hairline dividers and borders — 1px only.
- **Error** (`#CF6679`): Failed downloads, playback errors.

### Named Rules
**The Themability Rule.** Every color comes from `ThemeTokens.of(context)`. Hardcoding any hex in a widget is forbidden. If you need a color the tokens don't expose, the fix is a new token on `AppThemeTokens`, applied to all six themes — never a literal.

**The One Accent Rule.** The accent marks primary action, current selection, and live state. It is forbidden as decoration, as a gradient fill on cards, or as a section divider. Its scarcity is what makes a playing track read instantly.

**The No-Cross-Bleed Rule.** A theme's identity is total. Spotify green on Analog, Aura purple on Zen, glass on Neumorphic — all prohibited. If a screen looks the same across two themes, the screen is wrong.

## 3. Typography

**Default Font:** Inter (with system-ui, sans-serif fallback) — Spotify, and the app-wide `TextTheme` baseline.
**Per-theme display faces:** Space Mono (Aura), Nunito (Frost), DM Sans (Neumorphic), Playfair Display (Analog), Cormorant Garamond (Zen).

**Character:** Inter is the workhorse — neutral, dense-legible, music-first. The theme typefaces are the loudest signal of a theme's atmosphere: Cormorant's editorial serif makes Zen feel like a gallery placard; Space Mono makes Aura feel synthetic; Playfair makes Analog feel like a record sleeve. Type scale is a **fixed px scale** (product UI, consistent DPI), never fluid clamp.

### Hierarchy
- **Display** (700, 32px, 1.1, -0.5px tracking): Screen titles, the largest Now Playing track title.
- **Headline** (700, 24px, 1.15, -0.3px): Section headers ("Recently Played", "Made For You").
- **Title** (700, 16px, 1.2): Song titles in rows, card titles, dialog headers.
- **Body** (400, 14px, 1.45): Descriptions, secondary content. Cap prose at 65–75ch.
- **Label** (600, 11px, +1.2px tracking): Tab labels, nav captions, technical metadata. The one place tracking is widened — and only here.

### Named Rules
**The Fixed-Scale Rule.** Type sizes are fixed px, not `clamp()`. A title that shrinks inside a sidebar or mini-player looks broken, not responsive. The Zen theme already scales its base 1.08× internally — do not stack a second fluid scale on top.

**The One-Face-Per-Theme Rule.** Each theme uses a single family across all weights. Pairing two sans-serifs within one theme is forbidden; contrast comes from weight (400/600/700), not from mixing families.

## 4. Elevation

A hybrid system where **depth strategy is itself themed.** Dark themes (Spotify, Aura) convey elevation through tonal layering — base → surface → elevated → overlay get progressively lighter, with shadows nearly invisible. Two themes invert this with signature physical depth.

### Shadow Vocabulary
- **Neumorphic dual-shadow** (`NeuBox`): Every surface casts two shadows — a dark one (`neuDark`, offset +6/+6) and a light one (`neuLight`, offset -6/-6), blur 14. Pressed state shrinks offset to ±2 and blur to 6. This is the entire Neumorphic identity; without it the theme is flat gray.
- **Glass depth** (`GlassBox`): A single diffuse drop (`rgba(0,0,0,0.25)`, blur 20, spread -4) under translucent frosted panels (Frost theme), paired with a 1px light border to catch the edge.
- **Ambient row lift** (dark themes): Hover/selected rows step up one tonal layer (surface → elevated) rather than casting a shadow.

### Named Rules
**The Tonal-First Rule.** On dark themes, depth is lightness, not shadow. Reach for `bgElevated`/`bgOverlay` before a `BoxShadow`. Shadows belong to Neumorphic and Frost; importing them into Spotify/Aura/Zen makes the UI look like a 2014 app.

**The Pressed-State Rule.** `NeuBox` and `CupertinoClickable` express touch physically — neumorphic surfaces invert their shadow, tappable elements scale to 0.97. State must be felt, not just colored.

## 5. Components

Every interactive element reads its colors from `ThemeTokens.of(context)` and presses via `CupertinoClickable` (100ms scale to 0.97, `easeInOut`).

### Buttons
- **Shape:** Pill / stadium for primary actions and chips (`999px`); `12px` (lg) for blocky secondary buttons.
- **Primary:** Accent fill, black text (`onPrimary` is black on dark themes, white on light), `12px 32px` padding. The play button is the canonical primary — accent circle, centered glyph.
- **Hover / Focus:** No splash (`NoSplash`, transparent highlight/hover — disabled app-wide). Feedback is the press-scale, not a ripple. Focus states carry a visible accent ring for accessibility.
- **Disabled:** `accentDim` fill, `textMuted` label — never the live accent at lowered opacity.

### Chips
- **Style:** `bgOverlay` background, `textPrimary` label, stadium border, no side stroke. `6px 12px` padding.
- **State:** Selected → accent fill with inverted (black/white) label. Used for genre filters and library facets.

### Cards / Containers
- **Corner Style:** `12px` (lg) default; `16px` (xl) for hero/album tiles; `8px` (md) for compact rows.
- **Background:** `bgSurface`; raised content uses `bgElevated`. On Frost use `GlassBox`, on Neumorphic use `NeuBox`.
- **Shadow Strategy:** Tonal layering by default (see Elevation). Physical shadow only on Frost/Neumorphic via their helpers.
- **Border:** 1px `outline` hairline, or none. Never a thick colored stripe.
- **Internal Padding:** `16px` (lg) standard.

### Inputs / Fields
- **Style:** Filled `bgElevated` background, `12px` radius, no heavy stroke at rest.
- **Focus:** Border shifts to `accent`, 1px → visible accent edge. No glow except where a theme's identity (Frost) warrants it.
- **Placeholder:** Must hit 4.5:1 contrast — use `textSecondary`, not `textMuted`.

### Navigation
- **Bottom nav:** `bgBase` background, zero elevation. Selected item = accent icon + accent 11px label; unselected = `textMuted`. Fixed type, no shifting.
- **App bar:** Transparent, flat (elevation 0), left-aligned title, `textPrimary` icons — lets the fluid background and album art show through.

### Signature Components
- **FluidBackground:** A custom fragment shader (`FluidShaderLoader` → `_FluidPainter`) driven by the album-derived palette, rendered behind Now Playing. Pre-warmed in `main.dart`. The literal embodiment of "The Album as Atmosphere."
- **Now Playing progress bar:** `SliderTheme + Slider` (track 4px, accent active, `textPrimary` thumb), matched to the mini-player. **Never** a custom painter — `_NeonTrackPainter` and `_GlassThumbShape` are forbidden here.
- **Mini player:** Omnipresent, swipe-to-switch (`onHorizontalDragEnd`, 100px/s threshold, 50ms slide), `AppRouteTransitions.slideUp()` to expand. Coupled to `PlayerProvider`.

## 6. Do's and Don'ts

### Do:
- **Do** read every color, text style, and radius from `ThemeTokens.of(context)`. A new color means a new token applied to all six themes.
- **Do** lead every layout with cover art, then title, then artist, then playback affordances — music-first hierarchy.
- **Do** drive Now Playing atmosphere from the album-derived `PaletteCache` palette and the fluid shader.
- **Do** keep state transitions 150–250ms on `easeOutCubic`/`easeOut`; respect `MediaQuery.disableAnimations` and `prefers-reduced-motion`.
- **Do** express touch physically — `CupertinoClickable` press-scale, `NeuBox` shadow inversion.
- **Do** hold body and placeholder text at ≥4.5:1 contrast; use `textSecondary` for placeholders, never `textMuted`.
- **Do** use the `SliderTheme + Slider` for the Now Playing progress bar, matching the mini player.

### Don't:
- **Don't** hardcode colors. No generic green/blue gradients, no Spotify-green override on a non-Spotify theme. (PRODUCT.md anti-reference: *"Hardcoded Colors"*.)
- **Don't** let a theme's identity bleed into another — Aura purple on Zen, glass on Neumorphic, green on Analog are all prohibited.
- **Don't** overload screens with nested cards or generic decorative borders. (PRODUCT.md anti-reference: *"Overloaded Cards"*.)
- **Don't** add fake eyebrows, numbered section markers, or generic marketing copy that carries no information. (PRODUCT.md anti-reference: *"AI-scaffolding clues"*.)
- **Don't** use a `border-left`/`border-right` greater than 1px as a colored accent stripe on rows, cards, or callouts.
- **Don't** use the accent as decoration, a card-fill gradient, or a divider — primary action, selection, and live state only.
- **Don't** replace the progress bar with `_NeonTrackPainter` or `_GlassThumbShape`, and don't import shadows into the flat dark themes.
- **Don't** use fluid `clamp()` type scales; the px scale is fixed for product-UI consistency.
