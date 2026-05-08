from flask import Flask, jsonify, request
from shuffle_model import ShuffleEngine, load_model

app = Flask(__name__)

# Load the model and initialize the engine before starting
matrices, count_maps, behaviour, flac = load_model()
engine = ShuffleEngine(matrices, count_maps, behaviour, flac)

@app.route("/next")
def next_songs():
    """Get the next N songs based on the current song and context."""
    current  = request.args.get("current", "")
    playlist = request.args.get("playlist", None)
    artist   = request.args.get("artist", "")
    count    = int(request.args.get("count", 15))
    
    results  = engine.next_songs(
        current_song=current, 
        playlist=playlist,
        last_artist=artist, 
        count=count
    )
    return jsonify(results)

@app.route("/profile")
def song_profile():
    """Inspect a song's behavioural and acoustic profile."""
    song = request.args.get("song", "")
    if not song:
        return jsonify({"error": "Missing 'song' parameter"}), 400
    try:
        profile = engine.song_profile(song)
        return jsonify(profile)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/health")
def health_check():
    """Return a 200 OK status to check if the server is running."""
    return jsonify({"status": "ok"}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
