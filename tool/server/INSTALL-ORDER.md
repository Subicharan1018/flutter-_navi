# Pending server packages: safe install order

Verified by running every full `install.sh` in this order against fake `TG`/`SHUF` roots (copies of the live trees,
the live `.env` tunables present). Nothing on the real server was touched. Run each on the server as subi, from the
package folder (`scp -r tool/server/<name> subi@100.99.105.51:~/` first); none restarts anything.

1. `server-tests-fix-v1`     shuffle-server tests only: suite 1143 passed, 0 skipped. Independent of the others.
2. `tgfetcher-tests-fix-v1`  tg-fetcher tests + a real Weekly Exploration build fix (restart tg-fetcher): **must come before any package that tests the live tg-fetcher tree**
                             (otherwise the live-tree step fails on test_exportify_v1 and rolls back). Do not re-install
                             weekly-exploration-v1 from an old folder afterwards: use the one on main (it carries the fix).
3. `spotify-history-import-v1`  (tg-fetcher 748 passed, shuffle 1143 -> 1149)
4. `matcher-v2`              after the importers it patches (806 passed); a missing spotify_history.py is skipped, so
                             installing it before step 3 would leave that one call site unpatched.
5. `data-queue-v1`           re-copy (from main with the spotify_match.py import fix; 110 shuffle + 6 tg-fetcher tests).
   Not needed again if you do not want the newer matcher in its CSV matcher: the installed one keeps working.
   Already installed and still passing `--check` in this order: channels-primary-v1 (806 passed), weekly-exploration-v2 (43 passed).

Then, once: `sudo systemctl restart tg-fetcher navivibe` (each installer prints its own restart line; one restart after the
last install is enough).

```
for p in server-tests-fix-v1 tgfetcher-tests-fix-v1 spotify-history-import-v1 matcher-v2 data-queue-v1; do
  (cd ~/$p && bash install.sh --check) || break
done
for p in server-tests-fix-v1 tgfetcher-tests-fix-v1 spotify-history-import-v1 matcher-v2 data-queue-v1; do
  (cd ~/$p && bash install.sh) || break
done
sudo systemctl restart tg-fetcher navivibe
```

## preview-feed-v1 (Swipe to fetch)
Independent of the five above; needs only weekly-exploration-v1 and `fetch_access` (both already installed). Web server only, one restart:
`scp -r tool/server/preview-feed-v1 subi@100.99.105.51:~/ && cd ~/preview-feed-v1 && bash install.sh --check && bash install.sh && sudo systemctl restart navivibe`
(`--check` also runs against a scratch copy: 20 package tests + the live server's fetch/security tests.)
