---
type: "query"
date: "2026-05-13T05:46:50.182674+00:00"
question: "PlayerProvider ListeningEventCollector data flow"
contributor: "graphify"
source_nodes: ["PlayerProvider", "ListeningEventCollector"]
---

# Q: PlayerProvider ListeningEventCollector data flow

## Answer

The data flow between PlayerProvider and ListeningEventCollector is focused on tracking user playback behavior for analytics and history.

1. **Triggering:** The PlayerProvider (the core state manager for playback) calls the ListeningEventCollector. This happens at key lifecycle events during playback.
2. **Event Tracking:** The ListeningEventCollector exposes methods like onSongStarted, onSongEnded, and onSongRepeated to capture the current playback state.
3. **Data Processing & Storage:** Once an event is captured, the collector uses models like PlayEvent and Song. It then writes these events out in two ways:
   - To the local AppDatabase via Drift (using _upsertSongMetadata and persistWeight).
   - To local CSV logs via _buildCsv and _writeEvent.
4. **Relationship to Scrobbling:** The ListeningEventCollector is structurally separate from but semantically similar to the ListeningLogService, which is responsible for passing playback data along to the ScrobbleService (e.g., for Last.fm or ListenBrainz).

## Source Nodes

- PlayerProvider
- ListeningEventCollector