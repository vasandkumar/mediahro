---
ids: [IMG-010]
---
# Batch tools

Select photos, then **More → Batch tools**. Videos in the selection are left out.

## Rename

Type a name pattern. Tap a token to add it where the cursor is: `{name}` the old name, `{n:3}` a counter with three digits, `{date:yyyy-MM-dd}` or `{date:HHmmss}` the date and time the photo was taken, `{width}` and `{height}`. The extension is kept. The preview shows the first new names; if two photos would get the same name, the start button stays off until you change the pattern. Sidecar files (`.xmp`) are renamed with their photo.

## Convert

Makes **copies** next to the originals; the originals stay as they are.

- **Format:** keep each photo's own format, or JPEG, PNG, WebP, JPEG XL, and AVIF or HEIC on devices whose system can encode them.
- **Quality** for the lossy formats.
- **Size:** original, or at most 4096, 2048, 1600 or 1024 pixels on the long side. Photos are never enlarged.
- **Remove metadata** leaves location, camera and dates out of the copies.

A copy never overwrites a file: if the name is taken, `_converted` (then `_converted_2`, …) is added.

## Upright

Some cameras store a photo sideways and add a note saying how to turn it. Most apps follow the note; some do not. **Turn upright** saves such photos again with the pixels the right way up and the note reset. It replaces the originals (after a warning) and JPEG files lose a little quality. Only JPEG, PNG, WebP and JPEG XL can be saved over.

## Strip

- **Remove the location only** takes out the GPS position and leaves everything else.
- **Remove all metadata** takes out location, camera, serial numbers, dates, titles and keywords. Orientation and colour profile stay, so the photo looks the same. HEIC, AVIF and RAW files cannot be cleaned in place: convert them with *Remove metadata* instead.

Both change the files themselves (after a warning). The photo keeps its place in your timeline.

## While it runs

A progress box shows how far it is; **Stop** ends the batch after the current photo. At the end a report says how many were done, how many needed nothing, and which could not be processed and why not to worry: the others are unaffected.
