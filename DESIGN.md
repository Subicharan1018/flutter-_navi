---
name: NaviVibe
description: A Navidrome music client with Spotify's structure and Apple Music's finish, coloured by the album that is playing.
colors:
  # There is no fixed palette. Every role below is DERIVED per song from the
  # cover (lib/core/album_palette.dart) and exposed via ThemeTokens.of(context).
  # Values shown are the fallback used when nothing is playing.
  palette-deep: "#120C24"      # darkest cover tone — tints all grounds
  palette-base: "#3B1F5E"      # mid tone — mini player fill, panel wash
  palette-vibrant: "#FF5C8A"   # accent role, contrast-corrected ≥ 4.5:1 on deep
  palette-glow: "#FFB454"      # second hue — gradients, field highlights
  bg-base: "#000000 ⊕ 55% deep"
  bg-surface: "#111111 ⊕ 45% deep"
  bg-elevated: "#1B1B1B ⊕ 40% deep"
  bg-overlay: "#2A2A2A ⊕ 35% deep"
  accent: "palette-vibrant"
  on-accent: "#0B0B0B or #FFFFFF by luminance"
  text-primary: "#FFFFFF"
  text-secondary: "#FFFFFF @ 66%"
  text-muted: "#FFFFFF @ 44%"
  outline: "#FFFFFF @ 8%"
  gold: "#FFC94D"
  danger: "#FF5D73"
typography:
  text-face: "Inter 4.1 (bundled) — sizes < 20pt"
  display-face: "Inter Display 4.1 (bundled) — sizes ≥ 20pt, weight ≥ 500"
  tracking: "size-specific: +1% ≤11pt · 0 ≤13 · −0.8% ≤17 · −1.6% ≤24 · −2.2% ≤34 · −2.8% above"
  numerals: "tabular for every time / count"
rounded:
  list-art: "6px"
  player-cover: "12px (7px in header)"
  card: "12px"
  sheet: "28px top"
  pill: "999px (small toggles only)"
motion:
  press: "scale on pointer-down 90ms, release easeOutBack 260ms"
  state: "180–280ms easeOutCubic"
  layout: "420–480ms easeInOutCubic (cover → header morph)"
  gestures: "springs carrying release velocity; Apple momentum projection for dismiss"
---

# NaviVibe — Design System

## 1. Idea

**The album is the room, and the whole house takes its colour.**

NaviVibe has exactly one theme, and it is alive. The cover of the song that
is playing is decoded once (64 px), its palette extracted off the UI thread,
and every colour role in the app is derived from it: the near-black grounds
are tinted with the cover's deep tone, the accent is its vibrant tone
(contrast-corrected), the mini player is filled with its base tone, and Now
Playing is drenched in the cover's own pixels flowing slowly behind white type.

Structure comes from **Spotify** (dense true-black library, floating mini
player, bottom tab bar, desktop three-pane shell with a bottom player bar).
Finish comes from **Apple Music** (living artwork background, cover that
recedes on pause, bare transport glyphs, elastic scrubber, in-place Lyrics and
Queue, big bold lyrics).

## 2. Colour

Strategy: **Drenched** on Now Playing, **Committed** everywhere else.

| Role | Source | Used for |
|---|---|---|
| `palette.deep` | darkest cover hue, L≈8.5% | tints `bgBase…bgOverlay`; Now Playing scrim tone |
| `palette.base` | cover hue, L≈24% | mini player fill, side-panel wash, album/playlist headers |
| `palette.vibrant` → `accent` | cover hue, raised until ≥ 4.5:1 on `deep` | Play button fill, progress, selection, playing row, toggles, focus |
| `palette.glow` | strongest second hue ≥ 40° away | gradients, fallback field |
| `onAccent` | black or white by luminance | anything sitting on `accent` |

Extraction (`extractAlbumPalette`) weights each pixel by **area × √saturation ×
value** over a 24-bin hue histogram, so a cover reads as the colour a person
would name (a pale-sky pop cover → blue, not skin tone). Monochrome covers stay
neutral: their accent becomes a soft white rather than an invented hue.
Nothing is ever substituted with a colour that isn't in the artwork.

**Rules**
- Read colour only from `ThemeTokens.of(context)` (app chrome) or
  `NowPlayingStyle` (player panes). A hex literal in a widget is a bug.
- On Now Playing, controls and text are **white with vibrancy** (heavier
  weights, white-at-opacity secondaries) — never tinted grey — so they stay
  legible on any cover.
- Anything on an accent fill uses `onAccent`. Never hard-code black.
- State colours (`danger`, `positive`, `gold`) are fixed and only carry meaning.

## 3. Typography

Inter 4.1 is bundled (`assets/fonts`, SIL OFL). It is the closest open face to
SF Pro, and ships an optical **Display** cut — NaviVibe switches to it at 20 pt
and above, the way SF switches Text → Display. Call `naviText(size, weight,
color)`; it applies the face, size-specific tracking, and tabular figures when
asked.

| Use | Size / weight |
|---|---|
| Lyrics (phone / desktop) | 30 / 38 · 800 Display |
| Now Playing title / artist | 22 · 700 Display / 19 · 500 |
| Section headers ("Playing Next") | 19 · 700 Display |
| Row title / subtitle | 15 · 600 / 13 · 400 |
| Scrubber times | 12 · 600 tabular |
| Quality label | 10.5 · 600, +0.6 tracking |

## 4. Surfaces & depth

Depth is **tonal** (each ground is one album-tinted step lighter). Shadows exist
in exactly two places: the Now Playing cover (soft, deep-toned, offset down)
and the floating mini player. No glass, no noise, no neumorphism, no
decorative borders.

## 5. Components

- **Living artwork field** (`lib/player/artwork_field.dart`,
  `shaders/artwork_field.frag`). Three counter-rotating, flow-warped, softly
  sampled copies of the cover, rendered at ⅙ resolution and upscaled. Drifts
  only while playing (30 fps cap), stops when covered or when the OS reduces
  motion, cross-fades between songs. Deepens behind the controls for
  legibility; dims further when Lyrics/Queue are open.
- **Now Playing (phone)**. Grabber · cover (springs to 84% on pause, swipe
  sideways to skip) · title row with ★ and ⋯ glass circles · elastic scrubber
  with elapsed / honest format / −remaining · ⏪ ⏯ ⏩ bare glyphs · volume ·
  Lyrics / Devices / Queue. Lyrics or Queue swap in place: cover and title fly
  into a 60 px header, the pane rises beneath. Drag down anywhere to dismiss;
  the route follows the finger and projects the release velocity.
- **Now Playing (wide)**. Cover and controls left, lyrics or queue right.
- **Queue pane**. History above the anchor (scroll up), "Playing Next" with
  Shuffle / Repeat / Autoplay pills (long-press Shuffle for styles), drag
  handles, swipe to remove.
- **Lyrics pane**. Active line full white, others 26–38%; emphasis by opacity
  and 0.965 scale, never font-size animation. Tap a line to seek. Auto-follow
  pauses for 4 s after the user scrolls. Breathing dots during intros.
- **Mini player**. Solid `palette.base` card, cover, title/artist, morphing
  play/pause, next, 2 px progress. Swipe sideways to skip, up to open.
- **Desktop bar**. Spotify layout; accent play button; elastic scrubber with
  times either side; Lyrics / Queue / About toggles with an "on" dot.
- **Press feedback**. `CupertinoClickable` / `GlyphButton`: respond on
  pointer-down (scale + soft disc), spring back on release.

## 6. Motion

One authored moment: the cover → header flight when Lyrics/Queue open.
Everything else is feedback: 90 ms presses, 180–280 ms state changes,
springs for anything the finger touched. All motion has a reduced-motion
path (no drift, no marquee, instant scroll).

## 7. Do / Don't

**Do** derive every colour from the palette; keep player text white with
vibrancy; use `CoverImage` for every cover (one decode path, cache-width
aware); keep expensive effects bounded (low-res field, `RepaintBoundary`
around anything that ticks); give every control a 48 dp target and a semantic
label.

**Don't** add themes, light mode, glass, grain, glows, or gradient text; claim
"Lossless" for lossy files (use `qualityLabel`); animate font size; watch the
whole `playerProvider` in a widget (select the fields you render).
