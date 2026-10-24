---
name: NaviVibe
description: Apple Music (iOS 26), played straight, on Android. A Navidrome client on an AMOLED black ground, monochrome with a white accent, where only the artwork brings colour.
colors:
  ground: "#000000"
  grouped-surface: "#111111"
  elevated-surface: "#1C1C1E"
  overlay-fill: "#2C2C2E"
  tertiary-fill: "#1C1C1E"
  separator: "#262628"
  accent: "#FFFFFF"
  accent-dim: "#636366"
  on-accent: "#000000"
  icon-tile: "#2C2C2E"
  label: "#FFFFFF"
  secondary-label: "#9E9EA4"
  tertiary-label: "#86868C"
  system-yellow: "#FFD60A"
  system-orange: "#FF9F0A"
  system-red: "#FF453A"
  system-gray: "#8E8E93"
  system-gray-2: "#636366"
  fallback-base: "#1C1C1E"
  fallback-glow: "#2C2C2E"
typography:
  large-title:
    fontFamily: "InterDisplay, Inter, sans-serif"
    fontSize: "32px"
    fontWeight: 700
    lineHeight: 1.18
    letterSpacing: "-0.69px"
  title1:
    fontFamily: "InterDisplay, Inter, sans-serif"
    fontSize: "26px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.53px"
  title2:
    fontFamily: "InterDisplay, Inter, sans-serif"
    fontSize: "21px"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.37px"
  title3:
    fontFamily: "Inter, sans-serif"
    fontSize: "19px"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "-0.3px"
  headline:
    fontFamily: "Inter, sans-serif"
    fontSize: "16px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.18px"
  body:
    fontFamily: "Inter, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "-0.18px"
  callout:
    fontFamily: "Inter, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "-0.13px"
  subheadline:
    fontFamily: "Inter, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "-0.09px"
  footnote:
    fontFamily: "Inter, sans-serif"
    fontSize: "12.5px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "-0.02px"
  caption1:
    fontFamily: "Inter, sans-serif"
    fontSize: "11.5px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "0.03px"
  caption2:
    fontFamily: "Inter, sans-serif"
    fontSize: "10.5px"
    fontWeight: 500
    lineHeight: 1.25
    letterSpacing: "0.08px"
  stat-figure:
    fontFamily: "InterDisplay, Inter, sans-serif"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: 1.05
    letterSpacing: "-0.6px"
    fontFeature: "tnum"
rounded:
  thumb: "5px"
  cover: "8px"
  hero: "12px"
  control: "12px"
  group: "12px"
  dialog: "14px"
  sheet: "16px"
  capsule: "999px"
spacing:
  xxs: "2px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
  xxxl: "32px"
  huge: "48px"
  gutter: "16px"
  player-clearance: "152px"
components:
  button-play-capsule:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    padding: "0 24px"
    height: "50px"
  button-circle:
    backgroundColor: "{colors.tertiary-fill}"
    textColor: "{colors.label}"
    rounded: "{rounded.capsule}"
    size: "44px"
  button-tinted:
    backgroundColor: "{colors.tertiary-fill}"
    textColor: "{colors.accent}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    padding: "0 20px"
    height: "44px"
  button-tinted-filled:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    padding: "0 20px"
    height: "50px"
  button-queue-mode:
    rounded: "{rounded.dialog}"
    height: "44px"
  button-filled:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    typography: "{typography.headline}"
    rounded: "{rounded.control}"
    padding: "0 24px"
    height: "50px"
  search-field:
    backgroundColor: "{colors.tertiary-fill}"
    textColor: "{colors.label}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "9px 6px"
  segmented-control:
    backgroundColor: "{colors.tertiary-fill}"
    textColor: "{colors.label}"
    typography: "{typography.footnote}"
    rounded: "{rounded.control}"
    padding: "2px"
  filter-pill:
    backgroundColor: "{colors.tertiary-fill}"
    textColor: "{colors.label}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.capsule}"
    padding: "0 16px"
    height: "34px"
  filter-pill-selected:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
  grouped-section:
    backgroundColor: "{colors.grouped-surface}"
    textColor: "{colors.label}"
    typography: "{typography.body}"
    rounded: "{rounded.group}"
    padding: "10px 16px"
  collection-row:
    backgroundColor: "{colors.ground}"
    textColor: "{colors.label}"
    typography: "{typography.body}"
    padding: "8px 16px"
    height: "52px"
  media-card:
    textColor: "{colors.label}"
    typography: "{typography.footnote}"
    rounded: "{rounded.cover}"
    width: "150px"
  tab-bar:
    backgroundColor: "{colors.grouped-surface}"
    textColor: "{colors.label}"
    typography: "{typography.caption2}"
    rounded: "{rounded.capsule}"
    padding: "4px"
    height: "62px"
  mini-player:
    textColor: "{colors.label}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    height: "58px"
  action-group:
    backgroundColor: "{colors.grouped-surface}"
    textColor: "{colors.label}"
    typography: "{typography.body}"
    rounded: "{rounded.group}"
  bottom-sheet:
    backgroundColor: "{colors.grouped-surface}"
    textColor: "{colors.label}"
    rounded: "{rounded.sheet}"
---

# Design System: NaviVibe

## Overview

**Creative North Star: "Apple Music, played straight"**

NaviVibe is the iOS 26 Apple Music app rebuilt at full fidelity for Android phones, with a faithful wide layout on Linux and Windows desktops. It has two translations and no others: a monochrome white accent where Apple uses red, and a pure AMOLED black ground (with no tint) where Apple uses its neutral system greys. Everything else follows Apple's conventions. That means large titles that collapse into a compact bar, inset grouped lists, a floating capsule tab bar with Search split into its own circle, a capsule mini player, iOS page transitions with edge-swipe back, rubber-band scrolling, and presses that respond on touch-down by scaling instead of rippling.

The chrome is exact, quiet and opaque. Artwork is the main decoration and the only source of chrome colour. The default chrome stays on the same black ramp whatever is playing. Icons are monochrome and tinted by their role (Ionicons in the player and Settings, CupertinoIcons elsewhere); the one place fixed colour is drawn by hand is the illustrated set: the phone tab icons and the empty-state illustrations. Album colour appears in three places only: the living artwork field behind Now Playing, the mini player (filled with the playing cover's ground), and collection pages (album, playlist, artist), whose ground is sampled from the cover with the artwork dissolving into it. Every sampled colour passes a hue guard, so purple and pink never reach the chrome.

The density is Apple's. The page gutter is 16, rows are at least 48 to 52 tall with hairline separators inset past the art, and sections are separated by space rather than boxes. Stats reads like Apple Fitness or Health: big figures and charts set straight on the page, with no cards.

**Key Characteristics:**
- There is one theme. The chrome uses a single AMOLED black ramp and is monochrome: white is the only accent.
- Every role is an opaque colour. The only gradient seam is artwork dissolving into its own page colour.
- Collection pages and the mini player take a hue-guarded ground from the cover. On those pages foreground is white only.
- The type is Inter and Inter Display on Apple's text-style ladder, with size-specific (dynamic-metrics) tracking.
- Depth comes from tonal steps of the ground. Shadows are kept for artwork lifting off a page and for floating discs over artwork.
- Phone Now Playing has three transport controls. Shuffle and repeat live in the queue.
- The artwork field's light follows the music, and covers move on one deck whether you swipe or skip.

## Colors

The palette is an AMOLED black ramp with a white accent: monochrome. Colour beyond that comes only from the cover that is playing, plus red for destructive and failure states.

### Primary
- **Accent** (#FFFFFF): the single accent, white. Used for the Play capsule fill, the selected tab label and Search glyph, active filter pills, switch tracks, text cursor and selection, Library destination glyphs, the Stats hero figure, the Last 2 Weeks readout, and today's bar. It reaches 21:1 on the ground. Defined once as the `accent` token (`AppThemeTokens.brandAccent`); nothing hard-codes it.
- **Accent, Dim** (#636366, systemGray2): the secondary data tone (past days in the Last 2 Weeks chart, the lower clock bars, the second swipe action). It is never used for text.
- **On Accent** (#000000): glyphs and labels on a white fill. A switch that is on shows a black thumb on the white track.

### Neutral
- **AMOLED Black Ground** (#000000): systemBackground, pure black with no tint. Used for every default page, the collapsed nav bar, pinned headers, and the dock band.
- **Grouped Surface** (#111111): secondarySystemBackground. Used for inset grouped sections, action groups, bottom sheets, and the tab-bar surface on the default ground.
- **Elevated Surface** (#1C1C1E): tertiarySystemBackground. Used for dialogs, popup menus, snack bars, and the discs that float over artwork.
- **Overlay Fill** (#2C2C2E): pressed-row fill, the segmented-control thumb, the idle switch track, and queue pills inside chrome.
- **Tertiary Fill** (#1C1C1E): tertiarySystemFill. Used for the search field, round secondary buttons, tinted capsules, idle filter pills, and slider and progress tracks.
- **Separator** (#262628): 0.5px hairlines.
- **Label** (#FFFFFF): primary text.
- **Secondary Label** (#9E9EA4): subtitles, footnotes, row values. It holds 7.9:1 on the ground, 6.4:1 or better up to Elevated Surface, and 5.2:1 on Overlay Fill.
- **Tertiary Label** (#86868C): chevrons, placeholders, disabled glyphs. It holds 4.5:1 or better up to Elevated Surface (4.7:1), but not on Overlay Fill (3.8:1).

### System Colours
- **System Yellow** (#FFD60A): ratings and stars.
- **System Orange** (#FF9F0A): warnings (the offline banner glyph).
- **System Red** (#FF453A): destructive actions and errors.
- **Icon Tile** (#2C2C2E): the one neutral square behind every Settings-style row glyph (white glyph). Rows carry no per-row colour.
- **System Gray / Gray 2** (#8E8E93 / #636366): neutral marks only.

### Album-Derived Roles
Each cover is reduced off the main isolate to four roles: deep, base, vibrant, and glow. When nothing is playing they fall back to the app's own ramp: #000000 / #1C1C1E / #FFFFFF / #2C2C2E. `AlbumPalette.ground` is the page colour for collection pages and the mini player. It is the base hue with saturation × 0.8 (capped at 0.6) and lightness clamped to 13–19%, so white text always reads. `AppThemeTokens.tinted(ground)` then resolves every role as an opaque lerp toward white:
- Surface is ground + 7%, elevated + 12%, overlay + 18%, fill + 12%, separator + 14%.
- The accent becomes white with black on it. Secondary text is ground + 68%, which measured 6.5–7.6:1 on sample grounds. Tertiary text and the dim accent are ground + 55%.

### Named Rules
**The Opaque Chrome Rule.** Every chrome role is a solid colour. No blur, no translucent bars, no glass. The only gradient allowed is artwork dissolving into its own page colour: the collection-page seam, the Top Picks card seam, and the edge fade on scrolling panes.

**The Never Purple Rule.** Any colour derived from a cover goes through the hue guard. Hues from 250° to 340° are moved to 215° (blue) or 8° (red), and saturation within 20° of either edge of that band is capped at 0.3. The cover image itself is never altered. No purple or pink chrome is ever authored by hand either.

**The One Accent Rule.** White is the only accent, in default chrome and on artwork-coloured pages and Now Playing alike: the app is monochrome. Red is kept only for destructive actions and failures; nothing else gets a hue. Colour comes from theme tokens, never from values written into a screen. Monochrome glyphs take their colour from their role, never from the asset.

## Typography

**Display Font:** Inter Display (bundled), used at 20pt and above when weight is 500 or heavier.
**Body Font:** Inter (bundled). No runtime font fetching.

**Character:** Inter is the closest licensed match to SF Pro. Each role is set one notch below Apple's point size, because Inter draws about 6% larger and heavier than SF Pro. The switch to Inter Display at 20pt mirrors SF's switch from its Text cut to its Display cut.

### Hierarchy
- **Large Title** (700, 32, 1.18): the title of each top-level page. It collapses into the compact nav bar.
- **Title 1** (700, 26, 1.2): collection-page titles and large headings.
- **Title 2** (600, 21, 1.25): section headers (with an inline chevron when the section leads somewhere) and Stats section titles.
- **Title 3** (600, 19, 1.25): feature-card titles. Library destination rows use it at 400.
- **Headline** (600, 16, 1.3): button labels, nav-bar titles, mini-player title.
- **Body** (400, 16, 1.3): row titles, fields, settings values.
- **Callout** (400, 15, 1.3) and **Subheadline** (400, 14, 1.3, secondary label): supporting lines and filter-pill labels (at 600).
- **Footnote** (400, 12.5, 1.3, secondary label): subtitles, card subtitles, grouped headers and footers, collection summaries.
- **Caption 1 / Caption 2** (400 at 11.5 / 500 at 10.5): the offline banner and tab labels.
- **Stat Figure** (700, display cut, tabular, 1.05, −2% tracking): the one numeric voice on Stats. It is 30 for section readouts and 64 for the time-listened hero.
- **Now Playing title / artist** (Inter Display 22/700 white; 19/500 white at 68%): on the artwork field. Long titles marquee slowly instead of truncating. The title cross-fades (220ms) when the song changes.

### Named Rules
**The Dynamic Tracking Rule.** Letter-spacing is never hand-set. It always comes from `trackingFor(size) = size × (−0.0223 + 0.185·e^(−0.1745·size))`: small text opens slightly and display text tightens.

**The Tabular Numbers Rule.** Times, counts and figures use tabular numerals so values don't jitter as they change.

## Layout

The layout is phone first, and wide layouts restructure rather than stretch.
- **Phone:** the page gutter is 16. Shelves scroll horizontally with 150 covers and 12 gaps. Grids are 2 columns (3 from 600 wide, 5 from 900) with 16 / 20 spacing. Section headers sit 24 above and 12 below their content. Grouped sections are spaced 24 apart. Stats sections are spaced 40 apart, by space alone, and fall into two columns from 900 wide.
- **Scrolling:** every scrolling page ends with 152 of clearance (plus the safe area) so the last row clears the dock.
- **Dock:** the bottom of the phone is one solid band in the visible page's colour, published by `DockGroundScope`. The mini player and the tab bar float on that band, so nothing scrolls into view between or beside them.
- **Collection pages:** on phone, the artwork runs edge to edge as a square. Title, artist and transport sit over the seam. Pulling down stretches the art, and scrolling drifts it at half speed. On wide windows, a 260 cover sits beside the title.
- **Now Playing (phone):** a grabber sits at the top and the cover takes the space above the title. The cover deck follows the finger 1:1 with neighbouring covers 28 apart. The title sits just above the scrubber. Below that come rewind 40 / play-pause 58 / forward 40, then the volume bar, then Lyrics · Devices · Queue. When Lyrics or Queue opens, the cover flies into a 60 header thumbnail and the pane rises into the space it left.
- **Desktop:** a 248 sidebar, the content pane, an optional 320 Now Playing side panel, and an 84 player bar along the bottom. Desktop Now Playing places shuffle and repeat either side of the transport.

## Elevation & Depth

Depth is tonal. Raised surfaces are lighter, opaque steps of whichever ground they sit on: the default ramp in chrome, or lerps toward white on tinted pages. On the tab bar and mini player, a 0.5px hairline lifted from the ground (+16% and +12%) defines the edge. Shadows are used only where artwork or a disc lifts off moving content.

### Shadow Vocabulary
- **Cover lift** (`blur = 12% of cover size, y = 5% of size, colour = album deep mixed 40% toward black at 55% alpha`): the Now Playing cover and its carousel neighbours. The shadow is tinted by the album.
- **Hero art lift** (`0 14px 36px rgba(0,0,0,0.45)`): the wide-layout collection cover.
- **Bar disc** (`0 2px 8px rgba(0,0,0,0.20)`): the 36 discs that float over artwork in the collection top bar.
- **Dragged item** (`0 10px 24px rgba(0,0,0,0.35)`): a row being reordered in the playlist editor.

### Named Rules
**The Tonal Lift Rule.** Use the next opaque step of the ground before reaching for a shadow. Panels, cards and sections never get shadows.

## Shapes

Corners follow the iOS role of each surface:
- 5: thumbnails in rows.
- 8: covers in grids and shelves.
- 12: hero art, controls, grouped sections, action groups, and the search field.
- 14: dialogs and the queue mode buttons.
- 16: sheet tops.
- Capsule: Play, tinted buttons, filter pills, the tab bar, its selection pill, and the mini player.
- Circle: secondary actions (Shuffle, Download, More), the Search tab, and artist art.
- 7: Settings icon squares.
- 2–3: chart bars and year-grid cells; 5: the Last 2 Weeks bars.

On Now Playing the cover radius lerps from 12 to 7 as it becomes the header thumbnail. Borders are 0.5px hairlines only.

## Components

### Buttons
- **Play capsule:** 50 tall, at least 148 wide, white fill with black glyph and label (headline), on every page. Press scale is 0.95 with a medium haptic. Disabled, it shows the tertiary fill with the tertiary label.
- **Circle button:** a 44 disc on the tertiary fill with a 19 glyph in the label colour, scale 0.9 on press. It sits either side of Play (Shuffle on the left, Download or More on the right).
- **Tinted capsule:** 44 tall, tertiary fill, white glyph and headline label (red when destructive). It is for single secondary actions such as Try Again and Add Songs.
- **Paired capsules:** when two actions share a row they split it equally with a 12 gap and rise to 50 tall. The primary is the filled tinted capsule (white fill, black label); the other stays tinted. Smart Shuffle pairs Play (filled) with Reshuffle.
- **Filled / Outlined (Material):** 50 tall, radius 12. Filled is white with a black label. Outlined is the tertiary fill with a white label and no border.
- **Press behaviour:** everything scales on pointer-down (90ms) and springs back with easeOutBack (260ms). There are no ink ripples. Rows instead dim to the overlay fill while held.

### Chips
- **Filter pills:** a horizontal row 34 tall on the tertiary fill with a subheadline 600 label. When selected the fill is white and the label is black. A selection haptic fires on change.

### Cards / Containers
- **Media card:** a square cover (radius 8) with a one-line footnote title (label, 500) and a subtitle (secondary). There is no box around it.
- **Top Picks feature card:** a tall card (radius 12). The cover or mosaic fills the top, and a short seam dissolves it into a solid panel of the cover's ground. The title (Title 3, white) and subtitle sit on that panel.
- **Grouped section:** inset 16, radius 12, on the grouped surface. Rows are at least 48 tall. Separators are inset past the 30 icon square. Headers and footers are footnote.
- **Stats:** no containers. `StatSection` is a Title 2, an optional large readout, then the chart or list. The page opens on the summary hero (the time-listened figure and its supporting figures, with no chart inside it), followed by Last 2 Weeks, the listening clock, the trend, top artists, top songs, genre mix and the year grid.
- **Last 2 Weeks:** fourteen tall bars (168 area, radius 5) sized by plays, each with its count above. The readout is the fortnight's total in white; tapping a day lights that bar and reads that day instead (selection haptic). Today is white, past days the dim accent grey, and silent days a stub in the tertiary fill.

### Inputs / Fields
- **Search field:** the Cupertino search field on the tertiary fill, radius 12, body text, secondary-label placeholder and glyphs.
- **Grouped text row:** a 104 label column and a borderless field, with a white cursor. Password rows have a show/hide eye.
- **Segmented control:** the tertiary-fill track with an overlay-fill thumb. Footnote labels, 600 when selected.

### Navigation
- **Large-title page:** a Cupertino sliver nav bar on the opaque ground. There is no hairline until content scrolls under it, and no transitions between tab routes.
- **Tab bar:** a 62 floating capsule (ground + 9%, hairline at ground + 16%) holding Home, Shuffle, Stats and Library. The selected tab sits on a lighter pill (ground + 18%) that slides with easeOutBack, with a white label. Each tab's glyph is a 34 illustration that plays once per tap and rests on its still frame. Search is a separate 62 circle at the trailing end with a 26 Ionicons glyph, white when selected.
- **Collection top bar:** 36 discs inside 44 targets float over the art. Past the art, the bar fills with the ground and shows the title.

### Icons
- **Ionicons (v7, MIT):** the player and Settings draw from one set of white 192px PNGs (`assets/ionicons/`), tinted at draw time through `Ion` and `IonIcon` so one asset serves every colour and size. Transport and the star are filled; everything else is the outline cut. Settings icon squares (30, radius 7) carry a white Ionicons glyph on a system colour.
- **CupertinoIcons:** everywhere else (Library, collection pages, rows, menus).
- **Illustrations:** the phone tab bar uses `OneShotIcon`, a still PNG paired with a one-shot animated WebP whose last frame matches the first. A tap plays it once from frame zero, then the still returns; under reduced motion it never plays. `MessageState` can show a 96 still illustration above its message.

### Mini Player
A 58 capsule filled with the playing cover's guarded ground, with a hairline at ground + 12%. It shows the cover, the title, and the artist (ground + 72%), plus a 48 play/pause and a 44 forward. A 2px progress hairline runs under the title (track at + 18%, fill at + 90%). Swipe sideways to skip; tap or swipe up to open Now Playing. The fill animates over 600ms easeOutCubic between songs.

### Now Playing
- **Artwork field:** a GPU shader that flows the cover's own pixels at 1/8 resolution. It drifts only while playing, is capped at 30fps, cross-fades between songs, and stops under reduced motion. Until the shader is ready it shows a static field from the palette.
- **Field light:** the field's light follows the music. While playing it is more saturated and opens up behind the cover only, fading out before the title so text contrast never drops; paused, the whole field dims. It lights over 620ms (easeOutCubic) and dims over 420ms; under reduced motion it changes instantly. The light follows play/pause even when Living Artwork drift is off.
- **Cover deck:** the cover sits on a deck with its neighbours 28 apart, which shrink slightly as they leave the centre. Swipe to skip; dragging past a missing neighbour meets asymptotic rubber-band resistance (never more than 35% of a stride). Skips made elsewhere (the buttons, the notification, a song ending) glide the covers along the same deck instead of cross-fading; a jump to an unrelated song, an open pane, or reduced motion keeps the cross-fade.
- **Cover:** springs to full size when playing and recedes to 0.84 when paused.
- **Controls:** all foreground is white with vibrancy (white at 70% / 50%, idle pills at 15%, active pills solid white with near-black). The scrubber has a white fill on a white-25% track, with elapsed time, an honest format label, and remaining time. Transport is three bare Ionicons glyphs with no circles. Play and pause cross-fade with a slight scale (200ms); a glyph that changes state, such as the star filling, pops in (240ms easeOutBack).
- **Queue pane:** history above and Playing Next below, under four equal icon-only mode buttons (44 tall, radius 14, 20 glyph, 8 apart): Shuffle, Repeat (a small "1" badge for repeat-one), Autoplay and Smart Reshuffle. Smart Reshuffle is an action, never shown as on, with a spinner while it works. The queue and the lyrics both use the edge fade (5% top, 10% bottom).

### Action Sheets
An artwork header (56 cover) followed by action groups (grouped surface, radius 12, hairlines). Each row has its label on the left and its glyph on the right, as iOS context menus lay them out. Destructive confirmation uses iOS styling.

## Do's and Don'ts

### Do:
- **Do** read every colour, size and radius through `ThemeTokens.of(context)`, `Space`, `Radii` and `Motion`.
- **Do** derive collection-page and mini-player colour from `AlbumPalette.ground` and theme the page with `AppThemeTokens.tinted`, so shared widgets turn white-on-colour without special cases.
- **Do** publish a page's ground with `DockGroundScope` so the dock band matches it.
- **Do** keep text at 4.5:1 or better against its actual ground. Use Secondary Label for any text that must read on tinted pages.
- **Do** give every control a touch target of at least 44pt and a semantic label.
- **Do** draw player and Settings glyphs with `IonIcon`, tinted by role; use CupertinoIcons elsewhere.
- **Do** keep phone Now Playing to three transport controls (rewind, play/pause, forward), with shuffle and repeat in the queue.
- **Do** honour reduced motion for field drift, the field light (instant), the marquee, count-up figures, the cover scale, the deck glide and the tab illustrations.

### Don't:
- **Don't** add blur, glass, translucent bars or scrims over chrome. Chrome is opaque.
- **Don't** paint chrome purple or pink, by hand or from a sampled colour that skipped the hue guard.
- **Don't** add eyebrow kickers, numbered sections, glows or gradient text.
- **Don't** put Stats sections in cards. Type, space and the charts carry the structure.
- **Don't** add a second accent or a theme picker. There is one living theme.
- **Don't** use Material ripples, bottom navigation bars or chip-and-card Android scaffolding.
- **Don't** show a format badge the file doesn't earn: "Lossless" appears only for lossless suffixes.
