
## Architecture Action Plan (May 2026)

Based on recent graph analysis, the following structural improvements are prioritized:
- **Priority 1 (Missing Wires):** Document and wire `FluidShaderLoader` and `_FluidPainter` dependencies which were incorrectly marked as isolated nodes. 
- **Priority 2 (Community Cohesion):** Consolidate duplicated test utilities (`makeSong`, `pumpMicrotasks`) found in 5+ test files into a single `test/helpers/test_utils.dart` to clean up the test communities.
- **Priority 3 (God Node Reduction):** Split `replay_screen.dart` and `playlist_details_screen.dart` by extracting their heavy UI components into `lib/screens/replay/widgets/` and `lib/screens/playlist/widgets/`.