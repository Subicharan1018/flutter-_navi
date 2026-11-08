# Windows scrolling: findings and rules

Reported: scrolling on Windows is not as smooth as Spotify, with a slight extra
stutter. Found by reading the code and by a build-counting widget test
(`test/widgets/scroll_performance_test.dart`); the app was not profiled live.

## What was wrong

| # | Cause | Effect | Fix |
|---|-------|--------|-----|
| 1 | `SliverLayoutBuilder` around the song table, the `MediaGrid` (Home, Albums, Artists), the Browse grid and Stats' two-column layout. Its builder runs on every constraints change, and a scroll changes them every frame. | Every visible row or card (~50 table rows, ~30 cards with covers) was **rebuilt on every frame of a scroll**: 1,780 row rebuilds in a 40-frame glide, 0 now. | `SliverWidthBuilder` (`lib/widgets/ui/sliver_width_builder.dart`): rebuilds only when the width changes or the parent rebuilds. |
| 2 | The mouse wheel jumps a whole notch in one frame (Flutter's default). | A notch is a visible step; Spotify and browsers glide. | `SmoothWheel` (`lib/core/smooth_wheel.dart`): the wheel eases to an accumulating target over 260 ms (ease-out cubic), one `jumpTo` a frame. Installed in `main()` on desktop, in front of the engine's pointer packets. Text fields, lists at their end and horizontal shelves (without Shift) keep Flutter's own handling. |
| 3 | Decoded-image cache capped at 60 images / 25 MB. | A 1,000-row table shows ~25 covers at once; scrolling back over them evicted and re-decoded covers (the flicker and hitch when art pops in). | Desktop: 400 images / 160 MB. Phones keep 60 / 25. |
| 4 | Song rows built a hidden "More" button (focus node, tooltip, ink) per row (`Visibility(maintainState: true)`). | Each row scrolled in cost a second widget subtree. | Built only on hover or selection. |
| 5 | Rows are built as they enter view. | Row builds land inside the glide's frames. | Desktop `LargeTitlePage` and `ArtworkPage` keep a 900 px cache extent, so rows are built ahead of the glide. |
| 6 | `WindowGround` gradient was a plain `DecoratedBox` the whole window sat inside. | Any repaint in the shell (hover, progress tick) could repaint the gradient too. | The gradient is its own `RepaintBoundary` layer beside the window; it repaints only while the tint eases. |
| 7 | Queue and lyrics panes used `BouncingScrollPhysics` on Windows. | A rubber band where every other list stops. | Clamping on desktop. |

## Checked and fine

* **Player position ticks** do not rebuild pages: position is not in `PlayerState`; `DesktopSeekBar` already sits in a `RepaintBoundary` and rebuilds only itself (every 250 ms).
* **Per-row provider watches** use `select`; only the playing row does the O(n) queue comparison, and only when `PlayerState` changes.
* **Hover** rebuilds only the hovered row (asserted in the test).
* **Cover decoding** is at display size (`memCacheWidth/Height`) and requested in server steps (96 to 1024 px).
* **Shadows, blurs:** none in scrolling lists. `BackdropFilter` is phone dock glass only.

## Left as is (and why)

* `HorizontalShelf` wraps its list in a `ShaderMask` for the edge fades. It re-rasterises while that one shelf scrolls sideways; it does not run during vertical scrolling. Replacing it needs an overlay that matches the window gradient, which is a design change.
* `SliverLayoutBuilder` remains in `library_screen.dart` and `desktop_library_page.dart` (Library, owned by the social session). They have the same per-frame rebuild; swap in `SliverWidthBuilder` there.
* Keyboard PageUp/PageDown/Home/End inside the table use Flutter's own scroll actions and the table's own cursor keys; not changed.

## Rule

Never build a list or grid inside `SliverLayoutBuilder` / `LayoutBuilder` that is a child of a scrolling sliver without caching on width; use `SliverWidthBuilder`. Read theme, `MediaQuery` and art size in the parent's `build`, not through the builder's `context`.
