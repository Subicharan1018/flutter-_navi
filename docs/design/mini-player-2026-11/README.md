# Windows mini player — redesign, November 2026

## What was wrong

The pop-out (commit 78426e6) was the full player squeezed into a 380 x 168 box:
a small thumbnail, a title, a full-width seek bar and three transport buttons on
a black card. It had no identity (the cover was a 48 px thumbnail), spent a
third of its height on chrome, offered no like, volume, lyrics or pin, forgot
where the user had put it, and could only ever be one size.

## Research (what the good ones do)

Sources: Apple's Music support pages, TechRadar and GSMArena on the Spotify
Miniplayer, Cider and YouTube Music community threads. Where the search found
nothing (Windows 11 media flyout, foobar2000 layouts) this document says so
rather than guessing.

| Player | What to borrow |
| --- | --- |
| Apple Music MiniPlayer | The cover is the window; controls appear when the pointer is over the art; it can shrink smaller still; a setting keeps it above other windows; lyrics and queue are a click away. |
| Spotify Miniplayer (2024) | Two designs (a strip and a larger one), always on top, independent of the main window, opened from a small icon in the player bar. |
| Cider / YouTube Music users | Ask for: open straight to title and controls (not only a cover), and a window independent of the main one. |
| Windows 11 media flyout, foobar2000, Dynamic Island widgets | No usable result from the search. The Dynamic Island idea (one object that grows from a pill into a card) informed the strip → square toggle. |

Lessons: art first; controls only as loud as they need to be; always-on-top is
a user choice, not a given; two sizes cover "glance" and "look at it".

## Direction: "the cover is the window"

Monochrome white on black (DESIGN.md), opaque, no cards, no shadows, own
`NaviGlyph` icons. The only colour is the cover's.

**Strip, 360 x 96.** The cover flush on the left at full height. On the right:
title (`FittingTitle`) with the time (`1:24 / 3:58`) at its end, a second line
that is the live lyric line while one is sung and the artist otherwise, then
previous / play / next on the left and favorite, pin, shape and way-back on the
right. The scrubber is the window's bottom edge: a 3 px line the full width
that thickens under the pointer, with a time bubble while hovering or dragging.

**Square, 360 x 360.** The cover full-bleed (`FullBleedCover`, the same fade as
Now Playing, with a taller zone). Title, artist, the live lyric line, transport
and a labelled scrubber sit on the fade in the cover's own deep tone. The pin,
shape and way-back buttons fade in when the pointer is over the window or a
control has keyboard focus.

Behaviour shared by both:

- Drag from anywhere that is not a control; double-click switches shape.
- Wheel changes the volume 5% a notch; a toast names the level for 1.3 s.
- Keys: Space, Left / Right (seek 5 s), Ctrl+Left / Right (previous / next),
  Up / Down (volume), L (favorite), Esc (back to the full player).
- Remembers the shape, the pin and where it was left (a corner far off every
  screen is ignored). Shape change keeps the top-left corner.
- Track change: the cover slides out left and the next one in from the right
  (260 ms); the lyric line cross-fades. First open fades in over 160 ms.
- Reduced motion (system or the app setting): every one of those becomes a cut.
- Text is clamped at 1.15x inside the window, because a fixed-size window
  cannot grow; nothing overflows at 1.3x.

## Performance

No controller runs while idle. The scrubber and clock listen to the player's
position stream at 250 / 500 ms resolution inside their own `RepaintBoundary`;
the lyric line is a `select` that changes once per line; the title scrolls
twice then stops (`FittingTitle`); the hidden app is already `Offstage` with
tickers off. No per-frame `setState`.

## Not done / follow-ups

- Position is checked with a coarse range, not against real monitors
  (window_manager has no screen list); a screen-aware clamp needs
  `screen_retriever`.
- Time-bubble and window-button strings are English only, like the rest of the
  Windows shell.
- Goldens here: `test/goldens/mini_player/` (strip and square at 1x and 1.3x).
