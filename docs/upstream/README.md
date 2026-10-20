# Upstream patches (owner's decision to send)

Patches that fix bugs in upstream projects Mediahro depends on. Sending them means posting to a public mailing list or tracker, which only the owner decides. Each entry says what the patch fixes, how it was verified, and how to send it.

Until a patch is accepted upstream, the same change is carried in `mediahro-deps` (`patches/<project>/`), and any Dart workaround stays until every pinned archive carries it.

## FFmpeg: `avformat/mov: do not trim iTunSMPB padding twice`

File: [`ffmpeg/0001-avformat-mov-do-not-trim-iTunSMPB-padding-twice.patch`](ffmpeg/0001-avformat-mov-do-not-trim-iTunSMPB-padding-twice.patch), made against FFmpeg master `71403a21b0` (`libavformat/mov.c`).

**Bug.** `mov_read_custom()` discards the iTunSMPB end padding from `duration - remainder`. This assumes the media duration still includes the padding, as iTunes writes it. Some files have stts/mdhd that already end at `priming + samples`, for example FFmpeg 6.x AAC output (last frame shortened) tagged afterwards with iTunSMPB. For those, the demuxer drops `remainder` real samples at the end of every track and gapless albums lose audio at each join.

**Fix.** The discard point becomes `min(max(duration - remainder, priming + samples), duration)`. iTunes-framed files are unchanged because both values are equal there.

**Evidence (Mediahro lane B1, AUD-002).** Fixtures come from `tools/corpus/generate.dart`: `gapless_m4a_*` (iTunes framing) and `gapless_m4a_ff_*` (FFmpeg framing). Each is a 2 s, 44.1 kHz sine with priming 1024, remainder 888 and 88200 samples.

| Fixture | `ffmpeg -i x.m4a -f s16le -` (FFmpeg 8, unpatched) | Expected |
|---|---|---|
| `gapless_m4a_1.m4a` (iTunes framing) | 88200 samples | 88200 |
| `gapless_m4a_ff_1.m4a` (FFmpeg framing) | 87312 samples | 88200 |

With the patch, both decode to 88200; the arithmetic is in the commit message. Mediahro's engine works around the bug in `packages/mediahro_engine/lib/src/mpv/mp4_gapless.dart`. The workaround only applies to files that need it, and conformance tests `AUD-002 gapless m4a (iTunes framing)` / `(FFmpeg framing)` cover both cases.

**Before sending (owner):**

1. Apply the patch to a current FFmpeg checkout: `git am docs/upstream/ffmpeg/0001-*.patch`.
2. Set yourself as the author and add your sign-off, which FFmpeg requires: `git commit --amend --reset-author -s`.
3. Build and run `make fate-mov` (and `make fate` if time allows). Reviewers may ask for a FATE sample; `gapless_m4a_ff_1.m4a` (49 KB) can be offered.
4. Send it with `git send-email --to=ffmpeg-devel@ffmpeg.org -1`.
