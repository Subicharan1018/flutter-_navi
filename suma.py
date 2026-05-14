import requests

BASE = "https://subiserver.tail9df1a0.ts.net/"
import hashlib, secrets

salt = secrets.token_hex(6)
token = hashlib.md5(("myadmin" + salt).encode()).hexdigest()

params = {
    "u": "admin",
    "t": token,   # instead of "p"
    "s": salt,
    "v": "1.16.1",
    "c": "myapp",
    "f": "json",
    "id": "76"
}
r = requests.get(f"{BASE}rest/getLyricsBySongId.view", params=params)
data = r.json()

response = data.get("subsonic-response", {})
if response.get("status") == "failed":
    error = response.get("error", {})
    print(f"API Error: {error.get('code')} - {error.get('message')}")
else:
    lyrics_list = response.get("lyricsList", {}).get("structuredLyrics", [])
    if not lyrics_list:
        print("No lyrics found for this song.")
    else:
        for block in lyrics_list:
            print(f"Lang: {block.get('lang', 'unknown')}, Synced: {block.get('synced', False)}")
            for line in block.get("line", []):
                print(line.get("start", ""), line.get("value", ""))