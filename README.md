# ffmpeg-yt-dlp-gui

A purpose-built **FFmpeg 9.1 Android library** compiled as JNI shared libraries for use as the post-processing backend in [Android yt-dlp GUI](https://github.com/Samyak-2212/Android_yt-dlp_GUI).

---

## Architecture

Compiles FFmpeg 9.1 into **modular Android shared libraries (`.so`) and a JNI wrapper (`libffmpeg_jni.so`)** for in-process execution on Android 7.0+ (API 24+) through Android 15+ (API 35+).

```
Kotlin (FFmpegBridge.kt)
  └─ JNI → libffmpeg_jni.so          (wraps ffmpeg_main → runFFmpeg / runFFmpegJson)
             ├─ libavcodec.so
             ├─ libavformat.so
             ├─ libavfilter.so
             ├─ libavutil.so
             ├─ libswresample.so
             └─ libswscale.so
```

Bundled in `jniLibs/` across `arm64-v8a`, `armeabi-v7a`, and `x86_64`, the libraries are loaded via `System.loadLibrary()` on app startup with 16 KB ELF page alignment (`-Wl,-z,max-page-size=16384`). For design rationale and legacy binary comparisons, see [ffmpeg-android-jni-guide.md](ffmpeg-android-jni-guide.md).

---

## Built Release Artifacts (`release/`)

| Archive | ABIs Included | Compressed Size | SHA-256 Checksum |
|---|---|---|---|
| `ffmpeg-android-9.1-arm64-v8a.zip` | `arm64-v8a` (64-bit ARM) | **3.5 MB** | `7033c674f8c29ab9c07ec24928dc8c1b0120c281cd93807a9182a44ffb072150` |
| `ffmpeg-android-9.1-armeabi-v7a.zip` | `armeabi-v7a` (32-bit ARM) | **2.9 MB** | `11d47a9ae4ecde5bbf9dd9e02e2842fe9d90c13a166d5220a81e2798ccb922d2` |
| `ffmpeg-android-9.1-x86_64.zip` | `x86_64` (Emulator) | **3.9 MB** | `2978016b8e613433d45ef91c7b3007495bcc4251385df73ed41b05e224ce4d42` |
| `ffmpeg-android-9.1-all-abis.zip` | All 3 ABIs (`jniLibs/` tree) | **11 MB** | `a1e90996534071be3ce4ee2920d5b18a47f689465bbf7104cb5f7ad59bf6a37d` |

---

## Compiled Libraries per ABI

Each target ABI contains 7 stripped shared libraries:

| Library | arm64-v8a | armeabi-v7a | x86_64 | Purpose |
|---|---|---|---|---|
| `libavcodec.so` | 4.3 MB | 3.1 MB | 6.2 MB | AAC, Opus, FLAC, ALAC, H.264, HEVC, VP9, AV1, SRT/ASS/WebVTT/mov_text |
| `libavformat.so` | 940 KB | 688 KB | 977 KB | MP4, MOV, iPod/M4A, MKV, WebM, OGG, Opus, MP3, WAV, SRT/ASS/WebVTT |
| `libavfilter.so` | 198 KB | 130 KB | 210 KB | Audio resampling, volume, pan, scale filters |
| `libavutil.so` | 739 KB | 513 KB | 877 KB | Math, memory, data structures, logging |
| `libswresample.so` | 102 KB | 78 KB | 142 KB | Audio format and sample rate conversion |
| `libswscale.so` | 1.2 MB | 633 KB | 1.6 MB | Color space conversion and picture scaling |
| `libffmpeg_jni.so` | 341 KB | 318 KB | 349 KB | **JNI Bridge** (wraps `ffmpeg_main`, handles CLI argv & signal-safe cancel) |

---

## Technical Highlights (FFmpeg 9.1 Integration)

1. **Re-entrant Embedded Execution**:
   FFmpeg 9.1 `fftools/ffmpeg.c` resets static globals at the start of `main()` (compiled with `-Dmain=ffmpeg_main`) for safe repeated in-process invocations.

2. **Clean Signal-Safe Cancellation Support**:
   Invoking `nativeCancelFFmpeg()` checks `g_ffmpeg_running` and sends `raise(SIGINT)` at most once per active `ffmpeg_main()` run, triggering FFmpeg's `sigterm_handler()` without risking `SIG_DFL` process termination when idle.

3. **16 KB Page Alignment**:
   All `.so` files are compiled and linked with `-Wl,-z,max-page-size=16384`, fulfilling the mandatory requirement for devices running Android 15 (API 35+) on ARM64.

4. **Optimized Minimal Footprint**:
   Configured with `--disable-everything` and selective enablement of the codecs, formats, and filters needed by `yt-dlp` (MP4/MKV muxing, AAC/MP3/Opus audio extraction, soft subtitle embedding).

---

## Build Commands

From the MSYS2 MSYS shell (`C:\msys64\msys2.exe`):

```bash
cd /c/Users/naska/OneDrive/Documents/GitHub/ffmpeg_yt-dlp_gui

# 1. Build FFmpeg shared libraries for all ABIs (or specify --abi=arm64-v8a)
./build.sh

# 2. Build JNI wrapper (libffmpeg_jni.so) and populate jniLibs/
./build-jni-wrapper.sh

# 3. Package release zip files with SHA256 checksums
./package-release.sh
```

---

## Integration into Android yt-dlp GUI

### Option 1: Direct `jniLibs/` copy (Recommended)

Copy the pre-built `jniLibs/` directly into the Android application:

```powershell
Copy-Item -Recurse `
  c:\Users\naska\OneDrive\Documents\GitHub\ffmpeg_yt-dlp_gui\android-lib\src\main\jniLibs\* `
  c:\Users\naska\OneDrive\Documents\GitHub\Android_yt-dlp_GUI\app\src\main\jniLibs\
```

Copy `FFmpegBridge.kt` into `app/src/main/kotlin/com/ytdlp/ffmpeg/`.

In `app/build.gradle.kts`:
```kotlin
android {
    packaging {
        jniLibs {
            useLegacyPackaging = false  // uncompressed .so for fast mmap
        }
    }
}
```

In `MainActivity.kt` or `YtDlpApp.kt`:
```kotlin
FFmpegBridge.init()
```

Run FFmpeg operations directly:
```kotlin
val exitCode = FFmpegBridge.muxToMp4(
    videoInput = videoFile.absolutePath,
    audioInput = audioFile.absolutePath,
    output = outputFile.absolutePath
)
```

### Option 2: Android Library Module (`.aar`)

Build the standalone Android Archive:
```powershell
cd android-lib
.\gradlew assembleRelease
```
Add the output `.aar` to the app's `libs/` folder.
