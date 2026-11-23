# Flow offline replay

Everything here reads copies. Nothing opens a live database and nothing is committed that comes from one.

## Make the copies (read-only on the server; a temp tarball is removed afterwards)

```bash
ssh subi@100.99.105.51 'T=$(mktemp -d); L=/DATA/AppData/navivibe/listening_logs; mkdir $T/logs
for f in $L/*_listening_log.db; do sqlite3 -readonly "$f" ".backup \"$T/logs/$(basename "$f")\""; done
sqlite3 -readonly /opt/shuffle-server/catalog.db ".backup $T/catalog.db"
sqlite3 -readonly /opt/shuffle-server/spotify_details.db ".backup $T/spotify_details.db"
cp /opt/shuffle-server/mood_tags.json /opt/shuffle-server/mood_admin.json /opt/shuffle-server/mood_meta.json $T/
cp -r $L/mood_overrides $T/ 2>/dev/null
tar -C $T -czf /tmp/flowcopy.tgz . ; rm -rf $T'
scp subi@100.99.105.51:/tmp/flowcopy.tgz . && ssh subi@100.99.105.51 'rm -f /tmp/flowcopy.tgz'
mkdir data && tar -C data -xzf flowcopy.tgz
scp -r subi@100.99.105.51:/opt/shuffle-server/navivibe tree/navivibe          # the code: FLOW_TREE is tree/
```

(`explore/state.db`, the Flow served-songs table, is only needed for `familiarity.py`'s Flow-served join: copy `$L/explore/state.db` to `data/state.db` the same way.)

## Run

```bash
export FLOW_DATA=$PWD/data FLOW_TREE=$PWD/tree FLOW_OUT=$PWD/out; mkdir -p out
python -I eval/replay.py old                                   # the live flow.py: queues for every listener x chip x seed
# a patched copy: tree2/navivibe = tree/navivibe + `python patch_flow.py tree2/navivibe/flow.py` + files/navivibe/flow_v2.py
FLOW_TREE=$PWD/tree2 FLOW_V2=on     python -I eval/replay.py v2
FLOW_TREE=$PWD/tree2 FLOW_V2=shadow python -I eval/replay.py shadow
python -I eval/final.py        # every table in docs/flow-better.md except the three below
python -I eval/coverage.py     # chip sizes, label and feature coverage, random-queue baseline
python -I eval/skipmodel.py    # the owner's skip model: fit quality, coefficients, with and without transition features
python -I eval/risk.py old v2  # predicted skip risk of the replayed queues
python -I eval/familiarity.py  # skip rate by prior plays; Flow-served songs (needs data/state.db)
```

`SEEDS` (default 2), `MINPLAYS` (default 150) tune `replay.py`. The stand-in engine uses the catalog's effnet vectors reduced to 32 dimensions for "sound of the track" and **no word vectors**, so absolute rankings differ from the live engine; old and new run on the same stand-in, which is what the comparison needs.

Python 3.10+, numpy, scikit-learn (skip model only), rapidfuzz, and whatever the navivibe package imports (the server's venv has it).
