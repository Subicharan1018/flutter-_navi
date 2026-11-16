"""reshuffle-v1: a reshuffle picks across the top songs, not the same few.

The v3 engine samples each slot with softmax(z / temp), z = standardized score.
Scores are heavy-tailed: a handful of favourites sit far above the rest, so even
at the reshuffle temperature (0.9) they win almost every time and two reshuffles
in a row returned nearly the same queue (ai_order_log, 16 Nov: lY5v, uzH0, TLPL,
QSfk, F4vW at the top of three reshuffles within 7 s).

Now a reshuffle (and frustration mode, which uses the same temperature) samples by
RANK within the top SAMPLE_POOL: weight exp(-rank / (spread * pool)). With the
default pool of 40 and spread 0.33 the top song is picked about 8 % of the time
and every one of the 40 can come up, so a reshuffle varies but stays on taste.
Normal playback keeps the score-based sampling unchanged.

usage: python patch_reshuffle.py <recommender.py>
exit 0: patched or already patched; exit 2: not the expected file (nothing written).
"""
import sys

MARK = "# reshuffle-v1"

OLD_CONST = 'SAMPLE_POOL       = int(os.getenv("V3_SAMPLE_POOL", "40"))\n'
NEW_CONST = OLD_CONST + (
    "# reshuffle-v1: a reshuffle samples by rank in the pool (see _sample); 0 turns it off.\n"
    'RESHUFFLE_RANK_SPREAD = float(os.getenv("V3_RESHUFFLE_RANK_SPREAD", "0.33"))\n'
)

OLD_SAMPLE = """        if temp <= 0 or len(top) == 1:
            return int(top[0])
        z = (ts - ts.max()) / (ts.std() + 1e-6)
"""
NEW_SAMPLE = """        if temp <= 0 or len(top) == 1:
            return int(top[0])
        if temp >= TEMPERATURE_RESHUFFLE and RESHUFFLE_RANK_SPREAD > 0:
            # reshuffle-v1: by rank, not by score. A few favourites score far
            # above the rest, so score-based sampling kept picking them and a
            # reshuffle came back the same. Every song in the pool can come up.
            ranks = np.arange(len(top), dtype=float)
            p = np.exp(-ranks / max(1.0, RESHUFFLE_RANK_SPREAD * len(top)))
            p /= p.sum()
            return int(rng.choice(top, p=p))
        z = (ts - ts.max()) / (ts.std() + 1e-6)
"""


def main(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if MARK in text:
        print(f"   {path}: already")
        return 0
    if text.count(OLD_CONST) != 1 or text.count(OLD_SAMPLE) != 1:
        print(f"!! {path}: not the engine this patch expects; nothing changed.")
        return 2
    text = text.replace(OLD_CONST, NEW_CONST).replace(OLD_SAMPLE, NEW_SAMPLE)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"   {path}: patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
