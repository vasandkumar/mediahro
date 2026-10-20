# Android test build: Google Play internal testing (owner checklist)

The first internal-test upload locks the package name `com.mediahro.app` (docs/03). Agents prepare the build; the steps marked **you** need your accounts or your key, so agents never do them (CLAUDE.md §6).

## 1. Upload key (you, once)

Keep the key outside the repo and back it up. If it's lost, Play support has to reset it.

```
keytool -genkeypair -v -keystore K:\Projects\keys\mediahro-upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000
```

Create `K:\Projects\Mediahro\app\android\key.properties`. It is gitignored and never committed:

```
storeFile=K:\\Projects\\keys\\mediahro-upload.jks
storePassword=<your password>
keyAlias=upload
keyPassword=<your password>
```

## 2. Build the bundle

Run this once the Android work for the test build is merged. The orchestrator gives you the exact build number, or you can run it yourself:

```
cd K:\Projects\Mediahro\app
flutter build appbundle --release --flavor store --dart-define=MEDIAHRO_FLAVOR=store --build-name=0.1.0 --build-number=<N> --obfuscate --split-debug-info=build\symbols\0.1.0-<N>
```

Output: `app\build\app\outputs\bundle\storeRelease\app-store-release.aab`. Keep `build\symbols\…`, because crash stack traces from this build can only be decoded with it.

## 3. Play Console (you)

1. **Create app:** name *Mediahro*, default language English (United States) (en-US), App, Free. Accept the declarations.
2. **Testing › Internal testing › Create new release.** Accept Play App Signing, so Google holds the app signing key and yours stays the upload key. Upload the `.aab` and paste the release notes below.
3. **Testers:** create an email list (up to 100) and copy the opt-in link for your testers.
4. **App content:** Play may require these before the first rollout. Suggested answers:
   - Privacy policy URL: required once the app requests media permissions. Use the site's privacy page; if it isn't live yet, that's an owner task in STATUS.md §4.
   - Ads: **No ads.**
   - App access: all functionality is available without login.
   - Content rating: complete the questionnaire. A media player with no user-generated content and no communication features typically rates *Everyone*.
   - Target audience: 13+ (not designed for children).
   - Data safety: **no data collected or shared** (no accounts, no telemetry by default; opt-in crash reports are not in this build).
   - Photo and video permissions: a media player and gallery are the core function, so it needs broad access to the user's videos and photos. Photo Picker is offered where the user prefers it.
   - Foreground service (media playback): background audio and video playback that the user starts, with media controls in the notification.
5. **Review and roll out** to internal testing. Internal tests usually reach testers within minutes.

## 4. Release notes (en-US, paste into the release)

```
First internal test of Mediahro for Android.
- Browse your device's videos, music and photos (no account, no ads).
- Video player: gestures, speed, audio and subtitle tracks, resume where you left off.
- Music library with background playback and lock-screen controls.
Known gaps in this test: casting, server libraries (Jellyfin, Plex, etc.), photo editing and the supporter page are not in this build yet.
Please report problems with steps to reproduce and your phone model.
```

The final notes are updated to match what actually ships before you upload.

## 5. After upload

Tell the orchestrator the build number you uploaded and any Play pre-launch report warnings. It records the upload-key SHA-256 fingerprint for Android developer verification (docs/07 §3) in STATUS.md §4.
