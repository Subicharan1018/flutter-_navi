# Smart Shuffle page: direction

**What the page is for.** One question, answered at a glance: *what is this
mix tuned to, right now, and how sure is it?* Then one tap to play it. Familiar
vs Discover, "Describe a mix" and the song list serve that.

**What was bland.** A centred cover, a centred title, two capsules: the same
header every playlist has. The moment (the thing that makes this page
different) was a grey footnote.

**Idea: the moment is the hero.** The time-of-day word ("Late Morning") is the
largest thing on the page, left-aligned, in display weight. Under it, two
honest pieces of data drawn in monochrome, no charts library:

- **The day line**: a hairline ruler of the 24 hours. Hours already lived are
  white, hours to come are dim, the current hour is a taller tick with the
  clock time beside it. It slides to "now" once on first show (not with
  reduced motion). Source: the hour in `request_context.timestamp_ist`; hidden
  if the server didn't send one.
- **Closeness**: four short bars, filled by `fallback_level` (exact moment =
  four, cold start = one), with the plain-language sentence beside it.

The cover mosaic becomes a stamp beside the word (right on phone, left on
Windows like an album header). Season, weather and temperature are one accent
line under the word. No card containers, no eyebrow, no glow.

**Hierarchy (phone).** mode switch, moment word + stamp, day line, closeness,
Play / Reshuffle, Describe a mix (with its "Tuned for …" result), starter row,
songs.

**Type.** Moment word 40 phone / 56 Windows (display, w800, tight). Everything
else on the existing scale.

**Platforms.** Phone: stamp right, full-width capsules. Windows: stamp left,
compact buttons, same song table as every other list, no shadows. TV reaches
this page only through the shared shell and uses the phone layout.

**Motion.** One: the day-line marker settling on now (450 ms ease-out).
Reduced motion: drawn in place.

**States kept.** Syncing, loading skeleton, error with retry, empty, data;
described-mix busy / error / result.
