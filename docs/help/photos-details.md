---
ids: [IMG-006]
---
# Photo details and editing them

The **Details** button (ⓘ) shows what is known about the photo: its name, size and dimensions, when it was taken, the camera and lens, where it was taken, the colour profile, its rating, title, description and keywords. **All metadata** lists every other tag in the file.

## Changing details

Choose **Edit details** to change the date and time, the location, the title, the description, the keywords and the rating. Only what you change is written.

- **Location**: type a latitude and longitude in degrees (for example 48.8584 and 2.2945), or choose **Remove location**.
- **Keywords**: separate them with commas.
- **Rating**: tap a star; tap the same star again to clear it.

Mediahro writes the changes into the photo file itself for JPEG, PNG, WebP, TIFF, HEIC, AVIF and JPEG XL, so other apps see them too. Everything else in the file stays as it was, including the camera's own notes.

### Camera RAW and other files

RAW files are never modified. Mediahro saves your changes in a small `.xmp` file next to the photo, with the same name, which Lightroom, darktable and most other photo programs read. The same happens if a particular file can't hold the change (for example a HEIC without a metadata block); Mediahro tells you when it did.

### Sources that are read-only

If the folder or share is read-only, saving fails with a message and nothing is changed.

## Privacy

Mediahro can remove location and camera details when you share a photo; that option arrives with sharing.
