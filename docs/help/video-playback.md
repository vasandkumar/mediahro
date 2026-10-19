---
ids: [VID-001, VID-002, VID-003, VID-004, VID-005, VID-006, VID-007, CORE-011]
---
# Playing videos

Mediahro plays almost any video file without extra downloads or codec packs.

## Files that play

- **Containers:** MKV, MP4, M4V, MOV, WebM, AVI, WMV, ASF, FLV, TS, M2TS, MTS, MPG, VOB, OGM, OGV, 3GP, RM, RMVB and MXF.
- **Playlists:** M3U, PLS, XSPF and CUE files open as a queue.
- **Video:** H.264, HEVC (8 and 10-bit), AV1, VP8, VP9, MPEG-1, MPEG-2, MPEG-4, ProRes, DNxHD, Theora, MJPEG, FFV1 and more. Mediahro uses your device's hardware decoder first and switches to software decoding when the hardware cannot handle a file.
- **Sound:** all common audio formats in videos, including multichannel tracks, which are mixed for your speakers or headphones.

Very large files (over 4 GB or 20 GB), files with a variable frame rate and damaged or incomplete files also play. A damaged file plays up to its last good frame instead of stopping with an error.

## Surround sound to a receiver

When your device is connected to an AV receiver or soundbar over HDMI, S/PDIF or USB, Mediahro can send surround tracks to it unchanged so the receiver decodes them. Turn this on per output device in the audio settings and choose the formats your receiver supports. If the receiver rejects a format, Mediahro decodes it on the device instead.

## Videos on network shares and servers

Videos on network shares, WebDAV, media servers and web links play and seek like local files. Mediahro reads ahead to keep playback smooth. If the Wi-Fi drops for up to 30 seconds, playback continues from where it stopped once the connection returns.

## DVD and Blu-ray folders and disc images

Open a `VIDEO_TS` or `BDMV` folder, or an `.iso` disc image, and Mediahro plays the main title. You can pick another title, chapter, audio language or subtitle from the player. Disc menus are not shown. Copy-protected discs are not supported.

On Android, iPhone and iPad, Mediahro plays disc folders and images copied to the device.

## If something goes wrong

A file that cannot be played shows a message explaining why. It never closes the app or affects your library or queue. Mediahro saves your position every 5 seconds, so you can resume where you left off even after an interruption.
