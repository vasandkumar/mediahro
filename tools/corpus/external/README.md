# Corpus samples made with external tools

`test-media/corpus/*` (Git LFS) holds synthetic files that FFmpeg cannot make. They are our own signals (a 440 Hz sine, `testsrc2`), so they carry no third-party content; the tools below are only used to write them and are never shipped. `tools/corpus/generate.dart` copies them into the generated corpus (`_prebuilt`).

| File | Tool | Licence |
|---|---|---|
| `ape_tone.ape` | Monkey's Audio SDK 13.42 (`MAC` console encoder) | "Monkey's Audio License Agreement (3 clause BSD)" |
| `mpc_tone.mpc` | `mpcenc` 1.30.1 (Musepack `musepack_src_r475`) | LGPL-2.1-or-later (used as an offline test-data generator only; its output is plain data) |
| `dv_p81.mp4`, `dv_p81.mkv` | `dovi_tool` 2.3.3 (MIT) + FFmpeg 8.1 | MIT |
| `hdr10p.mp4`, `hdr10p.mkv` | `hdr10plus_tool` 1.7.2 (MIT) + FFmpeg 8.1 | MIT |

SHA-256 of the committed files: see `test-media/LICENSES.md`.

## Recipe

Tools build: Monkey's Audio with CMake (`-DBUILD_SHARED=OFF -DBUILD_UTIL=ON`, MinGW), `mpcenc` with CMake after `mpcenc-fastmath-nonconst.patch` (the 2011 code writes into `const` tables and crashes on current linkers; also `-std=gnu17 -Wno-incompatible-pointer-types`), `dovi_tool` and `hdr10plus_tool` with `cargo install --path <clone of the tag> --locked` (not on crates.io; `dovi_tool` 2.3.4 needs Rust 1.95).

```
# signal: 3 s, 44.1 kHz stereo, left 0.5 and right 0.125 of full scale (-6 and -18 dBFS)
ffmpeg -y -f lavfi -i "aevalsrc=0.5*sin(2*PI*440*t)|0.125*sin(2*PI*440*t):s=44100:d=3" -c:a pcm_s16le tone.wav
MAC tone.wav ape_tone.ape -c4000
mpcenc --standard tone.wav mpc_tone.mpc

# HDR10 base: 640x360, 25 fps, 75 frames, no B-frames (raw HEVC with B-frames cannot be stream-copied into Matroska)
X='pools=2:preset=ultrafast:bframes=0:repeat-headers=1:keyint=25:open-gop=0:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:range=limited:hdr10=1:hdr10-opt=1:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400'
ffmpeg -y -f lavfi -i "testsrc2=size=640x360:rate=25:duration=3" -pix_fmt yuv420p10le -c:v libx265 -x265-params "$X" -f hevc base_hdr10.hevc

# Dolby Vision profile 8.1 (config: dovi_p81.json)
dovi_tool generate -j dovi_p81.json -o dovi_p81_rpu.bin
dovi_tool inject-rpu -i base_hdr10.hevc --rpu-in dovi_p81_rpu.bin -o dv_p81.hevc
ffmpeg -y -framerate 25 -i dv_p81.hevc -c:v copy -bsf:v dovi_rpu -strict unofficial dv_p81.mkv
ffmpeg -y -framerate 25 -i dv_p81.hevc -c:v copy -bsf:v dovi_rpu -strict unofficial -tag:v hvc1 dv_p81.mp4

# HDR10+ (metadata: python -I make_hdr10plus_json.py hdr10plus_meta.json)
hdr10plus_tool inject -i base_hdr10.hevc -j hdr10plus_meta.json -o hdr10p.hevc
ffmpeg -y -fflags +genpts -framerate 25 -i hdr10p.hevc -c:v copy -tag:v hvc1 hdr10p.mp4
ffmpeg -y -framerate 25 -i hdr10p.hevc -c:v copy hdr10p.mkv
```

Both `-bsf:v dovi_rpu` and `-strict unofficial` are needed for FFmpeg to write the Dolby Vision configuration (`dvvC` box, or the Matroska block-addition mapping). HDR10+ is in-band SEI, so the container has no extra box.

FFmpeg reports about 1.67 s for the MPC file although it decodes to about 3.03 s (its `mpc8` demuxer): tests must not assert the header duration.
