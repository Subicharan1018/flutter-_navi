# Product

## Register

product

## Users
Subsonic and Navidrome music server users who desire a premium, fast, and highly-immersive audio client interface on Android/Linux. They want smooth navigation, robust playback control, and deep, context-respecting visual theme options.

## Product Purpose
A state-of-the-art Flutter audio client featuring dithered position shuffle, gapless playback, SQLite listening analytics, and dynamic visual styling options. The app elevates private streaming libraries to commercial streaming app aesthetics.

## Brand Personality
- **Adaptive**: Visually responds to the chosen theme mode (Spotify, Aura, Frost, Neumorphic, Analog, Zen) rather than forcing hardcoded brand colors.
- **Immersive**: Highly interactive, utilizing rich animations, smooth transitions, and tactile feedback.
- **Polished**: Respects typographic spacing, visual hierarchy, and precise alignment.

## Anti-references
- **Hardcoded Colors**: Overriding theme-specific palettes with generic green/blue gradients or Spotify-green overrides on non-Spotify themes.
- **Overloaded Cards**: Excessive nesting of boxes or generic borders that clutter screen layouts.
- **AI-scaffolding clues**: Fake eyebrows, generic marketing text, or hardcoded numbered lists where they carry no information.

## Design Principles
- **Cohesive Themability**: Every UI element must respect the current `ThemeTokens.of(context)` settings.
- **Music-first Hierarchy**: Layouts must elevate covers, song titles, artists, and playback affordances first.
- **Responsive Layout**: High density elements must transition cleanly between portrait and landscape modes.

## Accessibility & Inclusion
- Contrast ratio ≥ 4.5:1 for body and placeholder texts.
- Focus states and semantic labels for interactive elements (such as `Open Settings`, `Play playlist`).
- Support for `MediaQuery.of(context).disableAnimations` to gracefully bypass transitions for users with motion sensitivity.
