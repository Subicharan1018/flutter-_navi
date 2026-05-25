import subprocess
import os
import sys

queries = [
    'graphify query "What is the complete data flow from when a user presses play to when audio starts?"',
    'graphify query "What connects player_provider.dart to the shuffle server API?"',
    'graphify query "List all files that import or depend on models/song.dart"',
    'graphify query "What is the full dependency chain of the AI shuffle feature from UI to network call?"',
    'graphify query "Which files depend on settings_provider.dart and why?"',
    'graphify query "What connects core/theme.dart to the rest of the app? Why does it have 35+ edges?"',
    'graphify query "Find all Timer usages in the codebase — where are they created and where are they disposed?"',
    'graphify query "Find all places where play ratio or play duration is calculated or stored"',
    'graphify query "Where is applyShuffleAlgorithm called and what state does it read before and after each await?"',
    'graphify query "Find all catch blocks that swallow exceptions silently (empty catch or just print)"',
    'graphify query "Find all Navigator.push or navigation calls — are they guarded with mounted checks?"',
    'graphify query "Find all places where File.existsSync or any synchronous file I/O is called on the main thread"',
    'graphify query "Where is _playedDuration set, incremented, and reset? Is it possible to drift?"',
    'graphify query "Find all StreamSubscription declarations — are they all cancelled in dispose()?"',
    'graphify query "How does the shuffle scoring engine receive and process play history data?"',
    'graphify query "What is the complete flow of a play event from user action to being stored in the database?"',
    'graphify query "Where are context buckets (morning/evening etc) calculated and stored?"',
    'graphify query "How does composer loyalty score get calculated — trace the full data path"',
    'graphify query "What calls ShuffleApiService and what data does it send to the server?"',
    'graphify query "Where is the play ratio capped at 1.0? Is it capped before or after storage?"',
    'graphify query "What tables exist in the database and what does each store?"',
    'graphify query "What connects analytics_tables.dart to the play event collection flow?"',
    'graphify query "How does ListeningEventCollector decide when to flush events to the database?"',
    'graphify query "Where is the Apple Music migration data imported and how does it feed into the existing tables?"',
    'graphify query "Find all places where sensitive data (API keys, passwords, tokens) might be logged or stored"',
    'graphify query "What does Suma Secrets Logic contain? Is any secret hardcoded?"',
    'graphify query "Find all HTTP calls — are any made over plain HTTP instead of HTTPS?"',
    'graphify query "Which functions or methods are longer than 100 lines?"',
    'graphify query "Find all business logic that lives inside build() methods"',
    'graphify query "What is the full list of known bugs from project_audit.md and which files contain each bug?"',
    'graphify query "Which communities have cohesion below 0.10? What does that mean for those modules?"',
    'graphify query "What does FluidBackground depend on and what depends on it?"',
    'graphify query "How does PaletteCache work — what triggers it, what does it cache, and is there a size limit?"',
    'graphify query "What is the complete GaplessIncrementalReordering logic and where is it used?"',
    'graphify query "How does the Replay feature work end to end?"',
    'graphify query "What shuffle algorithms exist and how are they selected?"',
    'graphify path "ListeningEventCollector" "AppDatabase"',
    'graphify path "ShuffleApiService" "PlayerProvider"',
    'graphify path "Song" "ShuffleRepository"',
    'graphify path "RecommendationService" "PlayEvents"',
    'graphify path "AudioHandler" "ListeningLogService"',
    'graphify explain "RecommendationService"',
    'graphify explain "ListeningEventCollector"',
    'graphify explain "GaplessIncrementalReordering"',
    'graphify explain "ShuffleAlgorithms"',
    'graphify explain "PaletteCache"',
]

with open('/home/subi/.gemini/antigravity-cli/brain/452af757-523a-4788-b53e-39efa32ef7f5/graphify_queries_output.md', 'w') as f:
    f.write("# Graphify Queries Output\n\n")
    for q in queries:
        f.write(f"## Command: `{q}`\n\n```\n")
        print(f"Running: {q}")
        try:
            res = subprocess.run(q, shell=True, check=True, capture_output=True, text=True)
            f.write(res.stdout)
            if res.stderr:
                f.write("\nSTDERR:\n" + res.stderr)
        except subprocess.CalledProcessError as e:
            f.write(f"ERROR: {e}\nSTDOUT:\n{e.stdout}\nSTDERR:\n{e.stderr}\n")
        f.write("```\n\n")

print("All queries completed.")
