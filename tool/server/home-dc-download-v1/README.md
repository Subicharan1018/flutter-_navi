# home-dc-download-v1

Telethon cannot export an authorization to the data center it is already on, so every download from the account's home DC (DC5) logged "borrow failed" and used one connection (about 1 MB/s; other DCs 4-5 MB/s). For the home DC the parallel requests now share the main connection. Other DCs are unchanged.

`bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`. Rollback: the backup folder the installer prints.
