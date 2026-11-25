# FFmpeg 9.1 Android JNI Build — Production Guide

This guide documents the complete compilation, verification, and integration process for the **FFmpeg 9.1** shared library backend for the **yt-dlp Android GUI**.

---

## 1. Summary of Completed Builds

All requested binaries have been successfully compiled, stripped, and packaged in [`ffmpeg_yt-dlp_gui/release/`](file:///c:/Users/naska/OneDrive/Documents/GitHub/ffmpeg_yt-dlp_gui/release):

| Target ABI | CPU Architecture | Min API | Release Zip | SHA256 Checksum |
|---|---|---|---|---|
| **`arm64-v8a`** | 64-bit ARM (ARMv8-A) | 24 | `ffmpeg-android-9.1-arm64-v8a.zip` (3.5 MB) | `7033c674f8c29ab9c07ec24928dc8c1b0120c281cd93807a9182a44ffb072150` |
| **`armeabi-v7a`** | 32-bit ARM (ARMv7-A) | 24 | `ffmpeg-android-9.1-armeabi-v7a.zip` (2.9 MB) | `11d47a9ae4ecde5bbf9dd9e02e2842fe9d90c13a166d5220a81e2798ccb922d2` |
| **`x86_64`** | 64-bit x86 (Emulator) | 24 | `ffmpeg-android-9.1-x86_64.zip` (3.9 MB) | `2978016b8e613433d45ef91c7b3007495bcc4251385df73ed41b05e224ce4d42` |
| **`all-abis`** | Full `jniLibs/` tree | 24 | `ffmpeg-android-9.1-all-abis.zip` (11 MB) | `a1e90996534071be3ce4ee2920d5b18a47f689465bbf7104cb5f7ad59bf6a37d` |

---

## 2. Generated Shared Libraries (`android-lib/src/main/jniLibs/`)

Each ABI directory contains the following 7 `.so` libraries:

```
android-lib/src/main/jniLibs/
├── arm64-v8a/
│   ├── libavcodec.so      (4.3 MB)
│   ├── libavfilter.so     (198 KB)
│   ├── libavformat.so     (940 KB)
│   ├── libavutil.so       (739 KB)
│   ├── libffmpeg_jni.so   (341 KB)
│   ├── libswresample.so   (102 KB)
│   └── libswscale.so      (1.2 MB)
├── armeabi-v7a/
│   ├── libavcodec.so      (3.1 MB)
│   ├── libavfilter.so     (130 KB)
│   ├── libavformat.so     (688 KB)
│   ├── libavutil.so       (513 KB)
│   ├── libffmpeg_jni.so   (318 KB)
│   ├── libswresample.so   (78 KB)
│   └── libswscale.so      (633 KB)
└── x86_64/
    ├── libavcodec.so      (6.2 MB)
    ├── libavfilter.so     (210 KB)
    ├── libavformat.so     (977 KB)
    ├── libavutil.so       (877 KB)
    ├── libffmpeg_jni.so   (349 KB)
    ├── libswresample.so   (142 KB)
    └── libswscale.so      (1.6 MB)
```

---

## 3. Architecture & Key Technical Solutions

### Why JNI Shared Libraries?
1. **Android Security Boundaries**: Android 10+ (API 29+) enforces W^X in application private directories, preventing `execve()` on binaries in `context.filesDir`. Android 14+ (API 34+) further restricts dynamic loading of non-read-only `.so` files outside APK packaging.
2. **Linker Trust**: Libraries placed in `jniLibs/` within the APK/AAB are extracted by `PackageManager` into the system's trusted library directory (`nativeLibraryDir`), allowing standard `System.loadLibrary()` calls without permission errors on all Android versions (API 24 to 35+).
3. **16 KB Page Alignment**: Linked with `-Wl,-z,max-page-size=16384` to ensure compliance with Android 15's 16 KB memory page size requirements on ARM64 hardware.

### Cancellation Handling
FFmpeg 9.1's transcode loop and I/O interrupt callback cooperatively monitor `received_nb_signals`:
- In `ffmpeg_jni.c`, `nativeCancelFFmpeg()` checks `g_ffmpeg_running` and sends `raise(SIGINT)` at most once per active `ffmpeg_main()` run.
- This executes FFmpeg's registered `sigterm_handler(SIGINT)` in `ffmpeg.c`, which sets `received_nb_signals++` and `term_exit_sigsafe()`.
- The transcode loop aborts cleanly, and `ffmpeg_main()` returns code 255.

---

## 4. Kotlin Integration in `Android_yt-dlp_GUI`

### Step 1: Copy Native Libraries
Copy the generated `jniLibs` directly to the main Android project:
```powershell
Copy-Item -Recurse `
  c:\Users\naska\OneDrive\Documents\GitHub\ffmpeg_yt-dlp_gui\android-lib\src\main\jniLibs\* `
  c:\Users\naska\OneDrive\Documents\GitHub\Android_yt-dlp_GUI\app\src\main\jniLibs\
```

### Step 2: Copy Kotlin Bridge
Copy `FFmpegBridge.kt` from `ffmpeg_yt-dlp_gui/android-lib/src/main/kotlin/com/ytdlp/ffmpeg/FFmpegBridge.kt` into `Android_yt-dlp_GUI/app/src/main/kotlin/com/ytdlp/android/engine/`.

### Step 3: Configure `app/build.gradle.kts`
Ensure uncompressed packaging for faster mmap loading:
```kotlin
android {
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}
```

### Step 4: Initialize and Call from Kotlin
In `YtDlpApp.kt`:
```kotlin
class YtDlpApp : Application() {
    override fun onCreate() {
        super.onCreate()
        FFmpegBridge.init()
    }
}
```

In `YtDlpEngine.kt` or `DownloadService.kt`:
```kotlin
// Example: Post-process remuxing without spawning a subprocess
val exitCode = FFmpegBridge.muxToMp4(
    videoInput = videoFile.absolutePath,
    audioInput = audioFile.absolutePath,
    output = outputFile.absolutePath
)
if (exitCode == 0) {
    Log.i("YtDlpEngine", "Muxing successful via JNI")
}
```
