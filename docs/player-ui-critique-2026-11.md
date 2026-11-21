# Player UI, lyrics and downloader: critique and what changed (Nov 2026)

Measured against `DESIGN.md` / `PRODUCT.md` (Apple Music canon, monochrome white accent, opaque
chrome, no card containers) and the five reference screenshots of another app. Read from the code and
the committed goldens in `test/goldens/player/`; **nothing here was checked on a phone** (no device
was connected: `adb devices` was empty).

## What the references do that NaviVibe already does

Worth saying first, because it changes what is worth building:

| Reference idea | NaviVibe today |
|---|---|
| Floating bar that merges the mini player with the nav | `GlassDock` is one frosted sheet holding the Jam pill, the mini player and the tab bar, with a solid fallback (reduced motion, high contrast, TV, slow GPU via `GlassGovernor`). |
| Mini player: swipe up opens, swipe sideways skips | Already so (`MiniPlayer`): the contents follow the finger and spring back; tap or swipe up opens. |
| Progress hairline on the mini player | Already so (`_MiniProgress`, own `RepaintBoundary`). |
| Quality label between the times | Already so: `Lossless · FLAC · 24-bit/96 kHz` / `MP3 · 320 kbps` in `Scrubber`; it never says "Standard". |
| Lower half takes the cover's colour | Already so: `NowPlayingStyle` / `albumPaletteProvider`. |

So the references are not a gap list. The real gaps are below, ranked.

## Ranked critique

### Now Playing and the mini player

1. **The long title is the weakest thing on screen (fixed).** A long film title ("Aga Naga (From
   "Ponniyin Selvan…") looped in a marquee for as long as the song played. Every frame you glance at
   it is a title cut mid-letter (the golden shows exactly that, as does the reference), and a
   permanent animation keeps the screen redrawing. The mini player just truncated with an ellipsis, so
   its full title was never readable.
   → `FittingTitle`: rests as a clean ellipsis, scrolls across twice after a beat, settles back.
   Used by Now Playing and the mini player. Reduced motion never scrolls.
2. **The bottom controls didn't look like controls (fixed, phone only).** Lyrics, Devices and Queue
   were bare 48 dp glyphs; only the open pane's one had a disc. The reference's four round buttons
   read as buttons. → 56 dp targets with a faint round disc at rest (`GlyphButton.restFill`), still
   opaque-tint, no glass. Windows and TV keep bare glyphs.
3. **Lyrics showed one highlighted line only (fixed, below).** Whole-line highlight can't follow a
   fast line; the reference fills word by word.
4. **No credit/source on lyrics (fixed).** The reference's `lrc.red · SYNC` chip tells you where text
   came from and how it is timed. NaviVibe showed no source at all.
5. **Left alone, on purpose.**
   - Full-bleed art that melts into the page: first left alone (against the square Apple-style cover and
     the "no new surfaces" rule); the owner then chose it from the mock-ups (`docs/design/now-playing-2026-11/`,
     option B) and it is built for the phone layout; see `DESIGN.md`, "Full-bleed cover".
   - A round cover with a progress *ring* in place of the mini player when scrolling: it would break the
     mascot strip that walks along the hairline, and needs device testing for the dock's animation.
   - Close/translate round buttons over the lyrics: NaviVibe's Translate / Pronounce pills are already
     44 dp and in the same place.
   - **Wavy progress in the system media notification: not possible.** That widget is drawn by the OS
     (Android 13+ media-style notification and lock screen), `audio_service` only supplies the title,
     artwork, position and actions. The reference screenshot is the OS's own control.

### Lyrics

1. Position was read only at `positionStream`'s ~200 ms tick and the whole list (every line, a
   `GlobalKey` each) rebuilt on every line change. → each line now watches only "past / sung now /
   upcoming", so two lines rebuild; the word fill is a colour-only repaint of one paragraph inside a
   `RepaintBoundary`, driven by a `Ticker` that does nothing while paused.
2. Plain text from the server's own tags blocked every better source, and a "nobody has it" answer
   was cached forever. → synced online lyrics now beat plain tags; non-synced results expire after
   12 h.
3. The empty state said "your server or LRCLIB". It now names the sources and points to Settings.

### Song downloader ("Search online")

The flow is more complete than most (confirm dialogs, owned hints, "Search online anyway", batches,
a finished banner, a queue with a failed list). Problems found, ranked:

1. **The finish actions were under the results (fixed).** After a download ends, "Play" and "Add to
   Playlist" were rendered after the last result row, so on a phone with eight results they were below
   the fold and the song you just added had no obvious next step. → moved above the results.
2. **No feedback on tap beyond a small spinner (fixed).** The song row's only response to a tap is a
   22 dp spinner at the right edge, under the thumb. → a light haptic on starting a download.
3. **Rows had no action hint for screen readers (fixed).** The label said the status but not what a
   double-tap does (download, play, select, open). → `Semantics.hint`.
4. **Not fixed, worth doing:**
   - On a phone the batch bar ("Select all / Download n songs") sits at the top of a long list: the
     primary action is out of one-handed reach. It should dock at the bottom of the sheet.
   - A single download can't be cancelled from the row (only from the queue sheet).
   - Button labels are Title Case ("Select All", "Download 3 Songs") while the rule file says sentence
     case; the existing tests and Apple's canon use Title Case, so I left it.
   - No "downloads keep going if you close this" line while one is running (the app-wide banner covers
     it afterwards).

## Lyrics sources: request and response shapes

Read read-only. Nothing is reproduced; no credential is stored in the app.

| Source | How it is called | Response | Cost / risk |
|---|---|---|---|
| **lrc.red** | `GET /search.json?q=<title artist>` → `{hits:[{isrc,title,artist,duration,…}], next}`; then `GET /s/{isrc}.json` → `{sync:"word"\|"line"\|"none", files:{ttml,lrc}}`; then `GET /s/{isrc}.ttml` (word/syllable timing) or `.lrc` | TTML or LRC text | Free. Terms: a User-Agent (or `X-Client-ID` in a browser) naming the app with a link and a contact address, and visible credit with a link to lrc.red. Per-IP rate limit; unstable uptime reported in Oct 2026. The API docs page is client-rendered, so this was read from the site's JS bundle. |
| **BetterLyrics** | `GET https://api.betterlyrics.org/getLyrics?s=&a=&al=&d=` (title, artist, album, seconds) | `{ttml, score}`, TTML with per-word `<span begin end>` | Free, but keys are not being issued: a cache miss returns 401, so a song nobody has played in their extension is simply missing. Two rate tiers per IP. Upstream licences unstated. |
| **Paxsenix / Spotify-Lyrics-API** | self-hosted: `GET /api/lyrics?url=<spotify track url>&format=lrc` | `{syncType, lines:[{timeTag, words}]}` (line timing only) | **Terms-of-service risk**: the project's own README says it uses undocumented Spotify endpoints and "may violate Spotify's Terms of Service". It needs the operator's Spotify `sp_dc` cookie on the instance it runs on (never in this app or the shuffle server) and has no search, only a track URL; NaviVibe holds no Spotify track ids, so as built the source answers nothing until something supplies one. It is off by default in Settings and off on the server unless `NAVIVIBE_PAXSENIX_URL` is set. |

Order of use: the file's own synced tags → proxy (lrc.red → BetterLyrics → Spotify wrapper, as
enabled) → LRCLIB → plain text from whichever had it. The web build can't call these directly
(CSP); the app calls `GET /lyrics/fetch` on the shuffle server, which caches one file per song,
only for signed-in users, never publicly (`tool/server/lyrics-v1/`).
