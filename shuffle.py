# Minimal Flask wrapper
from flask import Flask, jsonify, request
from shuffle_model import ShuffleEngine, load_model

app = Flask(__name__)
matrices, count_maps, behaviour, flac = load_model()
engine = ShuffleEngine(matrices, count_maps, behaviour, flac)

@app.route("/next")
def next_songs():
    current  = request.args.get("current", "")
    playlist = request.args.get("playlist", None)
    artist   = request.args.get("artist", "")
    count    = int(request.args.get("count", 15))
    results  = engine.next_songs(current, playlist=playlist,
                                  last_artist=artist, count=count)
    return jsonify(results)

# Run: python shuffle_server.py
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)