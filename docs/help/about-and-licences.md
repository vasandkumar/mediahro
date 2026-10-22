---
ids: [CORE-013]
---
# About, licences and source code

**Settings › About** shows which build you have and where its parts come from. It works offline: the screen reads what is stored in the app and makes no network connections.

## This build

- The name, **version** and build number, and which kind of build it is (Store, Direct download, Open source or Enterprise) for which system.
- A build made by someone else from the source says **Unofficial build** here, as the trademark policy asks.
- The **playback engine** (mpv) and **codec library** (FFmpeg) versions. HEVC and AAC are decoded by your device's own decoders where it has them.

## Open-source licences

**Open-source licences** lists every library in the app with its licence text: the Dart and Flutter packages and the native libraries (FFmpeg, mpv, libass, dav1d and the rest).

## Source code and build details

Mediahro is free software. Some libraries, such as FFmpeg and mpv, are under the GNU Lesser General Public Licence (LGPL). The app links them dynamically, so you can replace them with your own build of the same source.

**Source code and build details** gives:

- the address of the release that holds the complete source of every library in your build, with the SHA-256 of the source archive;
- the exact build options (the FFmpeg configure line, and the mpv and libplacebo options) and the patches applied;
- the list of LGPL libraries in your build.

## Policies and source

The privacy policy, terms of use, trademark policy and the project's source code are listed as web addresses. Use the copy button and open the address in your browser; Mediahro does not open links itself.
