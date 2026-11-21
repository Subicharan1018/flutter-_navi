# Now Playing mock-ups (21 Nov 2026)

Visual mock-ups made for approval before any code. They are static 390 x 844 phone boards with
sample data and placeholder text (no real lyrics). The live canvas (private to the owner):
https://claude.ai/artifact/AaswN3jzDf3JvakAveC1bM

| File | What it shows | Status |
|---|---|---|
| `A-today-refined.dc.html` | Today's layout, lightly refined (square cover on a tint) | not chosen |
| `B-full-bleed.dc.html` | **Cover fills the top ~64 % and melts into the opaque tint; title sits on the fade** | **chosen: build this** |
| `C-sheet-over-art.dc.html` | Art on top, solid tinted sheet overlapping it | not chosen |
| `lyrics.dc.html` | Lyrics screen: close and translate buttons, cover thumb, source chip | not decided |
| `dock.dc.html` | Mini player and nav: today / floating Home circle + pill / four tabs + cover ring | not decided |

The `.dc.html` files use the canvas runtime (`support.js`), so they do not open on their own in a
browser: read them as markup and numbers. Colours and type follow `DESIGN.md`.

## B in numbers (844 dp tall phone; scale with the screen, don't hard-code)

- Cover: full width, about 64 % of the height (540 dp), `BoxFit.cover`, opaque. Its lower ~44 % fades
  to the page tint (gradient overlay from transparent to the tint colour, no blur).
- Top scrim: 120 dp, black 45 % to transparent, so the grabber, status bar and any Flow chips stay legible.
- Tint: the cover's tint colour, running from a lighter top to near-black at the bottom (mock: `#1b1347`
  to `#0e0a26` to `#07070c`).
- Title block on the fade: title 26/700, artist 16, star and more at 44 dp, a soft text shadow.
- Then the scrubber with the quality label centred, transport (play 72 dp white disc), volume row and
  three round 56 dp buttons with a faint disc (lyrics, devices, queue). Same controls as today.
