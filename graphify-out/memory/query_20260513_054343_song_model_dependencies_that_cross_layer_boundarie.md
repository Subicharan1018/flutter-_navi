---
type: "query"
date: "2026-05-13T05:43:43.571200+00:00"
question: "Song model dependencies that cross layer boundaries"
contributor: "graphify"
source_nodes: ["Song", "PlayerNotifier", "SubsonicService", "AppDatabase", "HiveBoxes"]
---

# Q: Song model dependencies that cross layer boundaries

## Answer

Based on the knowledge graph, the Song model crosses several architectural layer boundaries.

1.  **State Management Layer:** The Song entity is referenced directly by PlayerNotifier and PlayerState.
2.  **Service/Network Layer:** Song is referenced by SubsonicService for deserialization and API communication.
3.  **Local Storage Layer:** SubsonicService and PlayerNotifier subsequently bridge the Song entity into the local storage layer by interacting with HiveBoxes and conceptually linking to AppDatabase.
4.  **Testing Layer:** The Song model heavily crosses into the testing layer, being imported and utilized in test utilities like makeSong within audio_handler_shuffle_test.dart, bridging application logic with test mock objects.

The central nature of Song means it tightly couples the network fetching logic (SubsonicService), the application state (PlayerNotifier), and local persistence (HiveBoxes/AppDatabase).

## Source Nodes

- Song
- PlayerNotifier
- SubsonicService
- AppDatabase
- HiveBoxes