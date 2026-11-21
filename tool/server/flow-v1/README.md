# flow-v1: Flow stops replaying the same songs

A song Flow served a listener rests for 5 days in every session (before: only inside one
session). A small pool relaxes the rest instead of returning nothing. The "last plays" window
grows with the library (50 to 150). Familiar songs are ranked by plays blended with time since
last play. Patches `navivibe/flow.py` (and flips one old test that pinned the old behaviour).

Run as subi: `bash install.sh`, then (only after "Done") `sudo systemctl restart navivibe`.
Tests run on a scratch copy first; the live files are restored if a live test fails.
