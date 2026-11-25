package com.ytdlp.ffmpeg

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * FFmpegBridge — Kotlin API for the FFmpeg JNI wrapper.
 *
 * This class is the primary entry point for running FFmpeg operations
 * from the yt-dlp Android GUI. It wraps the native JNI functions
 * and provides a coroutine-friendly API.
 *
 * ## Loading
 *
 * Call [FFmpegBridge.init] once (e.g., in Application.onCreate) to load
 * the native libraries. For bundled mode (libraries in APK jniLibs),
 * this uses System.loadLibrary(). For runtime-download mode, use
 * [FFmpegLoader.loadFromFilesDir] before calling [init].
 *
 * ## Usage
 *
 * ```kotlin
 * // In Application.onCreate():
 * FFmpegBridge.init(context)
 *
 * // Running an FFmpeg command:
 * val result = FFmpegBridge.runFFmpeg(
 *     "-i", "input.mkv",
 *     "-c:a", "aac",
 *     "-c:v", "copy",
 *     "output.mp4"
 * )
 * if (result == 0) { /* success */ }
 * ```
 */
object FFmpegBridge {

    private const val TAG = "FFmpegBridge"

    @Volatile
    private var isLoaded = false

    // ─────────────────────────────────────────────────────────────────────────
    // Initialization
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Initialize the FFmpeg JNI bridge.
     *
     * In bundled mode (default): loads [libffmpeg_jni.so] and its dependencies
     * from the APK's `jniLibs/` using System.loadLibrary().
     *
     * In download mode: call [FFmpegLoader.loadFromFilesDir] first, which
     * loads the .so files directly via System.load(), then call this.
     *
     * @param fromJniLibs If true, load via System.loadLibrary (bundled APK mode).
     *                    If false, assume .so files are already loaded externally.
     */
    fun init(fromJniLibs: Boolean = true) {
        if (isLoaded) return
        synchronized(this) {
            if (isLoaded) return
            try {
                if (fromJniLibs) {
                    // Load in dependency order — Android linker resolves these
                    // from the APK's jniLibs/<abi>/ automatically when using
                    // System.loadLibrary(), but we must load in order for
                    // System.load() (file path) mode.
                    System.loadLibrary("avutil")
                    System.loadLibrary("swresample")
                    System.loadLibrary("swscale")
                    System.loadLibrary("avcodec")
                    System.loadLibrary("avformat")
                    System.loadLibrary("avfilter")
                    System.loadLibrary("ffmpeg_jni")
                }
                isLoaded = true
                Log.i(TAG, "FFmpeg JNI loaded: ${getFFmpegVersion()}")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to load FFmpeg native libraries", e)
                throw e
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Run an FFmpeg command asynchronously.
     *
     * @param args FFmpeg arguments (without the leading "ffmpeg").
     *             Example: ["-i", "in.mkv", "-c:a", "aac", "out.mp4"]
     * @return Exit code: 0 = success, 1 = error, negative = cancelled.
     */
    suspend fun runFFmpegAsync(vararg args: String): Int = withContext(Dispatchers.IO) {
        checkLoaded()
        Log.d(TAG, "runFFmpeg: ${args.joinToString(" ")}")
        val result = nativeRunFFmpeg(args.toTypedArray())
        Log.d(TAG, "runFFmpeg exit code: $result")
        result
    }

    /**
     * Run an FFmpeg command synchronously (blocking).
     * Must be called from a background thread.
     *
     * @param args FFmpeg arguments (without the leading "ffmpeg").
     * @return Exit code: 0 = success, 1 = error.
     */
    fun runFFmpeg(vararg args: String): Int {
        checkLoaded()
        Log.d(TAG, "runFFmpeg: ${args.joinToString(" ")}")
        return nativeRunFFmpeg(args.toTypedArray())
    }

    /**
     * Cancel the currently running FFmpeg operation.
     * This is a best-effort, cooperative cancellation — FFmpeg checks
     * the cancel flag at regular intervals during processing.
     */
    fun cancelFFmpeg() {
        if (!isLoaded) return
        nativeCancelFFmpeg()
    }

    /**
     * Returns the FFmpeg version string.
     * Example: "FFmpeg 9.0.2 (avutil=59.x.x avcodec=61.x.x avformat=61.x.x)"
     */
    fun getFFmpegVersion(): String {
        checkLoaded()
        return nativeGetFFmpegVersion()
    }

    /**
     * Returns true if the FFmpeg libraries are loaded and ready.
     */
    fun isAvailable(): Boolean = isLoaded

    // ─────────────────────────────────────────────────────────────────────────
    // Convenience helpers for yt-dlp GUI use cases
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Mux video + audio into an MP4 container (stream copy — no re-encode).
     * This is the primary use case: merging yt-dlp's video-only + audio-only
     * streams after download.
     *
     * @param videoInput Path to video-only file (e.g., .webm, .mp4)
     * @param audioInput Path to audio-only file (e.g., .m4a, .webm)
     * @param output Path to output MP4 file
     * @param extraArgs Additional FFmpeg flags (e.g., "-strict", "-2")
     * @return Exit code: 0 = success
     */
    suspend fun muxToMp4(
        videoInput: String,
        audioInput: String,
        output: String,
        vararg extraArgs: String
    ): Int {
        val args = buildList {
            add("-y")                    // overwrite output
            add("-i"); add(videoInput)
            add("-i"); add(audioInput)
            add("-c:v"); add("copy")     // stream-copy video
            add("-c:a"); add("copy")     // stream-copy audio
            addAll(extraArgs)
            add("-movflags"); add("+faststart")  // optimize for streaming
            add(output)
        }
        return runFFmpegAsync(*args.toTypedArray())
    }

    /**
     * Re-encode audio to AAC (for compatibility when stream-copy fails).
     *
     * @param input  Source audio file
     * @param output Output file (e.g., .m4a)
     * @param bitrate Audio bitrate (e.g., "192k")
     */
    suspend fun encodeAudioToAac(
        input: String,
        output: String,
        bitrate: String = "192k"
    ): Int = runFFmpegAsync(
        "-y", "-i", input,
        "-c:a", "aac",
        "-b:a", bitrate,
        "-vn",
        output
    )

    /**
     * Embed subtitles into an MKV container (soft subtitles, no burn-in).
     *
     * @param videoInput  Input video file
     * @param subtitleInput  Subtitle file (.srt, .ass, .vtt)
     * @param output  Output MKV file
     * @param language  Subtitle language tag (e.g., "en", "ja")
     */
    suspend fun embedSubtitles(
        videoInput: String,
        subtitleInput: String,
        output: String,
        language: String = "und"
    ): Int = runFFmpegAsync(
        "-y",
        "-i", videoInput,
        "-i", subtitleInput,
        "-c:v", "copy",
        "-c:a", "copy",
        "-c:s", "srt",
        "-metadata:s:s:0", "language=$language",
        output
    )

    // ─────────────────────────────────────────────────────────────────────────
    // Private
    // ─────────────────────────────────────────────────────────────────────────

    private fun checkLoaded() {
        check(isLoaded) {
            "FFmpegBridge not initialized. Call FFmpegBridge.init() first."
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Native method declarations
    // ─────────────────────────────────────────────────────────────────────────

    @JvmStatic
    private external fun nativeRunFFmpeg(args: Array<String>): Int

    @JvmStatic
    private external fun nativeCancelFFmpeg()

    @JvmStatic
    private external fun nativeGetFFmpegVersion(): String
}
