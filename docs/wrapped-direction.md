# NaviVibe Wrapped

One unbroken shot. About 1,500 points of light (900 on a TV or low-memory phone) are the whole film: they are never cut, only
re-formed, and every scene is made of the last one. White on black; the only colour is read from the covers' own pixels.

## The film (`lib/features/wrapped/film/`)
`WrappedFilm.paint(canvas, size, scene, seconds)` is a pure function: the same moment always paints the same frame. So what plays
is exactly what is saved or filmed. One ticker, one `drawRawAtlas` for the swarm, no blur, no per-particle layers.

| Scene | What happens | Touch |
|---|---|---|
| intro | a point of light bursts; the sparks find the year | stir |
| minutes | an hourglass swings over and the year drains while the minutes race | blast |
| guess | three covers hidden in coarse light; the wrong ones turn to ash | tap your guess |
| number-one | the cover builds from its pixels, rounds into a record, spins inside its sound | blast |
| top5 | five to one: each cover shatters and becomes the next | tap to smash on |
| artists | your number one is the sun, the rest are worlds | throw them |
| genres | a spiral galaxy, an arm per genre, stars by share | spin |
| clock | a day as 24 rays and a sweeping hand | drag through the day |
| streak | the year as a spiral of days; a comet sets your streak alight | stir |
| discovery | hyperspace | steer |
| personality | a moon, compass, heart, endless loop or wave, turning in space | turn it |
| journey | a low flight over twelve months of mountains | drag across the year |
| best-day | the sea rises past a usual day and keeps rising | tip it |
| finale | it all falls into a poster | tilt it |

Tap an edge to move, the middle to blast, hold to pause, flick up from the bottom (or Why?) for how a number was worked out. Keys:
arrows, space, Esc. Reduced motion shows each scene's still and runs nothing. A screen reader hears each scene's `speech`.

## Sharing
This scene or the whole film (under 60 s), moving or still, with your name off until you turn it on. Android films it on the phone's
own H.264 encoder (`WrappedChannel.kt`: MediaCodec and MediaMuxer, 720x1280, 24 fps, silent), then sends it straight to Instagram,
WhatsApp or Snapchat, the share sheet, or the gallery (Android 10+). Stills are 1080x1920; the poster also 1080x1080. Windows and
web share stills. Instagram's own "add to story" intent is not used because it needs a registered Facebook app id; Instagram's share
screen offers Story instead.

## Data (no new server package)
`GET /replay?year=` and `GET /replay/<year>/<month>` for months with plays, two requests at a time. Streak, biggest day and
personality are worked out in the app. Kept per server, user and year; a copy made before the year ended is only used offline.
A past year kept after it ended opens without the server. New-to-you songs and moods are not in those endpoints, so neither is claimed.
