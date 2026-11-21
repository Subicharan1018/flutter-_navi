# Replay, second pass: research and signature ideas (2026-11)

First pass (year ribbon, month ledger) was tidy but quiet. This pass looks at
what year-in-review products do that people remember, then keeps only what fits
NaviVibe's rules: white on #000, opaque, no card containers, no glows, gradient
text or glass, colour only from album art, Apple Music finish.

## What others do

| Product | Memorable move | Translates? |
|---|---|---|
| Spotify Wrapped 2025 | Vertical, swipeable stories; palette mostly black and white with colour kept for artist images and covers; a "Top Artist Sprint" showing how your top five shifted month by month; motion prototyped with dummy data first. Sources: Spotify newsroom, Rive case study, Prolific North, Fast Company. | Yes: story mode, black-and-white with art as the only colour, rank-over-time idea. Skip the loud type collage and share-first layouts. |
| Apple Music Replay | A highlight reel as stories with animated transitions; Milestones (first play of a song or artist, longest consecutive streak) added 2023-24; Discovery and Loyalty added 2025; reachable from the app and updated monthly. Sources: MacRumors, 9to5Mac, TechRadar. | Yes, it is our peer. Milestones as typographic lines, not badges. |
| YouTube Music Recap 2025 | Opens on minutes, longest streak, top song; a listening calendar for your top artist; month-by-month trends; AI "character" chat. Sources: TechRadar, 9to5Google. | Calendar-for-top-artist and streak yes; AI chat and mascots no (invented claims). |
| Strava Year in Sport | Full-screen, code-driven animation per data point, built in Rive for 14 languages; monthly animated stats recap. Third-party tools draw GitHub-style heat calendars. Sources: Rive blog, Manual, Hello Monday. | Yes: one number per screen, heat strips. |
| Receiptify | The whole period as a receipt: monospaced list, dotted leaders, a total; instantly legible and shareable. Source: Receiptify about page. | Yes, as typography on black with dotted leaders, no paper card. |
| Last.fm / stats.fm / mystats.music | Listening clocks, month-by-month, time-of-day. | Already covered by the clock and ledger. |

Honest limit: the searches found marketing and press coverage, not design
critiques, so "why it works" below is our reading, not their claim.

## What translates, and what does not

Translates: one idea per screen; numbers that count up; art as the only colour;
a scrubbable overview; a receipt that compresses the year to one glance;
haptics on discrete steps.
Does not: gradients and glow, stickers, mascots, AI personality text, paper or
card chrome, anything that asserts what the server did not measure.

## Signature ideas (built)

1. **Your year as a record.** Charts were dropped twice (bars read as a graph,
   a poster reel read as a carousel). Research that pointed the way: My Listening
   Record cuts one groove per day you listened into a vinyl disc; Sony's
   gold-record data art by Visual Cinnamon turns data into the grooves of a
   record on purpose, favouring "eye catching" over readable numbers;
   year-ring layouts widen a ring with its quantity; Joy Division's pulsar
   cover (a ridgeline plot) shows how a stack of white lines on black becomes
   an icon. We took the record: January is the outer band, December the inner,
   like tracks on a side. A month's band has more grooves the more you listened,
   an empty month is bare vinyl. The label is the No. 1 song's cover and turns
   slowly (one revolution per 14 s, stopped under reduced motion). A tonearm
   rests on the selected month, starting on the busiest; drag or tap across the
   record to move it (selection tick per month), then Open. Monochrome, no
   glow, colour only from the cover on the label. Ridgeline (per-day lines)
   remains an option if the server ever sends daily data for the whole year.
2. **Year Story.** A full-bleed, auto-advancing story (tap right/left, hold to
   pause, existing `StoryPager`): minutes counting up, the No. 1 song with
   pulse rings, your top artists rising into place as their own photos
   (`artistCoverUrlProvider`), the year set in type (each month named at a size that follows its minutes), and the
   receipt. Reduced motion: no auto-advance, finished cards.
3. **Artists rise.** Artist portraits fade and rise 24 px into place, staggered
   60 ms, ease-out 360 ms, first appearance only; shelf on Replay and the story
   card.
4. **The receipt.** "Your year in one line", a column of dotted-leader rows
   (top song, top artist, listened, biggest month, peak hour, days with music,
   skipped). Text on black, hairline dashes top and bottom, no container.
5. **Count-up figures.** Minutes roll like an odometer in the story (existing
   `NumberRoll` driven by the card's clock).

Not built, noted for later: shared-element transition from a ledger row into
its month sheet, a month-by-month artist rank race (needs top five per month
from the server), a top-artist listening calendar (needs per-day artist data).

## Motion rules used

Ease-out, 200-700 ms, one controller per surface, `RepaintBoundary` around
animated bars, selection held in a `ValueNotifier` so only the readout and bars
rebuild, `context.motionFull` / `disableAnimations` checked before any tween,
the only loop is the record label (a 14 s turn in its own RepaintBoundary), stopped under reduced motion and disposed with the widget.
