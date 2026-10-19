---
ids: [SUB-010, SUB-011, SUB-012, SUB-013, SUB-014, SUB-015, SUB-016]
---
# Subtitles

## Supported formats

- **Text:** SRT, WebVTT, ASS and SSA (with styles, karaoke, animations and fonts embedded in the video), SMI/SAMI, MicroDVD, TTML/DFXP, LRC and plain text.
- **Image:** PGS (SUP), VobSub (IDX and SUB) and DVB. Image subtitles in HDR videos are adjusted to the video's brightness so they are not too bright.

## Where Mediahro looks for subtitles

Mediahro shows every subtitle track inside the video. It also finds subtitle files next to the video when they:

- have the same name as the video, for example `Film.srt` for `Film.mkv`,
- have the same name plus a language, for example `Film.en.srt`,
- are in a `Subs` folder next to the video.

You can also choose any subtitle file from the player, or drop one onto the player window on a computer.

## Character encoding

Mediahro detects the character encoding of subtitle files, so subtitles in any language show the right letters. If a file still looks wrong, choose the encoding yourself in the subtitle settings.

## Appearance

Change the font, size, colour, outline, shadow, background box, position and alignment in the subtitle settings. By default Mediahro uses your system's caption preferences. You can also make styled ASS subtitles use your own appearance.

## Timing

If subtitles appear too early or too late, change the delay by up to 60 seconds in either direction, in 50 ms steps. You can also change the subtitle speed, for example to fit subtitles made for a 25 fps version to a 23.976 fps video. Mediahro remembers these settings for each file.

## Two subtitles at once

Show a second subtitle track at the same time, for example to learn a language. Each track has its own position, size and delay.
