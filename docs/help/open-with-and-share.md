---
ids: [CORE-003, SYS-003, SYS-004]
---
# Open with, Share and shortcuts

Other apps can hand files and links to Mediahro, and the launcher or the Assistant can jump to a screen. Mediahro treats all of it as untrusted: it only opens what it was given permission to read, and nothing is fetched without you choosing it.

## Open with and Share (Android)

- **Open with** on a video or audio file in Files or another app plays it at once. Several files shared together play one after the other.
- **Open with** or **Share** a picture, or several, and Mediahro shows them full screen. Swipe between them and pinch or double-tap to zoom. The pictures are read once and not copied into your library.
- **Share** a link from a browser or another app to play the stream. The link is allowed as a stream you opened yourself and is added to your recent links.
- **Share** plain text and Mediahro searches your library for it. The text is never sent anywhere.
- To make Mediahro the default for a kind of file, use **Set as default** in Settings, which opens Android's *Open by default* page for the app.

## What is not opened

- Links and files of any other kind (for example `smb://`, `ftp://` or a private file of another app) are refused with a short message. Add network shares in **Sources** instead.
- Playlists and subtitle files shared from other apps are not opened yet either.

## Shortcuts and voice

- Long-press the Mediahro icon for shortcuts to Video, Music, Photos and Search. The Assistant can open them by name ("open music in Mediahro", "search for … in Mediahro").
- **Resume** plays the video you watched last, or returns to the last screen you used if there is none.
- A playlist asked for by name opens Music; starting it by name is not available yet.
- Shortcuts never open the vault, hidden albums or private mode. If one asks for them, Mediahro shows the Photos tab, where the vault asks for its normal unlock.
