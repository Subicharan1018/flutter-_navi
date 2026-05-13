---
name: graph-first-navigation
description: >
  Use this skill before answering ANY question about the NaviVibe codebase
  structure, connections, dependencies, or architecture. Triggers include:
  "what connects", "how does X relate to Y", "where should I put", "what
  would break if", "which file handles", "add a new feature", "refactor X",
  or any question about file relationships. ALWAYS query the graph before
  answering. Never guess file relationships from memory.
---

# Graph-First Navigation Skill

## The Rule
**Never answer a structural question from memory. Always query the graph first.**

NaviVibe has 1237 nodes across 116 communities. No AI model can hold this
in context reliably. The graph already has the answers — use it.

## Query Commands

```bash
# What connects two things?
/graphify query "what connects AudioHandler to OfflineService?"

# Explain a component
/graphify explain "ListeningEventCollector"

# Find path between two components
/graphify path "PlayerProvider" "SubsonicService"

# Impact analysis before a change
/graphify query "what would break if I change settings_provider.dart?"

# Where should new code go?
/graphify query "which community handles offline caching?"
```

## God Nodes — Always Graph-Check Before Touching

| File | Edges | Bridges |
|------|-------|---------|
| `replay_screen.dart` | 52 | many communities |
| `playlist_details_screen.dart` | 52 | many communities |
| `package:flutter_riverpod` | 46 | 43 communities |
| `subsonic_service.dart` | 46 | 11 communities |
| `ListeningStats` | 43 | many communities |
| `ListeningEventCollector` | 41 | 11 communities |
| `settings_screen.dart` | 40 | many communities |
| `PlayerProvider` | 40 | many communities |
| `package:flutter/material.dart` | 38 | 34 communities |
| `mini_player.dart` | 37 | many communities |

## Before ANY Code Change — Answer These First
1. Which community does the target file belong to?
2. Does it connect to a god node?
3. Will this change create a new isolated node?
4. Is the target community fragile (cohesion < 0.1)?

## Fragile Communities — Do Not Expand
| Community | Cohesion | Rule |
|-----------|----------|------|
| Community 1 | 0.05 | Extract to new feature slice |
| Community 4 | 0.06 | Extract to new feature slice |
| Community 0 | 0.07 | Still fragile despite improvement |
| Community 2 | 0.07 | Do not add shuffle logic here |
| Community 3 | 0.07 | Do not add Drift tables here |

## After Adding New Files
```bash
/graphify . --update
```
Then verify the new file is NOT in the isolated nodes list.
493 isolated nodes remain — do not add more.

## Surprising Connections (non-obvious — do not break)
- `ListeningEventCollector` → `listening_log_service.dart` (semantically similar — keep in sync)
- `PaletteCache` → `Multi-Engine Theme System` → `FluidBackground Shader` (theme chain)
- `PlayerProvider` → `ListeningEventCollector` (play events feed telemetry directly)
- `AudioHandler` → `Gapless Incremental Reordering` (queue mutation pattern)
- `ListeningEventCollector` defines `pumpMicrotasks`, `makeSong`, `generateUuid` (test utils in wrong place — do not move without updating all test communities)
