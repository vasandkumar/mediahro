---
ids: [MUS-005, AUD-046]
---
# Lyrics and the visualiser

## Lyrics

Tap the lyrics button at the top of Now Playing to show lyrics in place of the cover. Tap it again to return to the cover.

Mediahro looks for lyrics in this order:

1. Lyrics you created or edited in Mediahro.
2. A lyrics file next to the song with the same name, `.lrc` or `.txt` (for example `03 Song.lrc`).
3. Lyrics stored in the song file: ID3 synced (SYLT) and unsynced (USLT) lyrics, or the `LYRICS` tag in FLAC, Ogg, MP4 and APE files.
4. **LRCLIB**, an open lyrics database, but only if you turn it on.

**Synced lyrics** follow the music: the current line is highlighted and stays in view. With word-timed (enhanced) LRC files, each word lights up as it's sung. Tap a line to jump there. Use the text-size buttons to make lyrics larger or smaller; Mediahro remembers your choice.

### Online lyrics

Online lyrics are off until you turn them on. If a song has no lyrics, tap **Search online (LRCLIB)**. Mediahro explains what it sends: the song's title, artist, album and length go to lrclib.net. No account is needed. Agree, and it searches. You can switch it off again in **Settings → Privacy** under LRCLIB. Lyrics found online are kept on your device, so each song is looked up only once.

### Creating and editing synced lyrics

Tap the edit button in the lyrics view.

1. If the song has no lyrics, paste or type them, one line per row, then tap **Use this text**.
2. Play the song. Each time a line starts, tap **Stamp line**. Blank lines are skipped.
3. Made a mistake? **Undo last stamp** steps back. Tap a stamped line to show its −0.1 s and +0.1 s buttons for fine-tuning.
4. Tap **Save**.

Your lyrics take priority over every other source. To go back to the original lyrics, open the editor and tap **Remove your edit**.

## Visualiser

Tap the visualiser button at the top of Now Playing. Choose:

- **Spectrum:** bars from bass to treble, with falling peak markers
- **Waveform:** the sound wave
- **Level meters:** left and right levels with peak markers

Its colours come from the album cover. **Low-power mode** draws half as many bars, 15 times a second instead of 60, to save battery. The visualiser only analyses audio while it's on screen.

The visualiser needs live audio analysis from the playback engine. On builds without it, the visualiser screen tells you so.
