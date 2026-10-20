---
ids: [MUS-003]
---
# Editing tags

You can change the title, artist, album, track numbers and every other common field of your songs, one at a time or many at once. Mediahro writes the changes into the song files themselves, so other players see them too.

## Editing

- **One song:** open the song's menu (⋮) and choose **Edit tags**.
- **A whole album, artist or genre:** open it and tap the edit button at the top.

In a batch, a field that differs between songs starts empty with the hint "Several values: leave empty to keep". Leave it empty and each song keeps its own value. Type into it and every song gets that value.

For **Artist**, **Album artist**, **Genre** and **Composer**, separate several values with `;`.

Tap **Save**. Mediahro shows its progress and tells you if any file couldn't be changed, and why.

## Cover

**Replace cover** picks an image to embed as the front cover. **Remove cover** removes the embedded pictures. Other embedded pictures, such as a back cover, are kept when you replace the front.

## File names

- **Fill from file name** reads tags from each file's name with a pattern, for example `%track% - %artist% - %title%` turns `07 - Bo - Hey.flac` into track 7, artist Bo, title Hey.
- **Rename files from tags** renames each file from its tags, for example `%track% - %title%` gives `07 - Hey.flac`. Track numbers get two digits. Characters that file names can't contain become `_`. Lyrics files next to the song (`.lrc`) are renamed with it.

Available placeholders: `%track%`, `%disc%`, `%title%`, `%artist%`, `%albumartist%`, `%album%`, `%year%`, `%genre%`, `%composer%`. The dialog shows a preview for the first file.

## Safe by design

Mediahro never changes a song file in place. For each file it:

1. writes a new copy with the new tags, copying the audio unchanged;
2. reads the copy back and checks that the new tags are there; if not, the original stays as it was;
3. swaps the copy in. If anything fails during the swap, the original is put back.

Information Mediahro doesn't edit is kept, for example other apps' private tag data, extra pictures and chapters.

Supported formats: MP3 (ID3v2.4, plus APE and ID3v1 when present), FLAC, Ogg Vorbis, Opus, M4A/M4B/ALAC, WMA, WAV, AIFF, DSF, Monkey's Audio, WavPack and Musepack.

## Undo

Changed your mind? On the Music screen, open the menu and choose **Undo last tag edit**. This restores the fields the last save changed, for every song in it.
