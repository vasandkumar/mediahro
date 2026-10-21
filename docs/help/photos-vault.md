---
ids: [IMG-011, PRIV-007]
---
# The vault

The vault keeps private photos **encrypted** behind a PIN, and behind your fingerprint too if you turn that on. Open it from **Albums → Vault**.

## Set-up

- Choose a **PIN of 6 to 12 digits**; the longer, the better (see below). When you open the vault the PIN is typed on Mediahro's own number pad, so no keyboard learns it. When you **set up** the vault or **change the PIN** the phone's keyboard is used, with suggestions switched off; some keyboards may still remember what you type there.
- The first time you also choose, if you want, a **second vault** with its own PIN (see below) and whether the **fingerprint** opens the vault.
- Each photo is encrypted with its own key. All of them are protected by a secret that belongs to the vault, and that secret is kept locked by your PIN together with a key in the phone's secure hardware. On Android every PIN guess has to be checked by that hardware, so guesses cannot be tried away from your phone, and the wrong-PIN waits (below) apply. The PIN is turned into a key with a slow function (600,000 rounds) on a background thread, which takes a moment on purpose. Someone who gets into the phone itself (a rooted phone, say) could still try PINs on it, which is why a longer PIN is better.

## Using it

- **Move photos and videos in:** the viewer's ⋮ menu, or **More** on a selection, then **Move to vault**. You enter the PIN (or use the fingerprint), then confirm. Each photo is encrypted and read back to check it, and only then deleted from its folder and from Mediahro's library (entry, tags, rating, albums and search). If the original can't be removed (a read-only source), the photo is not moved. For a video, the subtitle, artwork and info files next to it that share its name are deleted with it (the dialog says so), and its play queue entries, artwork and subtitle cache are removed from the library too. The screen is kept on while it works, and every piece is read back before the original goes. If the app goes to the background in the middle, the vault locks and the move stops, and Mediahro says how many were moved.
- **Add from the vault:** the plus button copies the photos, videos and music you pick into the vault, in pieces so a long film does not have to fit in memory; the originals stay where they are, so delete them yourself. Files that are none of those are skipped. A progress bar shows how far it has got and the screen stays on; if the vault locks half way, you are told how many went in. Take out does the same, and says how many could not be taken out and are still in the vault.
- **Look:** tap a photo to view it, swipe for the next. Pictures are decoded in memory only; nothing readable is written to disk, and nothing from the vault shows in the timeline, albums, places or search.
- **Play:** tap a video or a song to play it. It is decrypted a piece at a time as it plays and handed to the player as a private source: nothing decoded is ever written to storage, so the player has no visualiser, no subtitle generation, no screenshots, no picture-in-picture and no casting, and it tells the system nothing about the file (no title on the lock screen or in a notification). Playback stops the moment you leave the vault, lock it, or send the app to the background, and the screen stays on while it plays. Music that was playing is paused.
- **Take out:** select photos, **Take out**, choose where to save. The copy is saved first and then removed from the vault; its rating, colour label and tags are written back into the file where the format can hold them, so the library reads them again. This is not an export tool: the saved copy is plain.
- **Delete for good** erases photos without a trash.
- **Fingerprint:** ⋮ → **Fingerprint unlock** turns it on or off for the vault you are in. Read the note it shows first: anyone can make you place your finger on the phone, so turn it on only in the vault you would not mind being made to open. Adding or removing a fingerprint on the phone turns it off by itself; the PIN keeps working.
- **Change PIN:** ⋮ → **Change PIN** (6 to 12 digits). The new PIN can't be the PIN of the other vault. Only the vault's lock is changed; the photos are not touched and the fingerprint keeps working. If the phone stops or the app is closed in the middle, one of the two PINs still works.
- **Locking:** the vault locks when you press **Lock**, leave the screen, or send the app to the background, and every vault screen closes. While a vault screen is up, Android hides the window from screenshots, screen recordings and the recent-apps picture.

## Wrong PINs

Three wrong PINs are free; after that you wait 30 seconds, then 1 minute, 2 minutes and so on, up to a day. A try counts as soon as you make it, and a right PIN does not wipe the count, so a wrong guess can't be undone by entering the other vault's PIN in between. The count fades slowly: one miss is forgiven every four hours. The wait is remembered when you close the app. The count and the clock are kept on the phone, so someone who can change the phone's clock can shorten a wait; that is one reason to choose a longer PIN. Trying a new PIN in **Change PIN** counts as a try too.

## The second vault

If you set a second PIN, it opens a second, separate vault. The two look and behave exactly alike: the same screens, the same menu, the same lock screen. Which one a PIN opens is decided only by the PIN, and moving photos in never asks about the other vault. Both are made when you set up (the second one gets a PIN nobody knows if you don't give one), they have random folder names, and they hold the same kinds of files.

This helps if someone makes you open the vault: open the second one. It does **not** make the first one invisible to someone who can examine this phone's storage: they can still find that two vaults exist, and a skilled examiner may be able to tell which is which from file dates or sizes. Never use the second vault for anything you need kept safe.

## What can go wrong

- **If the phone's key is lost** (the app data was restored on another phone, or the key store was reset), the vault can't be opened and **there is no way back**. Mediahro says so and offers **Reset the vault** after a clear question; it deletes both vaults. If the app is stopped in the middle of a reset, the reset is finished the next time it starts. A wrong PIN is never mistaken for this: it is only reported when the phone's own key is gone. One damaged folder does not stop the other vault from opening. Take photos out first if you plan to restore or switch phones.
- **Backups:** the vault folder is kept out of Android backups and out of transfers to a new phone. A copy of a photo already in a cloud backup or another app, made before you moved it, is not touched.
- **Deleting is best effort** on a phone's flash memory: the original is deleted and its space is reused, but the phone does not promise to overwrite every trace.
