---
ids: [SUB-050]
---
# Syncing subtitles to the audio

Subtitles that are a few seconds off, or that drift further off as the film goes on, can be fixed automatically. In the player, open **Subtitles → Sync to the audio**.

Mediahro listens to the video's soundtrack on your device, finds where people are speaking, and lines the subtitles up with the speech. It checks a plain offset of up to a minute either way, and the common frame-rate mismatches (for example subtitles made for 23.976 fps on a 25 fps video). Nothing is uploaded.

The audio is read much faster than the film plays, and a progress bar shows how far it has got; **Cancel** stops it. When it finishes, the fix is applied straight away so you can watch the result, with **Undo** in the message at the bottom. The fix is kept for this video, as its subtitle delay and speed. To write it into the subtitle file itself, open **Edit subtitles** and save.

If the speech and the subtitles don't clearly match, for example because the subtitles belong to a different cut of the film, Mediahro says so and lets you decide whether to apply the result anyway.

Syncing works with subtitle files. It needs a player engine update that is on its way; until then the option is shown but unavailable.
