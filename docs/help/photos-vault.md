---
ids: [IMG-011, PRIV-007]
---
# The vault

The vault keeps private photos **encrypted** behind a PIN, and behind your fingerprint or screen lock too if you turn that on. Open it from **Albums → Vault**.

## Set-up

- Choose a **PIN of 4 to 12 digits** (6 or more is better). The PIN is typed on Mediahro's own number pad, so no keyboard learns it.
- The first time you also choose, if you want, a **second vault** with its own PIN (see below) and whether the **fingerprint or screen lock** opens the vault.
- The photos' keys are kept by the phone's secure hardware and never leave it. The PIN is turned into a key with a slow function (600,000 rounds) on a background thread, which takes a moment on purpose.

## Using it

- **Move photos in:** the viewer's ⋮ menu, or **More** on a selection, then **Move to vault**. You enter the PIN (or use the fingerprint), then confirm. Each photo is encrypted and read back to check it, and only then deleted from its folder and from Mediahro's library (entry, tags, rating, albums and search). If the original can't be removed (a read-only source), the photo is not moved. Videos can't go in yet.
- **Add from the vault:** the plus button copies photos you pick into the vault; the originals stay where they are, so delete them yourself. Files over 64 MB are skipped.
- **Look:** tap a photo to view it, swipe for the next. Pictures are decoded in memory only; nothing readable is written to disk, and nothing from the vault shows in the timeline, albums, places or search.
- **Take out:** select photos, **Take out**, choose where to save. The copy is saved first and then removed from the vault; its rating, colour label and tags are written back into the file where the format can hold them, so the library reads them again. This is not an export tool: the saved copy is plain.
- **Delete for good** erases photos without a trash.
- **Fingerprint:** ⋮ → **Fingerprint unlock** turns it on or off for the vault you are in. Adding a fingerprint to the phone, or removing the screen lock, turns it off by itself; the PIN keeps working.
- **Change PIN:** ⋮ → **Change PIN** (this turns the fingerprint off for that vault; turn it on again if you want it).
- **Locking:** the vault locks when you press **Lock**, leave the screen, or send the app to the background, and every vault screen closes. While a vault screen is up, Android hides the window from screenshots, screen recordings and the recent-apps picture.

## Wrong PINs

Three wrong PINs are free; after that you wait 30 seconds, then 1 minute, 2 minutes and so on, up to a day. The wait is remembered when you close the app.

## The second vault

If you set a second PIN, it opens a second, separate vault. The two look and behave exactly alike: the same screens, the same menu, the same lock screen. Which one a PIN opens is decided only by the PIN, and moving photos in never asks about the other vault. Both are made when you set up (the second one gets a PIN nobody knows if you don't give one), they have random folder names, and they hold the same kinds of files.

This helps if someone makes you open the vault: open the second one. It does **not** make the first one invisible to someone who can examine this phone's storage: they can still find that two vaults exist, and a skilled examiner may be able to tell which is which from file dates or sizes. Never use the second vault for anything you need kept safe.

## What can go wrong

- **If the phone's key is lost** (the app data was restored on another phone, or the key store was reset), the vault can't be opened and **there is no way back**. Mediahro says so and offers **Reset the vault** after a clear question; it deletes both vaults. Take photos out first if you plan to restore or switch phones.
- **Backups:** the vault folder is kept out of Android backups and out of transfers to a new phone. A copy of a photo already in a cloud backup or another app, made before you moved it, is not touched.
- **Deleting is best effort** on a phone's flash memory: the original is deleted and its space is reused, but the phone does not promise to overwrite every trace.
- Videos and music can't be put in the vault yet.
