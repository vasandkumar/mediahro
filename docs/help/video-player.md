---
ids: [VID-060, VID-061, VID-062, VID-063, VID-064, VID-065, VID-066, VID-067, VID-068, VID-069, VID-070, VID-072, VID-074]
---
# The video player

Tap the video to show or hide the controls. They hide by themselves after 3 seconds while the video plays, and stay up while a screen reader is on.

## Touch gestures (phones and tablets)

| Gesture | What it does |
|---|---|
| Tap | Show or hide the controls |
| Double-tap the left or right side | Skip back or forward (10 seconds; choose 5 to 60 in Settings → Video) |
| Double-tap the middle | Play or pause |
| Swipe left or right | Seek; the target time shows while you swipe |
| Swipe up or down on the left | Screen brightness |
| Swipe up or down on the right | Volume |
| Touch and hold | Play at 2× while you hold (choose the speed in Settings) |
| Pinch | Switch between fitting the video and filling the screen |
| Two-finger swipe left or right | Move the subtitles earlier or later |

Each gesture can be turned off, and the swipe sensitivity can be changed, in Settings → Video. The lock button turns off every gesture until you tap the screen and unlock.

## Seek bar

Drag the seek bar to move through the video; the time and chapter name show above your finger. Chapters are marks on the bar, and an A-B loop shows its two ends. When the video is paused, seeking stops on the exact frame.

Screen readers adjust the seek bar in 1 % steps, with actions for 10 % steps.

## Speed

Tap the speed chip to choose 0.25× to 4× in 0.05 steps, or one of the presets. The pitch stays natural. Mediahro remembers the speed for each video (or for all videos, or not at all: Settings → Video → Remember speed).

## Frame step, A-B loop, chapters and bookmarks

- **Frame step:** `,` and `.` on a keyboard step one frame back or forward and pause.
- **A-B loop:** press `B` once to set the start and again to set the end; the section repeats until you press `N`.
- **Chapters and bookmarks:** the list button at the top shows the video's chapters and your bookmarks. Add a bookmark with an optional note at the current position; tap one to jump to it.

## Resume and what happens at the end

Videos start where you stopped watching, with a "Start over" button for a few seconds. Positions are kept separately for each server a video comes from. A video counts as watched after 90 %.

When a video ends, Mediahro shows the next one in the folder with a countdown you can cancel. In Settings → Video you can instead stop, play the video again, close the player, or be asked whether to delete the file.

## Audio and subtitle tracks

The Audio and Subtitles chips list every track with its language, format and channels. Your choice is remembered for the rest of the series or folder, and Settings → Video sets the languages you prefer. Both sheets also move the audio or subtitles earlier or later (audio in 10 ms steps up to 5 seconds, subtitles in 50 ms steps up to 60 seconds); the delay is kept for that video.

## Playback information

The information button shows the format details: container, video codec, whether the hardware decoder is used, resolution, frame rate, dropped frames, bitrate, dynamic range (SDR, HDR10, HDR10+, HLG), the audio format and output, and the subtitle renderer.

## Picture in picture

The picture-in-picture button at the top (or **More → Picture in picture**) shrinks the video into a small window that stays on top of other apps. Its play, pause and skip buttons work like the player's. To go into picture in picture automatically when you leave the app while a video plays, turn on **Settings → Video → Picture in picture when leaving**.

## Playing in the background

By default a video pauses when you switch apps or turn the screen off. To keep the sound playing for the current video, turn on **More → Keep playing in the background**; to always keep playing, choose **Always** in **Settings → Video → Play in the background**. While only the sound plays, the picture is turned off to save battery; it comes back when you return. **More → Sound only** turns the picture off while you are in the app too.

When a video starts, music that is playing pauses.

## Rotation, screen and brightness

On phones and tablets the screen turns to match the video: landscape for wide videos, portrait for tall ones. **Settings → Video → Rotation** can follow the device instead, or always stay in landscape or portrait. The screen stays on while a video plays. When you close the player, the brightness and rotation go back to how they were.

## Lock screen, notification and media keys

While a video plays, its title shows on the lock screen and in the notification. Their buttons, headset buttons and keyboard media keys play, pause, seek and skip to the next video.

## Volume and boost

The Audio sheet has a volume slider from 0 to 300 % and a mute button. Above 100 % the sound is amplified for quiet videos; a limiter keeps loud parts from distorting. Mediahro remembers the volume for each output (phone speaker, headphones, Bluetooth, TV) and switches to it when you change outputs.

## Sleep timer

**More → Sleep timer** pauses the video after 15, 30, 45, 60 or 90 minutes, at the end of this video, or at the end of the last queued video. The sound fades out over the last 30 seconds, and a chip on the player shows the time left; tap it to change or turn off the timer. The countdown stops while the video is paused.
