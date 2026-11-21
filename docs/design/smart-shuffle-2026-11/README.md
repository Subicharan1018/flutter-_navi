# Smart Shuffle, second pass: research and signature ideas (2026-11)

First pass (commit 43fbe21) gave the page a time-of-day word, a day ruler and
closeness bars. It was tidy but still a list under a header. This pass asks what
the best "smart mix" experiences make memorable, keeps only what fits NaviVibe's
rules (white on #000, opaque, no card containers, no glows, gradient text or
glass, colour only from album art, Apple Music finish, own NaviGlyph icons,
each platform on its own rules).

## What others do

| Product | Memorable move | Translates? |
|---|---|---|
| Spotify DJ | A personality, not a list: spoken commentary explaining picks, and a way to ask for a different mood; Spotify's design lead says the team had to design feedback and control because picks are sometimes wrong. | Yes, the idea of *explaining* picks and *steering* them. No voice, no mascot, no invented commentary. |
| Apple Music Replay | Story-style reel with animated transitions; art drifts with slow parallax; data as large type. | Slow, purposeful motion and big type, yes. |
| YouTube Music Samples / Apple Autoplay | One-gesture sampling, mix continues itself. | Gesture-first interaction: touch a thing to hear it. |
| Teenage Engineering / Ableton-style instruments | Controls are the decoration: ticks, knobs, one hairline grid, monochrome. | Yes: the dial and the field are drawn as instruments. |
| Linear / Arc motion | Short ease-out transitions, springs that settle without bounce, nothing animates without a reason. | Yes: ease-out 320-600 ms, critically damped glides. |
| Data art (Visual Cinnamon, Joy Division pulsar) | One honest quantity becomes a shape. | Yes: distance in the field is the fit score. |

Honest limit: the searches returned press and community design write-ups, not
design critiques or first-party documents. YouTube Music Samples and Teenage
Engineering returned nothing usable, so those rows are our reading, not their
claim. Flutter guidance found: RepaintBoundary around animating subtrees,
spring or friction simulations for drags, `MediaQuery.disableAnimationsOf` for
reduced motion, dispose controllers.

## What translates, and what does not

Translates: explain *why*, let the listener steer, motion that carries
meaning, instruments drawn in hairlines, haptics on discrete steps.
Does not: voice, mascots, gradients, glow, glass, cards, anything asserting
what the server did not measure.

## Signature ideas (built)

1. **Taste field ("Why these songs").** The picks as dots around the moment.
   Distance from the centre is the server's fit score (nearer = closer); angle
   follows valence; dot size follows danceability. Dots drift in a slow orbit,
   glide to new places with a critically damped spring, and bloom out of the
   centre, staggered 45 ms, when a new mix arrives. Tap a dot to see the song
   and play from it. Reduced motion: same picture, static, no ticker.
2. **Energy dial.** Calm to Lively, a hairline ruler with a knob. Drag and the
   mix is re-ordered around that energy and the field's distances switch to
   "distance from that energy", so the dots visibly reshape as you drag.
   Selection haptic every 10%, slider semantics with increase/decrease, Reset.
   Hidden when the server sent no audio features (no spread, nothing to dial).
   Playing from the page plays the reshaped order.
3. **Rise-in cascade.** First eight rows fade up 14 px, 45 ms apart, ease-out
   320 ms, when a mix is generated; re-ordering by the dial does not replay.
4. **Haptics.** Light selection on dial steps and dot taps, medium impact on
   Play.

## Not built (candidates)

- Listening fingerprint (concentric day rings from play history): needs a
  per-day data source; the current screen only has the one timestamp.
- Mix hand-off animation from the field into Now Playing.

## Rules check

Monochrome white on black; no containers; no glow, gradient text or glass; no
shadows (Windows and TV safe); art colour untouched; everything painted with
`CustomPaint` inside `RepaintBoundary`; the ticker is created per field and
disposed with it, and `TickerMode` pauses it off-screen. Windows: same widgets,
field capped at 480 px and left-aligned, mouse drag on the dial. TV is not a
target of this page.
