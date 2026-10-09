# Product

## Register

product

## Users
Navidrome owners and the friends they share their server with — mostly
Tamil film music and English pop — listening daily on Android phones (often
at night, one-handed) and on Linux desktops. They expect the polish of the
commercial apps they left, on music they own.

## Product Purpose
A premium Subsonic/Navidrome client: gapless playback, a learned smart
shuffle (NaviVibe shuffle server), synced lyrics, listening analytics, and
multi-device session handoff — presented with Spotify's structure and Apple
Music's finish.

## Brand Personality
- **Alive**: the app takes its colour from whatever is playing; nothing is a
  fixed grey shell.
- **Calm and exact**: restrained chrome, precise type, motion that responds to
  the finger and settles quietly.
- **Honest**: shows what the server knows (real file format, real lyrics,
  real devices) and never invents claims.

## Anti-references
- Theme pickers and multiple visual modes — there is one, living theme.
- A grey app with a single fixed brand accent.
- Glassmorphism, film grain, glows, gradient text, decorative borders.
- AI-scaffolding: eyebrows, numbered sections, marketing copy inside the app.
- Fake badges ("Lossless" on an MP3) or invented colours not in the artwork.

## Design Principles
- **Album-derived colour**: every role comes from the playing cover via
  `ThemeTokens` / `NowPlayingStyle`.
- **Music-first hierarchy**: cover, title, artist, then playback affordances.
- **Direct manipulation**: drags track 1:1, releases carry velocity, every
  press responds on touch-down.
- **Phone first, desktop faithful**: phone layouts lead; wide layouts
  restructure (side-by-side), never stretch.
- **Performance is a feature**: one cover decode path, isolate palette
  extraction, low-resolution shader field, scoped rebuilds.

## Accessibility & Inclusion
- Text ≥ 4.5:1 (accent is contrast-corrected per song); 48 dp targets.
- Semantic labels and slider actions on every control.
- Reduced motion honoured everywhere (field drift, marquee, scroll animation).
- System Back / Esc close panes before the player; predictive back on Android.
