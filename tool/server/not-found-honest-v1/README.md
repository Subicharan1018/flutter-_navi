# not-found-honest-v1

`youtube_batch.fetch_one` asked the bot two ways (inline queries: nothing shows in the bot chat) and failed the song as "not found on the music bot" unless every query timed out. One unanswered query plus one empty answer was enough, so a flaky bot failed popular songs (54 of the 5,657-song Tamil import, 25 Nov 2026). Now any unanswered query means the song waits and is asked again. The not-found line also logs how many queries were asked and how many results each gave.

`bash install.sh --check`, then `bash install.sh`, then `sudo systemctl restart tg-fetcher`. To retry songs already failed: Wishlist screen, Try Them Again.
