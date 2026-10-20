# Android device batch 1: checks that need a person

The automated tests for batch 1 run on the Samsung first. These 15 checks need eyes, ears or a finger. Sample files are copied to the phone in **Download/MediahroTest**: `sample.mp4` with `sample.en.srt`, `cyrillic.mp4` with a Windows-1251 `cyrillic.srt`, `styled.mp4` with `styled.ass`, and `dual.mkv` with English and French subtitle tracks.

Before you start: in Mediahro, add the folder **Download/MediahroTest** as a source (Sources › Add folder) and allow notifications when asked.

## Picture-in-picture and background (#32)
1. Play `sample.mp4`, then More › Picture-in-picture. The video continues in a small window.
2. Play it again and press Home. It goes into picture-in-picture by itself.
3. Play it, turn on More › Sound only, then turn the screen off. The sound keeps playing, and the lock screen shows controls.
4. Lock rotation to landscape in the player, then leave the player. The app goes back to portrait.

## Volume and sleep timer (#35)
5. Set the volume to 250 %. It sounds louder, without crackling.
6. Connect headphones. The volume switches to the level you last set for headphones.
7. Set the sleep timer to "End of this video" and seek to 10 s before the end. It fades out and pauses.

## Subtitles (#38, #40)
8. Open `sample.mp4` from the added folder. The English subtitles appear by themselves.
9. In the player, use Subtitles › Add a subtitle file and pick `cyrillic.srt`. Choose the Cyrillic encoding, and the Russian text reads correctly.
10. Settings › Subtitles: set Size to Huge and Background to Solid box. The subtitles of a playing video change.
11. Open `styled.mp4` with `styled.ass`. The yellow italic text stays at the top unless "Override file styles" is on.
12. Open `dual.mkv` and turn on a second subtitle track. The second track shows at the top.

## Fingerprint or PIN (#33)
13. Turn on a parental PIN or the vault with biometrics (when that screen exists, otherwise skip). The prompt shows, and a fingerprint or PIN unlocks it.
14. Cancel the prompt. It stays locked.

## Lock screen
15. Play a song, then a video. The lock-screen buttons control only what's playing now.

Tell the orchestrator the numbers that failed and what you saw; everything else counts as passed.

## Batch runner notes

Notes for whoever runs a device batch (orchestrator, Samsung SM-M176B, Flutter 3.47.7). They apply to every batch.

- Do not pass `--no-dds` to `flutter test integration_test/...`. On Flutter 3.47.7 it causes a spurious `VmServiceProxyGoldenFileComparator` error and the run hangs.
- Pass `--no-uninstall` so runtime permission and appops grants survive from one test file to the next.
- After the first install, grant `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, `READ_MEDIA_IMAGES` and `POST_NOTIFICATIONS`, and run `appops set com.mediahro.app SCHEDULE_EXACT_ALARM allow` (needed by `c4a_android_car_alarm_test`).
- Generate the engine corpus with `dart run tools/corpus/generate.dart`, then stage it on the phone with `tool/stage_corpus.py`, before any `engine_test` run (restage when a new sample such as `mp4_movtext.mp4` is added).
- `c4a_android_tls_test` can hang after a failure. Always run it with a timeout.
- Results of each batch go in `docs/release/android-batch-N-results.md` (batch 2: `android-batch-2-results.md`).
