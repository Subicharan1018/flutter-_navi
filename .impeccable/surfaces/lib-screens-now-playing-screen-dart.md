---
version: 1
slug: "lib-screens-now-playing-screen-dart"
primary_target: "lib/screens/now_playing_screen.dart"
related_targets: ["lib/widgets/mini_player.dart","lib/widgets/app_scaffold.dart"]
---

# Player surfaces — Now Playing, Queue, History, Lyrics, Mini player

Scope: the playback surfaces of NaviVibe (Flutter, Navidrome client). Mode: Operate.
Primary target: Android phone (390×844 class); secondary: Linux desktop (1440×900) wide adaptation.
User: Navidrome owner + friends; mostly Tamil film music and English pop; listens daily, often at night, phone in hand or on a desk.
Job: see what is playing, control it one-handed, read lyrics, shape what plays next, revisit what just played.
Constraints: single theme (all six legacy themes removed); brief pins "Spotify's structure + Apple Music's finish"; Now Playing must be rich, not plain; Pure-Apple Now Playing layout (no scroll-down cards); phone first; system Back always works; 48dp targets; reduced-motion honoured; no runtime font fetching.

## Direction contract

THESIS: The album is the room, and the whole house takes its colour. Now Playing is drenched in the cover's own pixels flowing slowly behind white type; the rest of the app re-tints to the song that's playing (mini player filled with the album colour, active states and progress in its vibrant hue, album pages bleeding their cover colour down the page). Refuses the category default: a static blurred cover under an 80% black scrim, and a grey app with one fixed accent.

OWN-WORLD: Colour strategy: Drenched on Now Playing, Committed everywhere else. Ground is near-black tinted by the current song (#000 mixed 6-10% with the album's deep tone), tonal steps derived from it; white text at 100 / 66 / 44%. A dynamic, contrast-corrected palette per song (deep, base, vibrant, glow) drives the accent role app-wide: Play button fill, progress, selection, the playing row, toggles. The mini player is a solid album-colour card; Queue and Lyrics are washed in it. With nothing playing, a curated rich fallback palette (deep indigo / magenta / amber) stands in. Now Playing controls stay white with vibrancy (heavier weight, white 60% secondaries) so any cover stays legible. Inter (text cut) for UI, Inter Display for the big title and lyrics, tabular numerals for times. Radii: large art 12, list art 6, sheets 28, pills for small toggles. Transport glyphs are Apple's double-triangle rewind/forward and a bare play/pause, no circles.

STORY: A glance tells the listener the song, the artist and how far in; a thumb pauses or skips; Lyrics and Queue open in place as the cover flies into a header, so they never lose the song; the queue shows history above and "Playing Next" below with Shuffle, Repeat and Autoplay as pills.

FIRST VIEWPORT: Phone: grabber at top; cover 334×334 at 28dp margins, scaled to 0.82 on pause with a spring; below it title (Inter Display 22/700) and artist (20/400, 60%) left, ★ and ⋯ glass circles right; 7dp scrubber (grows to 12dp while dragged) with elapsed / format / −remaining; rewind 40 · play/pause 60 · forward 40; volume slider with speaker glyphs; bottom row Lyrics · Devices · Queue. Primary action: play/pause, dead centre of the lower third.

FORM: Pinned by the user (Spotify + Apple Music), position 1 of 1; no concept-seed roll (brief-pinned direction beats the roll). Seed key: none — user-pinned.

SIGNATURE: the living artwork field — a GPU shader that samples a 64px copy of the cover through slow flowing warps at 1/8 resolution, drifts only while playing, cross-fades between songs; plus the cover-to-header flight when Lyrics/Queue open.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved
- Last.fm/remote device naming for the Devices button relies on the existing session-sync service.
