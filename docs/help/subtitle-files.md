---
ids: [SUB-010, SUB-011, SUB-012, SUB-013]
---
# Subtitle files and encodings

## Subtitles that load by themselves

Mediahro shows a video's built-in subtitle tracks and also looks for subtitle files that belong to it:

- files in the same folder named like the video, such as `Film.srt`, `Film.en.srt` or `Film.eng.forced.ass`. The language and "forced" or "SDH" tags in the name are read;
- every subtitle file in a `Subs` folder next to the video, or in `Subs/<video name>/`;
- files named like the video in your own subtitle folder.

This works for videos on network shares, WebDAV, cloud folders and folders you added on Android, not only for files on the device. Subtitles in your preferred language (Settings → Video) are shown first. If you turned subtitles off for a video or series, they stay off.

The Subtitles sheet lists every track by language and format: SRT, ASS/SSA, WebVTT, SAMI, MicroDVD, TTML and MP4 text, and the picture-based PGS, VobSub and DVB.

## Adding a subtitle file

In the player, open **Subtitles → Add a subtitle file** and choose any subtitle file. It is added as a track and shown at once.

## Wrong characters

Mediahro detects the character encoding of text subtitles. If an older file still shows wrong letters, open **Subtitles → Character encoding** and choose its encoding, for example **Cyrillic (Windows-1251)** or **Chinese, simplified (GB18030)**. Your choice is remembered for that video.
