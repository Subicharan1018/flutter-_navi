#!/bin/bash

echo "=== player_provider.dart ==="
graphify query "What does player_provider.dart depend on and what depends on it?" --dfs

echo "=== navi_audio_handler.dart ==="
graphify query "What does navi_audio_handler.dart depend on and what depends on it?" --dfs

echo "=== God Nodes ==="
graphify query "Which files have the most inbound edges (god nodes)?"

echo "=== Fragile Communities ==="
graphify query "Which communities have cohesion below 0.1 (fragile clusters)?"

echo "=== Circular Dependencies ==="
graphify query "Are there any circular dependencies?"

echo "=== Providers ==="
graphify query "Which providers import other providers directly?"
