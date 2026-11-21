# Replay direction

Replay is a year told as one shape, then read month by month. No cards: type,
hairlines and one white mark on black.

**The year** (`ReplayScreen`)
- Hero stays the mosaic of top-song covers with Play / Shuffle (Apple Music
  playlist form).
- Headline figures sit under hairlines, as before.
- **Year ribbon**: twelve bars, one per month, the busiest month in white and
  the rest dimmed; a sentence above names it ("October was your biggest month,
  24h"). Tapping a bar opens that month. Bars rise once on entry; reduced
  motion draws them at full height.
- **Month ledger** replaces the card shelf: one row per month with its top
  song's cover, top artist, minutes and a hairline bar scaled against the
  busiest month. Empty months are drawn quiet and are not tappable.
- **No. 1** gets its own row treatment: a larger cover and a headline-weight
  title, so the top song and the rest of the list are not the same size.

**The month** (`MonthSheet`, `MonthScreen`)
- The month's minutes lead as the largest figure; secondary figures follow.
- Daily bars mark the peak day in white, dim the rest, label the axis (1,
  middle, last) and say the peak in words ("Biggest day: the 14th, 38 min").
- Story button and story cards keep their behaviour; story cards already use
  clock-driven staggered motion and honour reduced motion.

Data contracts are unchanged; every async surface keeps loading, error, empty
and data states.
