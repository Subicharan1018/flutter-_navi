# Product

## Register

product

## Users
Navidrome owners and the friends they share their server with — mostly
Tamil film music and English pop — listening daily on Android phones (often
at night, one-handed), on Android TV and on Windows desktops. They expect the
polish of the commercial apps they left, on music they own.

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

## Brand Commitments
- **Apple Music, played straight.** The app is the iOS 26 Apple Music
  experience on Android, at full fidelity with no irony and no smuggled quirks. Its peers
  and craft bar are Apple Music and Apple Podcasts on iPhone. The only
  translations are a monochrome white accent where Apple uses red (there is
  no green), and a pure AMOLED black ground (#000000) with no tint.
- **Monochrome accent, never purple or pink.** Controls are white on black;
  colour comes only from the playing artwork, whose sampled colours are
  hue-guarded away from 250–340°.
- **Opaque.** Chrome is opaque. Two exceptions: artwork fading into its page
  colour, and the phone's bottom dock (Jam pill, mini player, tab bar), one
  frosted-glass sheet documented in DESIGN.md. Windows and TV have no glass,
  no scrims and no shadows on panels.
- **Three platforms, each on its own rules.** Android is the Apple Music
  experience described above. Android TV is a 10-foot, remote-first layout.
  Windows is its own desktop app (top bar, library rail, song table, player
  bar; mouse and keyboard first): it shares data and logic with the phone, not
  its layouts, physics or gestures.

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
- **Each platform on its own rules**: the phone leads and keeps its Apple
  Music feel; Windows and TV are designed for their own input (pointer and
  keyboard, remote) with their own layouts, never a stretched phone.
- **Performance is a feature**: one cover decode path, isolate palette
  extraction, low-resolution shader field, scoped rebuilds.

## Accessibility & Inclusion
- Text ≥ 4.5:1 (accent is contrast-corrected per song); 44pt minimum touch targets on a phone (Apple's HIG floor), at least 28 px click targets on Windows, a visible white focus ring on every keyboard stop.
- Semantic labels and slider actions on every control.
- Reduced motion honoured everywhere (field drift, marquee, scroll animation).
- System Back / Esc close panes before the player; predictive back on Android.
