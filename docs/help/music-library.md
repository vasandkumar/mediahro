---
ids: [MUS-001, MUS-002, MUS-004, MUS-006, MUS-007]
---
# Your music library

## Adding music

Open **Sources** and add a folder with music, or your device's music library. Mediahro scans it and lists the songs under **Music** straight away. It then reads each song's tags in the background, and you see "Reading tags of … songs" while it works. Nothing is uploaded, and nothing leaves your device.

## Browsing

Music has tabs for **Songs**, **Albums**, **Artists**, **Album artists**, **Genres**, **Composers**, **Years** and **Folders**.

- Use the sort button to order songs by title, artist, album, date added, length, most played or year, and albums by title, artist, year or date added. **Reverse order** flips the direction.
- An album shows its songs in disc and track order, its cover, year, song count and total length.
- Albums without an album artist (compilations) stay together by folder and show as "Various artists".
- An artist page shows their albums and then every song.
- **Folders** shows your sources the way they are organised on disk.

## Tags

Mediahro reads these tag formats:

- ID3 (v1, v2.2, v2.3, v2.4) in MP3, WAV, AIFF and DSF
- Vorbis comments in FLAC, Ogg Vorbis, Opus and Speex
- MP4 atoms in M4A, ALAC and M4B
- APE tags in Monkey's Audio, WavPack and Musepack
- ASF in WMA
- WAV INFO and AIFF text chunks

It picks up multiple artists, disc and track numbers, embedded lyrics, ReplayGain values and MusicBrainz IDs. A broken or hostile tag never stops a scan; that file just keeps its file name as its title.

## Cover art

Covers come from the art embedded in the file first. If there is none, Mediahro uses an image in the same folder named `cover`, `folder`, `front`, `albumart` or `album` (JPEG, PNG or WebP). Covers are cached on your device, so an album's songs share one copy.

## Playing and the queue

- Tap a song to play that list from that song. **Play** and **Shuffle** play a whole album, artist, folder or your entire library.
- A song's menu has **Play next** and **Add to queue**.
- The queue button opens the queue. Drag the handle to reorder, swipe a song or use its remove button to take it out, and tap a song to jump to it.
- The queue is saved, so Mediahro remembers where you were after a restart.
- Songs play gaplessly. The next song is always prepared in advance.

## Now Playing

Tap the mini player to open Now Playing. It shows:

- the cover, and the title, artist and album; tap the artist or album name to open it
- a seek bar
- previous, play/pause and next
- shuffle and repeat (off, all, or this song)

Swipe the cover left or right to change songs, and swipe down to close Now Playing. Rotate the device, or use a tablet or desktop window, for a side-by-side layout.
