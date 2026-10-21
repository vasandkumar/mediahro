---
ids: [MUS-010]
---
# Identify a song

If a song has no tags, or the wrong ones, Mediahro can recognise it from its sound and fill them in.

## How to use it

1. In a song list, open the **⋮** menu of the song and choose **Identify song**.
2. The first time, Mediahro asks before it contacts anything. Choose **Allow and identify** to turn it on. You can turn it off again under **Settings → Privacy**.
3. Mediahro listens to the first two minutes of the song on your device and turns them into a short fingerprint. This takes a few seconds.
4. The fingerprint and the song's length go to acoustid.org, a free community service, which answers with the songs it thinks this is, best match first.
5. Tap the right one. Mediahro writes its title, artist, album and year into the file's tags, using the same safe write as **Edit tags**: a checked copy first, then the swap. You can undo it from the tag editor.

## What leaves your device

Only the fingerprint, the song's length and Mediahro's application key. The audio itself and your tags are never sent. Nothing is written to a file until you tap a match.

## When it doesn't work

- **No match found:** AcoustID doesn't know the song. Edit its tags by hand.
- **Couldn't identify this song:** check your connection and try again. AcoustID allows only a few requests a second, so wait a moment.
- **This file's tags couldn't be changed:** the file is read-only or its format can't be written (see **Edit tags**).
- **Not available in this build:** this version of Mediahro was built without an AcoustID key.
