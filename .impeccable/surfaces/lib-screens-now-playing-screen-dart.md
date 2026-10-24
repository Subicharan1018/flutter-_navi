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
Constraints: single theme; Apple Music (iOS 26) played straight; AMOLED black chrome with green accent; never purple or pink chrome (hue guard); Now Playing must be rich, not plain; Pure-Apple Now Playing layout (no scroll-down cards); phone first; system Back always works; 44pt+ targets; reduced motion honoured; no runtime font fetching. Icons: Ionicons v7 (Ion / IonIcon).

## Direction contract

THESIS: The album is the room, and the room's light follows the music. Now Playing is drenched in the cover's own pixels flowing slowly behind white type: richer and open behind the cover while a song plays, dimming as the cover recedes when it pauses. Every song change moves through one spatial model: the covers form a deck you can swipe, and skips from anywhere glide along it. Refuses the category default: a static blurred cover under an 80% black scrim.

OWN-WORLD: Colour strategy: Drenched on Now Playing, Committed elsewhere. The field's deep tone and the mini player's ground come from the guarded cover palette; with nothing playing, the AMOLED fallback (black, #1C1C1E, green). Now Playing controls stay white with vibrancy (white 68% secondaries, idle pills at 15%, active pills solid white). Inter for UI, Inter Display for the title and lyrics, tabular numerals for times. Radii: cover 12, list art 6, queue mode buttons 14. Transport glyphs are Ionicons play-back / play-forward and a bare play/pause, no circles.

STORY: A glance tells the listener the song, the artist and how far in; a thumb pauses or skips; Lyrics and Queue open in place as the cover flies into a header, so they never lose the song; the queue shows history above and "Playing Next" below with Shuffle, Repeat, Autoplay and Smart Reshuffle as four icon buttons.

FIRST VIEWPORT: Phone: grabber at top; cover at 28dp margins, a little above centre, scaled to 0.84 on pause with a spring; title (Inter Display 22/700) and artist (19/500, 68%) anchored just above the scrubber, ★ and ⋯ right; scrubber with elapsed / honest format / −remaining; rewind · play/pause · forward; volume with speaker glyphs; bottom row Lyrics · Devices · Queue. Primary action: play/pause, dead centre of the lower third.

FORM: Pinned by the user (Spotify structure + Apple Music finish, then Apple Music played straight), position 1 of 1; no concept-seed roll. Seed key: none — user-pinned.

SIGNATURE: the living artwork field — a GPU shader that samples a 64px copy of the cover through slow flowing warps at 1/6 resolution, drifts only while playing, lights with play state, cross-fades between songs; plus the cover deck (swipe and glide) and the cover-to-header flight when Lyrics/Queue open.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved
- Last.fm/remote device naming for the Devices button relies on the existing session-sync service.
