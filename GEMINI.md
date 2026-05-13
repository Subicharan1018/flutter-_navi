## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- ALWAYS read graphify-out/GRAPH_REPORT.md before reading any source files, running grep/glob searches, or answering codebase questions. The graph is your primary map of the codebase.
- IF graphify-out/wiki/index.md EXISTS, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Architecture Action Plan (May 2026)

Based on recent graph analysis, the following structural improvements are prioritized:
- **Priority 1 (Missing Wires):** Document and wire `FluidShaderLoader` and `_FluidPainter` dependencies which were incorrectly marked as isolated nodes. 
- **Priority 2 (Community Cohesion):** Consolidate duplicated test utilities (`makeSong`, `pumpMicrotasks`) found in 5+ test files into a single `test/helpers/test_utils.dart` to clean up the test communities.
- **Priority 3 (God Node Reduction):** Split `replay_screen.dart` and `playlist_details_screen.dart` by extracting their heavy UI components into `lib/screens/replay/widgets/` and `lib/screens/playlist/widgets/`.