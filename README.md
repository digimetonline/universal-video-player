# Universal Video Player (Android)

A native Android video player built with Flutter + media_kit (libmpv/FFmpeg),
following the attached PRD's recommended stack. Plays virtually any format:
MKV, MP4, AVI, MOV, WebM, HEVC/H.265, H.264, plus network streams (HLS `.m3u8`,
DASH `.mpd`, direct MP4 URLs).

## Features (MVP)

- Open local files (picker, SAF-based — no storage permission needed)
- Open network streams (http/https, HLS, DASH)
- Play/pause, seek bar with buffering indicator, ±10s (buttons or double-tap
  left/right of the screen)
- Playback speed 0.25x – 3x
- Subtitles: embedded tracks, auto/off, and loading external .srt / .vtt /
  .ass / .ssa / .sub files
- Audio track selection for multi-audio files
- Fullscreen (landscape + immersive mode)
- Auto-resume where you left off (per video), recent files list
- Screen stays awake during playback
- 100% local: no accounts, no tracking, works offline

## Option 1: Build the APK with GitHub (no install on your PC)

GitHub Actions builds it in the cloud for free. You never install Flutter.

1. Create a GitHub account if you don't have one, then create a **new
   repository** (e.g. `universal-video-player`, public or private).
2. On the repo page: **Add file → Upload files**, and drag in the contents of
   this folder (the `lib` folder, `.github` folder, `pubspec.yaml`, `README.md`).
   Tip: drag folders directly into the upload area in Chrome/Edge — GitHub
   keeps the folder structure. Commit the files.
3. The build starts automatically. Watch it under the **Actions** tab
   (takes ~5-10 minutes). You can also start it manually there:
   **Actions → Build Android APK → Run workflow**.
4. When it finishes, open that run → scroll to **Artifacts** → download
   `app-release-apk` (it's a zip; the APK is inside).
5. Copy the APK to your phone and open it to install (allow
   "install from unknown sources" when asked).

## Option 2: Build on your own PC

1. **Install the toolchain** (one time)
   - Install Flutter SDK 3.22+ and Android Studio (with Android SDK).
   - Run `flutter doctor` and fix anything it flags, including
     `flutter doctor --android-licenses`.
2. **Create the project**
   ```bash
   flutter create --org com.dailycome universal_video_player
   cd universal_video_player
   ```
3. **Drop in these files**
   - Replace `pubspec.yaml` with the one in this folder.
   - Replace `lib/main.dart` with the one in this folder.
4. **Add the INTERNET permission** in
   `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```
5. **Get packages and run**
   ```bash
   flutter pub get
   flutter run          # with a device/emulator connected
   ```
6. **Build the installable APK**
   ```bash
   flutter build apk --release
   ```
   Output: `build/app/outputs/flutter-apk/app-release.apk`

## Notes

- Broad codec support comes from `media_kit_libs_android_video`, which bundles
  FFmpeg-based decoders (same engine family as VLC/MPV). HEVC, MKV, AVI, DTS
  etc. work on Android, unlike a browser-based web version.
- If a local build complains about `minSdkVersion`, set
  `minSdkVersion flutter.minSdkVersion` (or 21) in
  `android/app/build.gradle`.
- Roadmap ideas from the PRD not yet in this MVP: light theme toggle, media
  info panel, swipe brightness/volume gestures, playlists, picture-in-picture.
