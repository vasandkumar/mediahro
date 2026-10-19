# ffigen configurations

One `<library>.yaml` per native library, generating `lib/src/<library>/<library>_bindings.dart` from the headers shipped in the pinned `mediahro-deps` release (`.deps-cache/<platform>/include`, fetched by `tools/deps/fetch.py`).

| Config | Owner lane |
|---|---|
| `mpv.yaml` | B1 Engine |
| `smb2.yaml`, `nfs.yaml`, `curl.yaml`, `archive.yaml`, `ebur128.yaml`, `chromaprint.yaml`, `uchardet.yaml`, `libssh2.yaml` (Windows `SftpFacade`, ADR-017) | B2 Library & sources |
| `vips.yaml`, `jxl.yaml`, `avif.yaml`, `raw.yaml` | C3 Photos |
| `openmpt.yaml`, `whisper.yaml` | B1 (openmpt), C1 (whisper) |

Generated bindings are committed so builds do not need LLVM. Regenerate with `dart run ffigen --config ffigen/<library>.yaml`.
