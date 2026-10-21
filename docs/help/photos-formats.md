---
ids: [IMG-001]
---
# Photo and image formats

Mediahro shows these image types on Android:

| Kind | Formats |
|---|---|
| Common | JPEG (including progressive and CMYK), PNG and animated PNG, GIF, WebP (also animated), BMP, ICO |
| Modern | JPEG XL, AVIF (also animated) |
| Camera RAW | Canon, Nikon, Sony, Adobe DNG, Fujifilm, Olympus, Panasonic, Pentax, Samsung and most others |
| Vector | SVG (drawn on your device; see below) |
| Scientific and graphics | TIFF (16-bit and multi-page), EXR and Radiance HDR (tone-mapped), Photoshop PSD/PSB (the flattened picture), DDS, TGA, PNM, QOI |

## Camera RAW

A RAW file opens at once from the full-size preview your camera stored in it, and the finished picture replaces it a moment later: Mediahro develops the RAW itself (white balance from the camera, standard colours). RAW files are never changed; your edits to details go into a `.xmp` file beside them.

## SVG

SVG pictures are drawn by Mediahro itself. A vector picture has no pixel size, so Mediahro draws it on a canvas whose long side is at least 2048 pixels (and at most 8192), which keeps it sharp when you zoom in. SVG files larger than 8 MB are not drawn. Pictures inside an SVG that point to a web address are never fetched: only pictures stored inside the file are shown, so opening an SVG never uses the network. Scripts and animations in an SVG are ignored. Transparent parts show the viewer's background.

## Animations

GIF, WebP and APNG animations play in the viewer. Use the pause button; if your phone's "remove animations" setting is on, animations start paused.

## What does not open

Files that are damaged, or in a format Mediahro does not read, show a message instead of the picture. Photoshop files saved without "Maximise compatibility" have no flattened picture inside and cannot be shown. HEIC and HEIF photos depend on your phone's own support for them.
