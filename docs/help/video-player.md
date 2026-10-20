---
ids: [VID-060, VID-061, VID-062, VID-063, VID-064, VID-065, VID-066, VID-072]
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
