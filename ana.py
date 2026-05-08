import pandas as pd
import numpy as np
from collections import defaultdict
import json

def build_transition_matrix(csv_path):
    df = pd.read_csv(csv_path, low_memory=False)
    
    df = df[
        (df['Event Type'] == 'PLAY_END') & 
        (df['Media Type'] == 'AUDIO') & 
        (df['Source Type'] == 'ORIGINATING_DEVICE')
    ].copy()
    
    df['Event Start Timestamp'] = pd.to_datetime(
        df['Event Start Timestamp'],
        format='mixed',
        utc=True,
        errors='coerce'
    )
    df = df.dropna(subset=['Event Start Timestamp'])
    df = df.sort_values('Event Start Timestamp')
    
    df['Play_Ratio'] = df['Play Duration Milliseconds'] / df['Media Duration In Milliseconds']
    df['Play_Ratio'] = df['Play_Ratio'].replace([np.inf, -np.inf], 0).fillna(0).clip(upper=1.0)
    
    df['Time_Gap'] = df['Event Start Timestamp'].diff().dt.total_seconds() / 60.0
    df['Session_ID'] = (df['Time_Gap'] > 20).cumsum()
    
    transitions = defaultdict(lambda: defaultdict(float))
    
    for _, session in df.groupby('Session_ID'):
        songs = session['Song Name'].tolist()
        weights = session['Play_Ratio'].tolist()
        for i in range(len(songs) - 1):
            current_song = str(songs[i])
            next_song = str(songs[i+1])
            weight = weights[i]
            
            if current_song != "nan" and next_song != "nan" and current_song != next_song:
                transitions[current_song][next_song] += weight

    matrix = {}
    for current, next_songs in transitions.items():
        total_weight = sum(next_songs.values())
        if total_weight > 0:
            matrix[current] = {nxt: round((w / total_weight), 4) for nxt, w in next_songs.items()}
            
    return matrix

if __name__ == "__main__":
    matrix = build_transition_matrix("/home/subi/Downloads/shuffle_data/Apple Music Play Activity.csv")
    with open("transition_matrix.json", "w") as f:
        json.dump(matrix, f, indent=2)